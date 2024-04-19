#!/bin/sh

set -eu

symlink_dups() {
    prev_file=''
    prev_hash=''

    find "$1" -type f -print0 | \
        xargs -0 sha256sum | \
        sort | \
        uniq -w64 -d --all-repeated=separate | \
        while read -r line; do
        hash=$(echo "$line" | awk '{ print $1; }')
        if [ "$line" = '' ]; then
            prev_hash=''
            continue
        fi

        if [ "$prev_hash" = '' ]; then
            prev_hash="$hash"
            prev_file=$(echo "$line" | awk '{ print $2; }')
            continue
        fi

        file=$(echo "$line" | awk '{ print $2; }')
        ln -srf "$prev_file" "$file"
    done
}

build_task() {
    output_file="/releases/git-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add \
        sed \
        coreutils \
        build-base \
        clang \
        file \
        openssl-dev \
        openssl-libs-static \
        nghttp2-dev \
        nghttp2-static \
        zstd-dev \
        zstd-static \
        perl \
        zlib-dev \
        zlib-static \
        expat-dev \
        expat-static

    tar -xf "/work/downloads/curl-$CURL_VERSION.tar.gz"
    cd "/curl-$CURL_VERSION"

    export CC=clang
    LDFLAGS="-static" PKG_CONFIG="pkg-config --static" ./configure \
        --prefix=/usr \
        --with-ca-bundle=/etc/ssl/cert.pem \
        --disable-shared \
        --enable-static \
        --enable-unix-sockets \
        --enable-ipv6 \
        --with-ssl \
        --disable-ldap \
        --disable-docs \
        --disable-manual \
        --without-libpsl

    make -j4 LDFLAGS="-static -all-static"
    make install
    cd ..

    tar -xf "/work/downloads/git-$VERSION.tar.gz"
    cd "/git-$VERSION"

    PREFIX="/opt/git-$VERSION"
    LDFLAGS="-static" \
    PKG_CONFIG="pkg-config --static" \
    CFLAGS="$(pkg-config --cflags libcurl)" \
    LIBS="$(pkg-config --libs libcurl)" \
    ./configure \
        --prefix="$PREFIX" \
        --sysconfdir=/etc \
        --without-tcltk \
        --with-curl

    make NO_PERL=1 RUNTIME_PREFIX=1 -j4 install

    if ldd "$PREFIX/bin/git"; then
        echo "git is not statically linked"
        exit 1
    fi

    nulls=''
    for _ in $(seq 1 $((${#PREFIX} + 1))); do
        nulls="$nulls\\x00"
    done

    symlink_dups "$PREFIX"

    find "$PREFIX/bin" "$PREFIX/libexec" -type f -exec file --mime-type {} + | \
        awk '$2 == "application/x-executable" { print substr($1,0,length($1)-1); }' | \
        xargs -r strip

    find "$PREFIX/bin" "$PREFIX/libexec" -type f -exec file --mime-type {} + | \
        awk '$2 == "application/x-executable" { print substr($1,0,length($1)-1); }' | \
        xargs -r sed -ri "s:$PREFIX/share/git-core/templates:share/git-core/templates$nulls:g"

    find "$PREFIX/bin" "$PREFIX/libexec" -type f -exec file --mime-type {} + | \
        awk '$2 == "application/x-executable" { print substr($1,0,length($1)-1); }' | \
        xargs -r sed -ri "s:$PREFIX/libexec/git-core:libexec/git-core$nulls:g"

    tar --numeric-owner -C "$PREFIX" -czf "$output_file" .
}

sanity_check() {
    install_dir="$(mktemp -d /opt/XXXXXXXXXX)"
    git="$install_dir/bin/git"

    mkdir -p /etc/ssl "$install_dir"
    cp /work/downloads/cacert.pem /etc/ssl/cert.pem
    tar -C "$install_dir" -xf "/releases/git-$VERSION-linux-$(uname -m).tar.gz"

    if ! "$git" --version | grep -q "^git version $VERSION$"; then
        echo "git failed to run"
        exit 1
    fi

    if ! "$git" clone https://github.com/git/git.git git1 -b master --depth 1; then
        echo "git failed to clone"
        exit 1
    fi

    cd git1
    if ! PAGER='cat' "$git" log --oneline -n 1; then
        echo "git failed to log"
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
        -e CURL_VERSION="$CURL_VERSION" \
        alpine:3 /work/build-git.sh build_task

    # shellcheck disable=SC1091
    . ./constants.sh
    wget -nv -N -P downloads https://github.com/certifi/python-certifi/raw/master/certifi/cacert.pem

    for image in $TEST_IMAGES; do
        docker run \
            -it \
            --rm \
            --platform "$1" \
            -v "$PWD:/work:ro,delegated" \
            -v "$PWD/releases:/releases" \
            -e "VERSION=$VERSION" \
            "$image" /work/build-git.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")"
    VERSION=2.44.0
    CURL_VERSION=8.7.1

    mkdir -p downloads releases

    wget -nv -N -P downloads \
        "https://curl.se/download/curl-$CURL_VERSION.tar.gz"

    wget -nv -N -P downloads \
        "https://www.kernel.org/pub/software/scm/git/git-$VERSION.tar.gz"

    # build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi
