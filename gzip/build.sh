#!/usr/bin/env bash

set -euo pipefail

VERSION=1.14

build_task() {
    output_file="/releases/gzip-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add --cache-dir /var/cache/apk \
        build-base \
        clang

    tar -xf "/work/downloads/gzip-$VERSION.tar.gz"
    cd "/gzip-$VERSION"

    PREFIX="/opt/gzip-$VERSION"

    export CC=clang
    LDFLAGS=-static ./configure --prefix="$PREFIX"

    make -j4
    make install

    if ldd "$PREFIX/bin/gzip"; then
        echo "gzip is not statically linked"
        exit 1
    fi

    strip "$PREFIX/bin/gzip"
    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    gzip="$install_dir/bin/gzip"

    tar -C "$install_dir" -xf "/releases/gzip-$VERSION-linux-$(uname -m).tar.gz"

    set -x
    cd /tmp
    echo "the quick brown fox jumps over the lazy dog" > test.txt
    echo "jackdaws love my big sphinx of quartz" >> test.txt

    "$gzip" test.txt
    [[ ! -f test.txt ]]
    [[ "$(od -N2 -t x1 test.txt.gz | head -n 1)" == "0000000 1f 8b" ]]

    "$gzip" -d test.txt.gz
    [[ ! -f test.txt.gz ]]

    head -n 1 test.txt | grep -Fq "the quick brown fox jumps over the lazy dog"
    tail -n 1 test.txt | grep -Fq "jackdaws love my big sphinx of quartz"
    [[ "$(wc -l test.txt)" == "2 test.txt" ]]
}

build_platform() {
    docker run \
        -it \
        --rm \
        --platform "$1" \
        -v "$PWD:/work:ro,delegated" \
        -v "$PWD/releases:/releases" \
        -v "static-builds-cache-${1/\//-}:/var/cache/apk" \
        alpine:3 sh -c "apk add --cache-dir /var/cache/apk bash; /work/gzip/build.sh build_task"

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
            "$image" $shell /work/gzip/build.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")/.."
    mkdir -p downloads releases
    wget -nv -N -P downloads "https://ftp.gnu.org/gnu/gzip/gzip-$VERSION.tar.gz"

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi
