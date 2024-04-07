#!/bin/sh

set -eu

build_task() {
    output_file="/releases/curl-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add \
        build-base \
        clang \
        openssl-dev \
        openssl-libs-static \
        nghttp2-dev \
        nghttp2-static \
        libssh2-dev \
        libssh2-static \
        zstd-dev \
        zstd-static \
        perl \
        zlib-dev \
        zlib-static

    tar -xf "/work/downloads/curl-$VERSION.tar.gz"
    cd "/curl-$VERSION"

    PREFIX="/opt/curl-$VERSION"

    export CC=clang
    LDFLAGS="-static" PKG_CONFIG="pkg-config --static" ./configure \
        --prefix="$PREFIX" \
        --with-ca-bundle=/etc/ssl/cert.pem \
        --disable-shared \
        --enable-static \
        --enable-unix-sockets \
        --enable-ipv6 \
        --with-ssl \
        --with-libssh2 \
        --disable-ldap \
        --disable-docs \
        --disable-manual \
        --without-libpsl

    make -j4 LDFLAGS="-static -all-static"
    make install

    if ldd "$PREFIX/bin/curl"; then
        echo "curl is not statically linked"
        exit 1
    fi

    strip "$PREFIX/bin/curl"
    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin/curl
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    curl="$install_dir/bin/curl"

    mkdir -p /etc/ssl
    cp /work/downloads/cacert.pem /etc/ssl/cert.pem

    tar -C "$install_dir" -vxf "/releases/curl-$VERSION-linux-$(uname -m).tar.gz"
    if ! "$curl" --version | grep -q "^curl $VERSION "; then
        echo "curl failed to run"
        exit 1
    fi

    if [ "$("$curl" -sSf --compressed "$REF_URL" | sha256sum | cut -d' ' -f1)" != "$REF_SHA256" ]; then
        echo "curl failed to download the reference file"
        exit 1
    fi
}

build_platform() {
    docker run \
        --rm \
        --platform "$1" \
        -v "$PWD:/work:ro,delegated" \
        -v "$PWD/releases:/releases" \
        -e VERSION="$VERSION" \
        alpine:3 /work/build-curl.sh build_task

    # shellcheck disable=SC1091
    . ./constants.sh
    REF_SHA256=$(wget -qO - "$REF_URL" | sha256sum | cut -d' ' -f1)

    wget -nv -N -P downloads https://github.com/certifi/python-certifi/raw/master/certifi/cacert.pem

    for image in $TEST_IMAGES; do
        docker run \
            --rm \
            --platform "$1" \
            -v "$PWD:/work:ro,delegated" \
            -v "$PWD/releases:/releases" \
            -e "REF_URL=$REF_URL" \
            -e "REF_SHA256=$REF_SHA256" \
            -e "VERSION=$VERSION" \
            "$image" /work/build-curl.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")"
    VERSION=$(wget -qO - https://api.github.com/repos/curl/curl/releases | jq -r '.[0].name')

    mkdir -p downloads releases
    wget -nv -N -P downloads "https://curl.haxx.se/download/curl-$VERSION.tar.gz"

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi
