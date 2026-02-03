#!/usr/bin/env bash

set -euo pipefail

VERSION=4.10.0

build_task() {
    output_file="/releases/findutils-$VERSION-linux-$(uname -m).tar.gz"
    if [ -f "$output_file" ]; then
        echo "File $output_file already exists, no need to build"
        exit 0
    fi

    apk add --cache-dir /var/cache/apk \
        build-base \
        clang \
        bison

    export CC=clang

    tar -xf "/work/downloads/findutils-$VERSION.tar.xz"
    cd "/findutils-$VERSION"

    PREFIX="/opt/findutils-$VERSION"

    LDFLAGS="-static" PKG_CONFIG="pkg-config --static" ./configure \
        --prefix="$PREFIX" \
        --disable-rpath

    make -j4
    make install

    if ldd "$PREFIX/bin/find"; then
        echo "find is not statically linked"
        exit 1
    fi

    rm "$PREFIX/bin/updatedb" "$PREFIX/bin/locate"

    find "$PREFIX/bin" -type f -exec strip {} \;
    tar --numeric-owner -C "$PREFIX" -czf "$output_file" bin
}

sanity_check() {
    install_dir=$(mktemp -d /opt/XXXXXXXXXX)
    tar -C "$install_dir" -xf "/releases/findutils-$VERSION-linux-$(uname -m).tar.gz"
    find="$install_dir/bin/find"
    xargs="$install_dir/bin/xargs"

    # ensure no dependencies exist on system findutils
    unlink "$(command -v find)" || true
    unlink "$(command -v xargs)" || true

    if command -v useradd > /dev/null; then
        useradd -m -p "" -s /bin/bash testuser
    else
        adduser -D -g "" -s /bin/bash testuser
    fi

    mkdir -p /home/testuser/dir1
    for i in $(seq 1 10); do
        echo "$i" > "/home/testuser/dir1/file$i"
    done

    mkdir -p /home/testuser/dir1/dir2
    for i in $(seq 1 10); do
        echo "$i" > "/home/testuser/dir1/dir2/file$i"
    done

    chown -R testuser: /home/testuser/dir1

    output=$("$find" /home/testuser/dir1 -type f -printf '%u:%g %p %s\n' | sort)
    expected_output=$(cat <<EOM
testuser:testuser /home/testuser/dir1/dir2/file1 2
testuser:testuser /home/testuser/dir1/dir2/file10 3
testuser:testuser /home/testuser/dir1/dir2/file2 2
testuser:testuser /home/testuser/dir1/dir2/file3 2
testuser:testuser /home/testuser/dir1/dir2/file4 2
testuser:testuser /home/testuser/dir1/dir2/file5 2
testuser:testuser /home/testuser/dir1/dir2/file6 2
testuser:testuser /home/testuser/dir1/dir2/file7 2
testuser:testuser /home/testuser/dir1/dir2/file8 2
testuser:testuser /home/testuser/dir1/dir2/file9 2
testuser:testuser /home/testuser/dir1/file1 2
testuser:testuser /home/testuser/dir1/file10 3
testuser:testuser /home/testuser/dir1/file2 2
testuser:testuser /home/testuser/dir1/file3 2
testuser:testuser /home/testuser/dir1/file4 2
testuser:testuser /home/testuser/dir1/file5 2
testuser:testuser /home/testuser/dir1/file6 2
testuser:testuser /home/testuser/dir1/file7 2
testuser:testuser /home/testuser/dir1/file8 2
testuser:testuser /home/testuser/dir1/file9 2
EOM
)
    if [ "$output" != "$expected_output" ]; then
        echo "find output does not match expected output"
        exit 1
    fi

    "$find" /home/testuser/dir1 -type f -size +2c -print0 | "$xargs" -0 rm
    output=$("$find" /home/testuser/dir1 -type f -printf '%u:%g %p %s\n' | sort)
    expected_output=$(echo "$expected_output" | grep -v file10)

    if [ "$output" != "$expected_output" ]; then
        echo "find output does not match expected output"
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
        -v "static-builds-cache-${1/\//-}:/var/cache/apk" \
        alpine:3 sh -c "apk add --cache-dir /var/cache/apk bash; /work/findutils/build.sh build_task"

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
            "$image" $shell /work/findutils/build.sh sanity_check
    done
}

main() {
    cd "$(dirname "$0")/.."
    mkdir -p downloads releases
    wget -nv -N -P downloads \
        "https://ftp.gnu.org/gnu/findutils/findutils-$VERSION.tar.xz"

    build_platform linux/amd64
    build_platform linux/arm64
}

if [ -z ${1+x} ]; then
    main
else
    "$@"
fi
