#!/usr/bin/env bash

set -euo pipefail

VERSION=5.3

build_task() {
    output_file="/releases/bash-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add --cache-dir /var/cache/apk \
        build-base \
        clang \
        patch

    tar -xf "/work/downloads/bash-$VERSION.tar.gz"
    cd "/bash-$VERSION"
    patch -p1 < /work/bash/patch.diff
    for i in {1..3}; do
        patch -p0 < "/work/downloads/bash${VERSION/./}-00$i"
    done

    PREFIX="/opt/bash-$VERSION"

    export CC=clang
    ./configure \
        --prefix="$PREFIX" \
        --without-bash-malloc \
        --enable-static-link \
        --disable-rpath \
        --disable-nls \
        --disable-debugger

    make -j4
    make install

    if ldd "$PREFIX/bin/bash"; then
        echo "bash is not statically linked"
        exit 1
    fi

    strip "$PREFIX/bin/bash"
    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin/bash
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    bash="$install_dir/bin/bash"

    tar -C "$install_dir" -xf "/releases/bash-$VERSION-linux-$(uname -m).tar.gz"
    set -x
    "$bash" --version | grep -qE "^GNU bash, version"

    cat << EOM > /tmp/1.sh
#!bash
for ((i=1; i<=10; i++)); do
    echo \$i
done
EOM

    "$bash" /tmp/1.sh > /tmp/1.txt
    [[ $(wc -l /tmp/1.txt | cut -d' ' -f1) -eq 10 ]]
    [[ $(head -n 1 /tmp/1.txt) == 1 ]]
    [[ $(tail -n 1 /tmp/1.txt) == 10 ]]
}

build_platform() {
    docker run \
        -it \
        --rm \
        --platform "$1" \
        -v "$PWD:/work:ro,delegated" \
        -v "$PWD/releases:/releases" \
        -v "static-builds-cache-${1/\//-}:/var/cache/apk" \
        alpine:3 sh -c "apk add --cache-dir /var/cache/apk bash; /work/bash/build.sh build_task"

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
            "$image" $shell /work/bash/build.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")/.."
    mkdir -p downloads releases
    wget -nv -N -P downloads "https://ftp.gnu.org/gnu/bash/bash-$VERSION.tar.gz"
    for i in {1..3}; do
        wget -nv -N -P downloads "https://ftp.gnu.org/gnu/bash/bash-$VERSION-patches/bash${VERSION/./}-00$i"
    done

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi
