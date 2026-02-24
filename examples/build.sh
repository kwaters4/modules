#!/usr/bin/env bash
# build.sh — configure, build, and install a CMake project to a custom prefix
#
# Usage: ./build.sh [PREFIX] [BUILD_TYPE]
#
#   PREFIX     Install prefix  (default: $HOME/.local)
#   BUILD_TYPE CMake build type (default: Release)
#
# Examples:
#   ./build.sh
#   ./build.sh /opt/foo/1.0
#   ./build.sh /opt/foo/1.0 Debug

set -euo pipefail

VERSION=1.0.0
PREFIX="/opt/apps/foo/${VERSION}"
MODULE_INSTALL_DIR="/opt/apps/modulefiles/foo"
mkdir -p $PREFIX
BUILD_TYPE="${2:-Release}"
BUILD_DIR="build"
JOBS="$(nproc)"

# Neutralise LD_RUN_PATH — prevents module-set values from
# being baked into the installed binary's RPATH
unset LD_RUN_PATH

cmake -S . -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DMODULE_PREFIX="$MODULE_INSTALL_DIR"

cmake --build   "$BUILD_DIR" --parallel "$JOBS"
cmake --install "$BUILD_DIR"

echo
echo "Installed to: $PREFIX"
echo
echo "To use newly generated module:"
echo " module load foo/${VERSION}"
echo
echo "If not on the default module search path $MODULEPATH:"
echo " module load ${MODULE_INSTALL_DIR}/${VERSION}"
