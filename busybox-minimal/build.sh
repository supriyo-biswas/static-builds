#!/usr/bin/env bash

set -euo pipefail

VERSION=1.38.0

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
    local applet applets busybox fdisk_help help_output sha384 version_output yescrypt

    if [ -n "${BUSYBOX_PATH:-}" ]; then
        busybox=$BUSYBOX_PATH
    else
        install_dir=$(mktemp -d /opt/XXXXXXXXXX)
        busybox="$install_dir/bin/busybox"
        tar -C "$install_dir" -xf "/releases/busybox-minimal-$VERSION-linux-$(uname -m).tar.gz"
    fi

    set -x
    help_output=$("$busybox" --help 2>&1)
    printf '%s\n' "$help_output" | grep -E "^BusyBox .* multi-call binary" >/dev/null
    version_output=$("$busybox" --version)
    printf '%s\n' "$version_output" | grep "BusyBox v$VERSION" >/dev/null

    applets=$("$busybox" --list)
    for applet in sha384sum lsblk uuidgen vmstat; do
        printf '%s\n' "$applets" | grep -x "$applet" >/dev/null
    done
    if printf '%s\n' "$applets" | grep -x ssl_server >/dev/null; then
        echo "ssl_server must remain disabled"
        return 1
    fi

    sha384=$(printf test | "$busybox" sha384sum)
    printf '%s\n' "$sha384" | grep '^768412320f7b0aa5812fce428dc4706b3cae50e02a64caa16a782249bfe8efc4b7ef1ccb126255d196047dfedf17a0a9  -$' >/dev/null
    yescrypt=$("$busybox" mkpasswd -m yescrypt test)
    printf '%s\n' "$yescrypt" | grep '^[$]y[$]' >/dev/null

    fdisk_help=$("$busybox" fdisk --help 2>&1 || true)
    printf '%s\n' "$fdisk_help" | grep -- '-s.*Show sizes' >/dev/null
}

build_platform() {
    local arch test_dir

    docker run \
        -it \
        --rm \
        --platform "$1" \
        -v "$PWD:/work:ro,delegated" \
        -v "$PWD/releases:/releases" \
        ubuntu:24.04 /work/busybox-minimal/build.sh build_task

    case "$1" in
        linux/amd64) arch=x86_64 ;;
        linux/arm64) arch=aarch64 ;;
    esac
    test_dir=$(mktemp -d)
    tar -C "$test_dir" -xf "releases/busybox-minimal-$VERSION-linux-$arch.tar.gz"

    # shellcheck disable=SC1091
    . ./common/constants.sh
    trap 'rm -rf "$test_dir"; trap - RETURN' RETURN
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
            -v "$test_dir/bin/busybox:/busybox-minimal:ro" \
            -e "BUSYBOX_PATH=/busybox-minimal" \
            -e "VERSION=$VERSION" \
            "$image" $shell /work/busybox-minimal/build.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")/.."
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
