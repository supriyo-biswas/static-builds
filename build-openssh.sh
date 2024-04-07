#!/bin/sh

set -eu

build_task() {
    output_file="/releases/openssh-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add \
        build-base \
        clang \
        openssl-dev \
        openssl-libs-static \
        zlib-dev \
        zlib-static

    tar -xf "/work/downloads/openssh-$VERSION.tar.gz"
    cd "/openssh-$VERSION"

    PREFIX="/opt/openssh-$VERSION"

    export CC=clang
    LDFLAGS="-static" PKG_CONFIG="pkg-config --static" ./configure \
        --prefix="$PREFIX" \
        --sysconfdir=/etc/ssh \
        --without-rpath \
        --with-privsep-path=/var/lib/sshd \
        --with-default-path=/usr/bin \
        --with-superuser-path=/usr/sbin:/usr/bin \
        --with-pid-dir=/run

    make -j4
    make install

    if ldd "$PREFIX/bin/ssh"; then
        echo "ssh is not statically linked"
        exit 1
    fi

    find "$PREFIX/bin" "$PREFIX/libexec" -type f -exec strip {} +
    rm "$PREFIX/libexec/sftp-server"

    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin libexec
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    ssh="$install_dir/bin/ssh"
    ssh_keyscan="$install_dir/bin/ssh-keyscan"
    ssh_keygen="$install_dir/bin/ssh-keygen"

    tar -C "$install_dir" -xf "/releases/openssh-$VERSION-linux-$(uname -m).tar.gz"
    if ! "$ssh" -V 2>&1 | grep -q "^OpenSSH_$VERSION, OpenSSL "; then
        echo "ssh failed to run"
        exit 1
    fi

    if ! "$ssh_keygen" -t rsa -f ~/.ssh/id_rsa -N ""; then
        echo "ssh-keygen failed to run"
        exit 1
    fi

    cp ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys
    chmod 400 ~/.ssh/authorized_keys

    apt-get update -qq
    apt-get install -qq -y openssh-server
    mkdir -p /run/sshd
    /usr/sbin/sshd
    sleep 3

    "$ssh_keyscan" localhost > ~/.ssh/known_hosts

    # Kerberos/GSSAPI is not available in our build
    unlink /etc/ssh/ssh_config
    if ! timeout 5 "$ssh" root@localhost uptime | grep -q "load average"; then
        echo "ssh failed to connect to localhost"
        exit 1
    fi
}

build_platform() {
    docker run \
        --rm \
        --platform "$1" \
        -v "$PWD:/work:ro,delegated" \
        -v "$PWD/releases:/releases" \
        -e VERSION="$VERSION" \
        alpine:3 /work/build-openssh.sh build_task

    # shellcheck disable=SC1091
    . ./constants.sh
    for image in $TEST_SSH_IMAGES; do
        docker run \
            --rm \
            --platform "$1" \
            -v "$PWD:/work:ro,delegated" \
            -v "$PWD/releases:/releases" \
            -e "VERSION=$VERSION" \
            "$image" /work/build-openssh.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")"
    VERSION=9.7p1

    mkdir -p downloads releases
    wget -nv -N -P downloads \
        "https://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-$VERSION.tar.gz"

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi