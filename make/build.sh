#!/usr/bin/env bash

set -euo pipefail

build_task() {
    output_file="/releases/make-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add \
        build-base \
        clang

    tar -xf "/work/downloads/make-$VERSION.tar.gz"
    cd "/make-$VERSION"

    PREFIX="/opt/make-$VERSION"

    export CC=clang
    LDFLAGS=-static ./configure --prefix="$PREFIX"

    make -j4
    make install

    if ldd "$PREFIX/bin/make"; then
        echo "make is not statically linked"
        exit 1
    fi

    strip "$PREFIX/bin/make"
    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    make="$install_dir/bin/make"

    tar -C "$install_dir" -xf "/releases/make-$VERSION-linux-$(uname -m).tar.gz"

    set -x
    cd /tmp
    cat << EOM >> Makefile
.PHONY: sanity_check

sanity_check:
	@echo "the quick brown fox jumps over the lazy dog" > test.txt
EOM

    "$make"
    grep -F "the quick brown fox jumps over the lazy dog" test.txt
    set +x

    rm -rf "$install_dir"
}

build_platform() {
    docker run \
        -it \
        --rm \
        --platform "$1" \
        -v "$PWD:/work:ro,delegated" \
        -v "$PWD/releases:/releases" \
        -e VERSION="$VERSION" \
        alpine:3 sh -c "apk add bash; /work/make/build.sh build_task"

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
            "$image" $shell /work/make/build.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")/.."
    VERSION=4.4.1

    mkdir -p downloads releases
    wget -nv -N -P downloads "https://ftp.gnu.org/gnu/make/make-$VERSION.tar.gz"

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi
