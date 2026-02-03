#!/usr/bin/env bash

set -euo pipefail

VERSION=10.2p1

build_task() {
    output_file="/releases/openssh-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add --cache-dir /var/cache/apk \
        build-base \
        clang \
        linux-headers \
        openssl-dev \
        openssl-libs-static \
        zlib-dev \
        zlib-static \
        makedepend \
        patch

    tar -xf "/work/downloads/openssh-$VERSION.tar.gz"
    cd "/openssh-$VERSION"

    patch -p1 < /work/openssh/patch.diff
    # shellcheck disable=SC2035
    makedepend -w1000 -Y. -f .depend *.c 2>/dev/null

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

    if [ -n "$(find "$PREFIX/bin" "$PREFIX/libexec" -type f -exec grep -a "$PREFIX" {} \;)" ]; then
        echo "Binary contains references to $PREFIX"
        exit 1
    fi

    rm "$PREFIX/libexec/sftp-server" "$PREFIX/libexec/sshd-session" "$PREFIX/libexec/sshd-auth"
    find "$PREFIX/bin" "$PREFIX/libexec" -type f -exec strip {} +

    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin libexec
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    ssh="$install_dir/bin/ssh"
    ssh_keyscan="$install_dir/bin/ssh-keyscan"
    ssh_keygen="$install_dir/bin/ssh-keygen"
    sftp="$install_dir/bin/sftp"
    scp="$install_dir/bin/scp"

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
    mkdir -p /run/sshd

    if grep -qE 'rhel|fedora' /etc/os-release; then
        yum install -y openssh-server procps
    elif grep -q alpine /etc/os-release; then
        apk add openssh-server
    else
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssh-server
    fi

    ssh-keygen -A
    /usr/sbin/sshd
    sleep 3

    "$ssh_keyscan" localhost > ~/.ssh/known_hosts

    # Kerberos/GSSAPI is not available in our build
    unlink /etc/ssh/ssh_config || true
    if ! (timeout 5 "$ssh" root@localhost uptime | grep -q "load average"); then
        echo "ssh failed to connect to localhost"
        exit 1
    fi

    if ! (echo "get /bin/cp /tmp/cp1" | "$sftp" root@localhost); then
        echo "sftp failed to copy"
        exit 1
    fi

    target_file_checksum=$(sha256sum /bin/cp | cut -d' ' -f1)
    if [ "$target_file_checksum" != "$(sha256sum /tmp/cp1 | cut -d ' ' -f1)" ]; then
        echo "sftp copy did not work properly"
        exit 1
    fi

    if ! "$scp" root@localhost:/bin/cp /tmp/cp2; then
        echo "scp failed to copy"
        exit 1
    fi

    if [ "$target_file_checksum" != "$(sha256sum /tmp/cp2 | cut -d ' ' -f1)" ]; then
        echo "scp copy did not work properly"
        exit 1
    fi
}

build_platform() {
    docker run \
        -it \
        --rm \
        --platform "$1" \
        -v "$PWD:/work:ro,delegated" \
        -v "$PWD/releases:/releases" \
        -v "static-builds-cache-${1/\//-}:/var/cache/apk" \
        alpine:3 sh -c "apk add --cache-dir /var/cache/apk bash; /work/openssh/build.sh build_task"

    # shellcheck disable=SC1091
    . ./common/constants.sh
    for image in $TEST_IMAGES; do
        docker run \
            -it \
            --rm \
            --platform "$1" \
            -v "$PWD:/work:ro,delegated" \
            -v "$PWD/releases:/releases" \
            -e "VERSION=$VERSION" \
            "$image" sh -c "grep -q alpine /etc/os-release && apk add bash; /work/openssh/build.sh sanity_check"
    done
}

main() {
    cd "$(dirname "$0")/.."
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
