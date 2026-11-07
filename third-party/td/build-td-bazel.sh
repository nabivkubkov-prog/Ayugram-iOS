#!/bin/sh

set -e
set -x

ARCH="$1"

SOURCE_DIR="$2"
BUILD_DIR=$(echo "$(cd "$(dirname "$3")"; pwd -P)/$(basename "$3")")
OPENSSL_DIR="$4"

openssl_crypto_library="${OPENSSL_DIR}/lib/libcrypto.a"
options=""
options="$options -DOPENSSL_FOUND=1"
options="$options -DOPENSSL_CRYPTO_LIBRARY=${openssl_crypto_library}"
options="$options -DOPENSSL_INCLUDE_DIR=${OPENSSL_DIR}/src/include"
options="$options -DCMAKE_BUILD_TYPE=Release"
options="$options -DIOS_DEPLOYMENT_TARGET=13.0"

cd "$BUILD_DIR"

# Generate source files
mkdir native-build
cd native-build
cmake -DTD_GENERATE_SOURCE_FILES=ON ../td
cmake --build . -- -j$(sysctl -n hw.ncpu)
cd ..

if [ "$ARCH" = "arm64" ]; then
  IOS_SYSROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
  export CFLAGS="-arch arm64 --target=arm64-apple-ios13.0 -miphoneos-version-min=13.0"
elif [ "$ARCH" = "sim_arm64" ]; then
  IOS_SYSROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  export CFLAGS="-arch arm64 --target=arm64-apple-ios13.0-simulator -miphonesimulator-version-min=13.0"
else
  echo "Unsupported architecture $ARCH"
  exit 1
fi

# TD and FindAtomics compile C++. CFLAGS alone leaves them targeting the
# host architecture (x86_64 on Intel runners) against an arm64 iPhone SDK.
# Set these only after building the generators, which must run on macOS.
export CXXFLAGS="$CFLAGS"

# Common build steps
mkdir build
cd build

echo "set(CMAKE_SYSTEM_NAME Darwin)" > toolchain.cmake
echo "set(CMAKE_SYSTEM_PROCESSOR aarch64)" >> toolchain.cmake
echo "set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING \"\")" >> toolchain.cmake
echo "set(CMAKE_C_COMPILER \"$(xcrun --find clang)\")" >> toolchain.cmake
echo "set(CMAKE_CXX_COMPILER \"$(xcrun --find clang++)\")" >> toolchain.cmake

if ! cmake -G"Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake -DCMAKE_OSX_SYSROOT="$IOS_SYSROOT" ../td $options; then
  # Bazel does not otherwise include the failed compiler probes in its log.
  if [ -f CMakeFiles/CMakeError.log ]; then
    cat CMakeFiles/CMakeError.log >&2
  fi
  exit 1
fi
make tde2e -j$(sysctl -n hw.ncpu)
