#!/bin/sh

# Build script
# Usage: ./build.sh [debug|release] [--trace]
# Default: debug, tracing disabled

set -e

BASE_DIR=$(dirname "$(realpath "$0")")

BUILD_MODE=${1:-debug}

TRACE_ENABLED=false
if [[ "$2" == "--trace" ]]; then
    TRACE_ENABLED=true
fi

if [[ "$BUILD_MODE" != "debug" && "$BUILD_MODE" != "release" ]]; then
    echo "Error: Invalid build mode '$BUILD_MODE'. Use 'debug' or 'release'."
    exit 1
fi

BUILD_DIR="$BASE_DIR/build/$BUILD_MODE"
mkdir -p "$BUILD_DIR"

ODIN_FLAGS="-define:GLFW_SHARED=false -define:WGPU_SHARED=false"

if [[ "$BUILD_MODE" == "debug" ]]; then
    ODIN_FLAGS+=" -debug -define:GLFW_DEBUG=true -define:WGPU_DEBUG=true -define:TRACY_DEBUG=true"
fi

if $TRACE_ENABLED; then
    ODIN_FLAGS+=" -define:TRACY_ENABLE=true"
fi

odin build $BASE_DIR/bin/viewer $ODIN_FLAGS -out:"$BUILD_DIR/viewer" -collection:external="$BASE_DIR/external" -collection:raytracing2="$BASE_DIR"

if [[ $? -ne 0 ]]; then
    echo "Failed :("
    exit 1
fi