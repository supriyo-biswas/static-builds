#!/usr/bin/env bash

set -euo pipefail

VERSION=1.0.8

build_task() {
    output_file="/releases/bzip2-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add --cache-dir /var/cache/apk \
        build-base \
        clang \
        coreutils \
        file

    tar -xf "/work/downloads/bzip2-$VERSION.tar.gz"
    cd "/bzip2-$VERSION"

    PREFIX="/opt/bzip2-$VERSION"
    make CC=clang CFLAGS="-Wall -O2 -static" LDFLAGS="-static"
    make install PREFIX="$PREFIX"

    # shellcheck disable=SC1091
    . /work/common/functions.sh
    symlink_dups "$PREFIX/bin"
    convert_symlinks "$PREFIX/bin"

    find "$PREFIX/bin" -type f -exec file --mime-type {} + | \
        awk '$2 == "application/x-executable" { print substr($1,0,length($1)-1); }' | \
        xargs -r strip

    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    bzip2="$install_dir/bin/bzip2"

    tar -C "$install_dir" -xf "/releases/bzip2-$VERSION-linux-$(uname -m).tar.gz"

    set -x
    cd /tmp
    echo "the quick brown fox jumps over the lazy dog" > test.txt
    echo "jackdaws love my big sphinx of quartz" >> test.txt

    "$bzip2" test.txt
    [[ ! -f test.txt ]]
    [[ "$(od -N3 -t x1 test.txt.bz2 | head -n 1)" == "0000000 42 5a 68" ]]

    "$bzip2" -d test.txt.bz2
    [[ ! -f test.txt.bz2 ]]

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
        alpine:3 sh -c "apk add --cache-dir /var/cache/apk bash; /work/bzip2/build.sh build_task"

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
            "$image" $shell /work/bzip2/build.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")/.."
    mkdir -p downloads releases
    wget -nv -N -P downloads "https://sourceware.org/pub/bzip2/bzip2-$VERSION.tar.gz"

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi
