#!/bin/sh

set -eu

build_task() {
    output_file="/releases/wget-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add \
        build-base \
        clang \
        openssl-dev \
        pcre-dev \
        zlib-dev \
        perl \
        openssl-libs-static \
        zlib-static

    tar -xf "/work/downloads/wget-$VERSION.tar.gz"
    cd "/wget-$VERSION"

    PREFIX="/opt/wget-$VERSION"

    export CC=clang
    LDFLAGS="-static" PKG_CONFIG="pkg-config --static" ./configure \
        --prefix="$PREFIX" \
        --sysconfdir=/etc \
        --with-ssl=openssl \
        --disable-rpath

    make -j4
    make install

    if ldd "$PREFIX/bin/wget"; then
        echo "wget is not statically linked"
        exit 1
    fi

    strip "$PREFIX/bin/wget"
    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin/wget
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    wget="$install_dir/bin/wget"

    mkdir -p /etc/ssl
    cp /work/downloads/cacert.pem /etc/ssl/cert.pem

    tar -C "$install_dir" -xf "/releases/wget-$VERSION-linux-$(uname -m).tar.gz"
    if ! "$wget" --version | grep -q "^GNU Wget $VERSION "; then
        echo "wget failed to run"
        exit 1
    fi

    if [ "$("$wget" -nv -O - "$REF_URL" | sha256sum | cut -d' ' -f1)" != "$REF_SHA256" ]; then
        echo "wget failed to download the reference file"
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
        alpine:3 /work/build-wget.sh build_task

    # shellcheck disable=SC1091
    . ./constants.sh
    REF_SHA256=$(wget -qO - "$REF_URL" | sha256sum | cut -d' ' -f1)

    wget -nv -N -P downloads https://github.com/certifi/python-certifi/raw/master/certifi/cacert.pem

    for image in $TEST_IMAGES; do
        docker run \
            -it \
            --rm \
            --platform "$1" \
            -v "$PWD:/work:ro,delegated" \
            -v "$PWD/releases:/releases" \
            -e "REF_URL=$REF_URL" \
            -e "REF_SHA256=$REF_SHA256" \
            -e "VERSION=$VERSION" \
            "$image" /work/build-wget.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")"
    VERSION=1.24.5

    mkdir -p downloads releases
    wget -nv -N -P downloads "https://ftp.gnu.org/gnu/wget/wget-$VERSION.tar.gz"

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi
