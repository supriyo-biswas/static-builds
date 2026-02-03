#!/usr/bin/env bash

set -euo pipefail

VERSION=3.12
PCRE2_VERSION=10.47

build_task() {
    output_file="/releases/gnu-grep-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add --cache-dir /var/cache/apk \
        build-base \
        clang

    export CC=clang

    tar -xf "/work/downloads/pcre2/pcre2-$PCRE2_VERSION.tar.gz"
    cd "/pcre2-$PCRE2_VERSION"
    ./configure --prefix=/usr --enable-pcre2-16 --enable-pcre2-32
    make -j4
    make install
    cd ..

    PREFIX="/opt/grep-$VERSION"

    tar -xf "/work/downloads/grep-$VERSION.tar.gz"
    cd "/grep-$VERSION"
    LDFLAGS="-static"  PKG_CONFIG="pkg-config --static" ./configure \
        --prefix="$PREFIX" \
        --disable-rpath

    make -j4
    make install

    if ldd "$PREFIX/bin/grep"; then
        echo "grep is not statically linked"
        exit 1
    fi

    strip "$PREFIX/bin/grep"
    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    grep="$install_dir/bin/grep"

    tar -C "$install_dir" -xf "/releases/gnu-grep-$VERSION-linux-$(uname -m).tar.gz"

    set -x
    printf '123\nabc\nxy99' > /tmp/test.txt
    "$grep" -E '^1[0-9]+$' /tmp/test.txt > /tmp/test1.txt
    [[ "$(cat /tmp/test1.txt)" == "123" ]]
    "$grep" -P 'xy\d+' /tmp/test.txt > /tmp/test2.txt
    [[ "$(cat /tmp/test2.txt)" == "xy99" ]]
}

build_platform() {
    docker run \
        -it \
        --rm \
        --platform "$1" \
        -v "$PWD:/work:ro,delegated" \
        -v "$PWD/releases:/releases" \
        -v "static-builds-cache-${1/\//-}:/var/cache/apk" \
        alpine:3 sh -c "apk add --cache-dir /var/cache/apk bash; /work/gnu-grep/build.sh build_task"

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
            "$image" $shell /work/gnu-grep/build.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")/.."

    mkdir -p downloads releases
    wget -nv -N -P downloads "https://ftp.gnu.org/gnu/grep/grep-$VERSION.tar.gz"
    wget -nv -N -P downloads/pcre2 \
        "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$PCRE2_VERSION/pcre2-$PCRE2_VERSION.tar.gz"

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi
