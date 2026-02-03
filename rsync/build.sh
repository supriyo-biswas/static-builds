#!/usr/bin/env bash

set -euo pipefail

VERSION=3.4.1
LZ4_VERSION=1.10.0
XXHASH_VERSION=0.8.2

build_task() {
    output_file="/releases/rsync-$VERSION-linux-$(uname -m).tar.gz"
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
        zstd-dev \
        zstd-static \
        attr-dev \
        attr-static \
        acl-dev \
        acl-static

    export CC=clang

    tar -xf "/work/downloads/xxhash/v$XXHASH_VERSION.tar.gz"
    cd "/xxHash-$XXHASH_VERSION"
    LDFLAGS=-static make
    MAKE_DIR=/usr make install
    cd ..

    tar -xf "/work/downloads/lz4/v$LZ4_VERSION.tar.gz"
    cd "/lz4-$LZ4_VERSION"
    make
    make install
    cd ..

    tar -xf "/work/downloads/rsync-$VERSION.tar.gz"
    cd "/rsync-$VERSION"

    PREFIX="/opt/rsync-$VERSION"

    LDFLAGS="-static" PKG_CONFIG="pkg-config --static" ./configure \
        --prefix="$PREFIX" \
        --enable-ipv6 \
        --with-included-zlib \
        --with-included-popt \
        --disable-md2man \
        --disable-locale

    make -j4
    make install

    if ldd "$PREFIX/bin/rsync"; then
        echo "ssh is not statically linked"
        exit 1
    fi

    if [ -n "$(find "$PREFIX/bin" -type f -exec grep -a "$PREFIX" {} \;)" ]; then
        echo "Binary contains references to $PREFIX"
        exit 1
    fi

    strip "$PREFIX/bin/rsync"
    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    chmod 755 "$install_dir"
    tar -C "$install_dir" -xf "/releases/rsync-$VERSION-linux-$(uname -m).tar.gz"
    rsync="$install_dir/bin/rsync"

    ln -s "$rsync" /usr/local/bin/rsync

    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        --no-install-recommends openssh-server openssh-client
    mkdir -p /run/sshd
    /usr/sbin/sshd
    sleep 3

    adduser --disabled-password --gecos "" testuser

    mkdir /home/testuser/.ssh ~/.ssh
    ssh-keyscan localhost > /home/testuser/.ssh/known_hosts
    ssh-keygen -t rsa -f /home/testuser/.ssh/id_rsa -N ""
    cp /home/testuser/.ssh/id_rsa.pub ~/.ssh/authorized_keys
    chown -R testuser: /home/testuser/.ssh
    chmod 400 ~/.ssh/authorized_keys

    mkdir /source /target
    for i in $(seq 1 10); do
        dd if=/dev/zero of="/source/file$i.bin" bs=1M count=2 2>/dev/null
    done

    chown -R testuser: /source
    su testuser -c "$rsync -az /source/ root@localhost:/target"

    source_files=$(find /source -type f -printf '%u:%g %f\n' | sort)
    target_files=$(find /target -type f -printf '%u:%g %f\n' | sort)
    if [ "$source_files" != "$target_files" ]; then
        echo "rsync failed to copy files"
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
        alpine:3 sh -c "apk add --cache-dir /var/cache/apk bash; /work/rsync/build.sh build_task"

    # shellcheck disable=SC1091
    . ./common/constants.sh
    for image in $TEST_SSH_IMAGES; do
        docker run \
            -it \
            --rm \
            --platform "$1" \
            -v "$PWD:/work:ro,delegated" \
            -v "$PWD/releases:/releases" \
            -e "VERSION=$VERSION" \
            "$image" /bin/bash /work/rsync/build.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")/.."

    mkdir -p downloads releases
    wget -nv -N -P downloads \
        "https://www.samba.org/ftp/rsync/src/rsync-$VERSION.tar.gz"

    wget -nv -N -P downloads/xxhash \
        "https://github.com/Cyan4973/xxHash/archive/refs/tags/v$XXHASH_VERSION.tar.gz"

    wget -nv -N -P downloads/lz4 \
        "https://github.com/lz4/lz4/archive/refs/tags/v$LZ4_VERSION.tar.gz"

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi
