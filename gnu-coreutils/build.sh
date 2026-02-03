#!/usr/bin/env bash

set -euo pipefail

VERSION=9.9

build_task() {
    output_file="/releases/gnu-coreutils-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add --cache-dir /var/cache/apk \
        build-base \
        clang \
        perl \
        libcap-dev \
        libcap-static \
        acl-dev \
        acl-static \
        attr-dev \
        attr-static \
        openssl-dev \
        openssl-libs-static

    tar -xf "/work/downloads/coreutils-$VERSION.tar.xz"
    cd "/coreutils-$VERSION"

    PREFIX="/opt/coreutils-$VERSION"

    export CC=clang
    FORCE_UNSAFE_CONFIGURE=1 LDFLAGS=-static ./configure \
        --prefix="$PREFIX" \
        --enable-single-binary=symlinks \
        --enable-no-install-program=kill,uptime,dir,vdir,stdbuf \
        --disable-rpath

    make -j4
    make install

    if ldd "$PREFIX/bin/coreutils"; then
        echo "coreutils is not statically linked"
        exit 1
    fi

    strip "$PREFIX/bin/coreutils"
    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    coreutils="$install_dir/bin/coreutils"

    tar -C "$install_dir" -xf "/releases/gnu-coreutils-$VERSION-linux-$(uname -m).tar.gz"
    set -x
    "$coreutils" --version | grep -Fq "coreutils (GNU coreutils) $VERSION"
    "$install_dir/bin/ls" -la "$install_dir/bin" > /tmp/ls_results.txt
    head -n 1 /tmp/ls_results.txt | grep -E "^total [0-9]+"
    tail -n 1 /tmp/ls_results.txt | grep -E "^lrwxrwxrwx 1 root root .* yes -> coreutils"

    [[ "$(echo -n 'the quick brown fox jumps over the lazy dog' | sha256sum)" == \
        "05c6e08f1d9fdafa03147fcb8f82f124c76d2f70e3d989dc8aadb5e7d7450bec  -" ]]
}

build_platform() {
    docker run \
        -it \
        --rm \
        --platform "$1" \
        -v "$PWD:/work:ro,delegated" \
        -v "$PWD/releases:/releases" \
        -v "static-builds-cache-${1/\//-}:/var/cache/apk" \
        alpine:3 sh -c "apk add --cache-dir /var/cache/apk bash; /work/gnu-coreutils/build.sh build_task"

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
            -e "VERSION=$VERSION" \
            "$image" $shell /work/gnu-coreutils/build.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")/.."
    mkdir -p downloads releases
    wget -nv -N -P downloads "https://ftp.gnu.org/gnu/coreutils/coreutils-$VERSION.tar.xz"

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi
