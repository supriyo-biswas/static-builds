#!/usr/bin/env bash

set -euo pipefail

VERSION=5.3.2

build_task() {
    output_file="/releases/gnu-awk-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add --cache-dir /var/cache/apk \
        build-base \
        clang \
        m4

    tar -xf "/work/downloads/gawk-$VERSION.tar.gz"
    cd "/gawk-$VERSION"

    PREFIX="/opt/gawk-$VERSION"

    export CC=clang
    LDFLAGS="-static" ./configure --prefix="$PREFIX" --disable-rpath

    make -j4
    make install

    if ldd "$PREFIX/bin/gawk"; then
        echo "awk is not statically linked"
        exit 1
    fi

    strip "$PREFIX/bin/gawk"
    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin/gawk
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    awk="$install_dir/bin/gawk"

    tar -C "$install_dir" -xf "/releases/gnu-awk-$VERSION-linux-$(uname -m).tar.gz"

    set -x
    "$awk" --version | grep -q "GNU Awk $VERSION"
    printf '1,2,3,4\n5,6,7,8' > /tmp/test.csv
    # shellcheck disable=SC2016
    "$awk" -F, '$1 == 1 { print $2; }' /tmp/test.csv > /tmp/result.txt
    cat /tmp/result.txt
    grep -Fq 2 /tmp/result.txt
}

build_platform() {
    docker run \
        -it \
        --rm \
        --platform "$1" \
        -v "$PWD:/work:ro,delegated" \
        -v "$PWD/releases:/releases" \
        -v "static-builds-cache-${1/\//-}:/var/cache/apk" \
        alpine:3 sh -c "apk add --cache-dir /var/cache/apk bash; /work/gnu-awk/build.sh build_task"

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
            "$image" $shell /work/gnu-awk/build.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")/.."
    mkdir -p downloads releases
    wget -nv -N -P downloads "https://ftp.gnu.org/gnu/gawk/gawk-$VERSION.tar.gz"

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi
