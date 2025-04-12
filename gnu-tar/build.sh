#!/usr/bin/env bash

set -euo pipefail

build_task() {
    output_file="/releases/gnu-tar-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add \
        build-base \
        clang \
        acl-dev \
        acl-static \
        attr-dev \
        attr-static \

    tar -xf "/work/downloads/tar-$VERSION.tar.gz"
    cd "/tar-$VERSION"

    PREFIX="/opt/tar-$VERSION"

    export CC=clang
    FORCE_UNSAFE_CONFIGURE=1 LDFLAGS=-static ./configure \
        --prefix="$PREFIX" \
        --disable-rpath \
        --disable-nls

    make -j4
    make install

    if ldd "$PREFIX/bin/tar"; then
        echo "tar is not statically linked"
        exit 1
    fi

    find "$PREFIX/bin" "$PREFIX/libexec" -type f -exec strip {} \;
    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin libexec
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    tar="$install_dir/bin/tar"

    tar -C "$install_dir" -xf "/releases/gnu-tar-$VERSION-linux-$(uname -m).tar.gz"

    set -x
    cd /tmp
    echo "the quick brown fox jumps over the lazy dog" > test.txt
    echo "jackdaws love my big sphinx of quartz" >> test.txt

    "$tar" -cf test.tar test.txt
    rm test.txt
    "$tar" -xf test.tar
    head -n 1 test.txt | grep -Fq "the quick brown fox jumps over the lazy dog"
    tail -n 1 test.txt | grep -Fq "jackdaws love my big sphinx of quartz"
    [[ "$(wc -l test.txt)" == "2 test.txt" ]]
    [[ "$(od -j257 -N5 -c test.tar | head -n 1)" == "0000401   u   s   t   a   r" ]]

    "$tar" -czf test.tar.gz test.txt
    rm test.txt
    "$tar" -xf test.tar.gz
    head -n 1 test.txt | grep -Fq "the quick brown fox jumps over the lazy dog"
    tail -n 1 test.txt | grep -Fq "jackdaws love my big sphinx of quartz"
    [[ "$(wc -l test.txt)" == "2 test.txt" ]]
    [[ "$(od -N2 -t x1 test.tar.gz | head -n 1)" == "0000000 1f 8b" ]]

    mkdir /custom
    if [[ $(uname -m) == x86_64 ]]; then
        ln -s /downloads/busybox-builds/busybox_amd64 /custom/gzip
    else
        ln -s /downloads/busybox-builds/busybox_arm64 /custom/gzip
    fi

    # ensure that compression programs are located from PATH
    unlink /bin/gzip || true
    unlink /usr/bin/gzip || true
    export PATH=/custom
    "$tar" -xf test.tar.gz
    [[ "$(/usr/bin/wc -l test.txt)" == "2 test.txt" ]]
}

build_platform() {
    docker run \
        -it \
        --rm \
        --platform "$1" \
        -v "$PWD:/work:ro,delegated" \
        -v "$PWD/releases:/releases" \
        -e VERSION="$VERSION" \
        alpine:3 sh -c "apk add bash; /work/gnu-tar/build.sh build_task"

    # for the aforementioned verification
    wget -nv -N -P downloads/busybox-builds \
        https://github.com/EXALAB/Busybox-static/raw/refs/heads/main/busybox_amd64 \
        https://github.com/EXALAB/Busybox-static/raw/refs/heads/main/busybox_arm64

    chmod +x downloads/busybox-builds/*

    # shellcheck disable=SC1091
    . ./common/constants.sh
    for image in $TEST_IMAGES; do
        case "$image" in
            alpine:*|busybox:*)
                shell=/bin/sh
                ;;
            *)
                shell=/bin/bash
                ;;
        esac

        docker run \
            -it \
            --rm \
            --platform "$1" \
            -v "$PWD:/work:ro,delegated" \
            -v "$PWD/releases:/releases" \
            -v "$PWD/downloads:/downloads:ro,delegated" \
            -e "VERSION=$VERSION" \
            "$image" $shell /work/gnu-tar/build.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")/.."
    VERSION=1.35

    mkdir -p downloads releases
    wget -nv -N -P downloads "https://ftp.gnu.org/gnu/tar/tar-$VERSION.tar.gz"

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi
