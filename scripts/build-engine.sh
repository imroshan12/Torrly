#!/bin/zsh
# Builds Vendor/TorrlyEngine.xcframework: OpenSSL + libtorrent 2.0 + the Objective-C++ bridge in Engine/,
# for iOS devices (arm64) and the simulator (arm64). Needs CMake and Boost headers (brew install cmake boost).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIBTORRENT_TAG=v2.0.15
OPENSSL_TAG=openssl-3.5.9
LT_SRC="$ROOT/Vendor/src/libtorrent"
SSL_SRC="$ROOT/Vendor/src/openssl"
BUILD="$ROOT/build/engine"
OUT="$ROOT/Vendor/TorrlyEngine.xcframework"
MIN_IOS=17.0
BOOST_DIR=${BOOST_DIR:-$(brew --prefix boost)/lib/cmake/Boost-$(brew list --versions boost | awk '{print $2}' | cut -d_ -f1)}
JOBS=$(sysctl -n hw.ncpu)

[[ -d "$LT_SRC" ]] || git clone --depth 1 --branch "$LIBTORRENT_TAG" --recurse-submodules --shallow-submodules \
    https://github.com/arvidn/libtorrent "$LT_SRC"
[[ -d "$SSL_SRC" ]] || git clone --depth 1 --branch "$OPENSSL_TAG" https://github.com/openssl/openssl "$SSL_SRC"

# OpenSSL is built out of tree, once per platform, into build/engine/<sdk>/openssl.
build_openssl() {
    local sdk=$1 target=$2 minflag=$3
    local prefix="$BUILD/$sdk/openssl"
    [[ -f "$prefix/lib/libssl.a" ]] && return
    local work="$BUILD/$sdk/openssl-build"
    rm -rf "$work" && mkdir -p "$work"
    (cd "$work" && "$SSL_SRC/Configure" "$target" no-shared no-tests no-apps no-docs no-engine no-dso no-async \
        "$minflag=$MIN_IOS" --prefix="$prefix" --libdir=lib \
        && make -j "$JOBS" build_libs >/dev/null && make install_dev >/dev/null)
}

build_platform() {
    local sdk=$1
    local dir="$BUILD/$sdk"
    local ssl="$dir/openssl"
    cmake -S "$ROOT/Engine" -B "$dir/cmake" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$sdk" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_IOS \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_STANDARD=17 \
        -DCMAKE_CXX_FLAGS="-DTORRENT_HAVE_MMAP=0 -DNDEBUG" \
        -DCMAKE_OBJCXX_FLAGS="-DTORRENT_HAVE_MMAP=0 -DNDEBUG" \
        -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
        -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
        -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
        -DOPENSSL_ROOT_DIR="$ssl" \
        -DOPENSSL_INCLUDE_DIR="$ssl/include" \
        -DOPENSSL_SSL_LIBRARY="$ssl/lib/libssl.a" \
        -DOPENSSL_CRYPTO_LIBRARY="$ssl/lib/libcrypto.a" \
        -DOPENSSL_USE_STATIC_LIBS=ON \
        -DCMAKE_DISABLE_FIND_PACKAGE_GnuTLS=ON \
        -DCMAKE_DISABLE_FIND_PACKAGE_LibGcrypt=ON \
        -DBoost_DIR="$BOOST_DIR" \
        -DBUILD_SHARED_LIBS=OFF \
        -Ddeprecated-functions=OFF \
        -Dlogging=OFF \
        -Di2p=OFF
    grep -q 'TORRENT_USE_OPENSSL' "$dir/cmake/CMakeFiles/TorrlyEngine.dir/flags.make" \
        || { echo "OpenSSL was not picked up for $sdk" >&2; exit 1; }
    cmake --build "$dir/cmake" --target TorrlyEngine --config Release -j "$JOBS"
    local lt_lib
    lt_lib=$(find "$dir/cmake" -name 'libtorrent-rasterbar.a' | head -1)
    libtool -static -o "$dir/libTorrlyEngineCombined.a" \
        "$dir/cmake/libTorrlyEngine.a" "$lt_lib" "$ssl/lib/libssl.a" "$ssl/lib/libcrypto.a" 2>/dev/null
}

build_openssl iphoneos ios64-xcrun -mios-version-min
build_openssl iphonesimulator iossimulator-arm64-xcrun -mios-simulator-version-min
build_platform iphoneos
build_platform iphonesimulator

rm -rf "$OUT"
xcodebuild -create-xcframework \
    -library "$BUILD/iphoneos/libTorrlyEngineCombined.a" -headers "$ROOT/Engine/include" \
    -library "$BUILD/iphonesimulator/libTorrlyEngineCombined.a" -headers "$ROOT/Engine/include" \
    -output "$OUT"
echo "Built $OUT"
