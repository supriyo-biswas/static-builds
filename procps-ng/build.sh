#!/usr/bin/env bash

set -euo pipefail

build_task() {
    output_file="/releases/procps-ng-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add \
        build-base \
        clang \
        ncurses-dev \
        ncurses-static \
        perl

    tar -xf "/work/downloads/procps-ng-$VERSION.tar.xz"
    cd "/procps-ng-$VERSION"

    PREFIX="/opt/procps-ng-$VERSION"

    export CC=clang
    LDFLAGS="-static" PKG_CONFIG="pkg-config --static" ./configure \
        --prefix="$PREFIX" \
        --disable-shared \
        --enable-static \
        --disable-nls

    make -j4 LDFLAGS="-static -all-static"
    make install

    if ldd "$PREFIX/bin/ps"; then
        echo "procps-ng binaries are not statically linked"
        exit 1
    fi

    strip "$PREFIX/bin/"*
    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin/
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    ps="$install_dir/bin/ps"

    tar -C "$install_dir" -xf "/releases/procps-ng-$VERSION-linux-$(uname -m).tar.gz"
    if ! "$ps" --version | grep -Fq "ps from procps-ng $VERSION"; then
        echo "procps-ng failed to run"
        exit 1
    fi

    if ! "$ps" aux | grep -q "PID"; then
        echo "procps-ng ps command failed"
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
        -e VERSION="$VERSION" \
        alpine:3 sh -c "apk add bash; /work/procps-ng/build.sh build_task"

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
            "$image" $shell /work/procps-ng/build.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")/.."
    VERSION=4.0.5

    mkdir -p downloads releases
    wget -nv -N -P downloads "https://sourceforge.net/projects/procps-ng/files/Production/procps-ng-$VERSION.tar.xz"

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi