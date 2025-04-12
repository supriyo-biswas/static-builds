#!/usr/bin/env bash

set -euo pipefail

build_task() {
    output_file="/releases/gnu-sed-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add \
        build-base \
        clang

    tar -xf "/work/downloads/sed-$VERSION.tar.gz"
    cd "/sed-$VERSION"

    PREFIX="/opt/sed-$VERSION"

    export CC=clang
    LDFLAGS="-static" ./configure --prefix="$PREFIX" --disable-rpath

    make -j4
    make install

    if ldd "$PREFIX/bin/sed"; then
        echo "sed is not statically linked"
        exit 1
    fi

    strip "$PREFIX/bin/sed"
    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin/sed
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    sed="$install_dir/bin/sed"

    tar -C "$install_dir" -xf "/releases/gnu-sed-$VERSION-linux-$(uname -m).tar.gz"

    set -x
    "$sed" --version | grep -q "(GNU sed) $VERSION"
    echo 'Hello World World' > /tmp/test.txt
    "$sed" -ri 's/W([a-z]+)/w\1/g' /tmp/test.txt
    grep -Fq 'Hello world world' /tmp/test.txt
}

build_platform() {
    docker run \
        -it \
        --rm \
        --platform "$1" \
        -v "$PWD:/work:ro,delegated" \
        -v "$PWD/releases:/releases" \
        -e VERSION="$VERSION" \
        alpine:3 sh -c "apk add bash; /work/gnu-sed/build.sh build_task"

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
            "$image" $shell /work/gnu-sed/build.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")/.."
    VERSION=4.9

    mkdir -p downloads releases
    wget -nv -N -P downloads "https://ftp.gnu.org/gnu/sed/sed-$VERSION.tar.gz"

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi
