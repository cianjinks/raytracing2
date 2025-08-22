#!/bin/sh

# Build script
# Usage: ./build.sh [debug|release]
# Default: debug

set -e

BASE_DIR=$(dirname "$(realpath "$0")")

BUILD_MODE=${1:-debug}

if [[ "$BUILD_MODE" != "debug" && "$BUILD_MODE" != "release" ]]; then
    echo "Error: Invalid build mode '$BUILD_MODE'. Use 'debug' or 'release'."
    exit 1
fi

BUILD_DIR="$BASE_DIR/build/$BUILD_MODE"
mkdir -p "$BUILD_DIR"

ODIN_FLAGS="-define:GLFW_SHARED=false -define:WGPU_SHARED=false"

if [[ "$BUILD_MODE" == "debug" ]]; then
    ODIN_FLAGS+=" -debug"
fi

odin build $BASE_DIR/bin/viewer $ODIN_FLAGS -out:"$BUILD_DIR/viewer" -collection:external="$BASE_DIR/external" -collection:raytracing2="$BASE_DIR"

if [[ $? -ne 0 ]]; then
    echo "Failed :("
    exit 1
fi