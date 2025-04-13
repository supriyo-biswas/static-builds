#!/usr/bin/env bash

set -euo pipefail

build_task() {
    output_file="/releases/busybox-minimal-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apt update
    apt install -y -qq build-essential

    tar -xf "/work/downloads/busybox-$VERSION.tar.bz2"
    cd "/busybox-$VERSION"

    cp /work/busybox-minimal/.config ./
    make

    if ldd busybox; then
        echo "busybox is not statically linked"
        exit 1
    fi

    mkdir bin
    mv busybox bin/
    tar --numeric-owner -czf "$output_file" bin
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    busybox="$install_dir/bin/busybox"

    tar -C "$install_dir" -xf "/releases/busybox-minimal-$VERSION-linux-$(uname -m).tar.gz"

    set -x
    "$busybox" --help 2>&1 | grep -qE "^BusyBox .* multi-call binary"
}

build_platform() {
    docker run \
        -it \
        --rm \
        --platform "$1" \
        -v "$PWD:/work:ro,delegated" \
        -v "$PWD/releases:/releases" \
        -e VERSION="$VERSION" \
        ubuntu:24.04 /work/busybox-minimal/build.sh build_task

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
            "$image" $shell /work/busybox-minimal/build.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")/.."
    VERSION=1.37.0

    mkdir -p downloads releases
    wget -nv -N -P downloads "https://busybox.net/downloads/busybox-$VERSION.tar.bz2"

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi
