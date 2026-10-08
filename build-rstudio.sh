#!/bin/sh
#
# Configure and build RStudio Server on OpenBSD.
#
# Assumes:
#   - OpenBSD source patches are already applied
#   - SOCI 4.0.3 is installed in /usr/local
#   - frontend helper dependencies are prepared
#   - login-class limits are high enough
#

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
WORKSPACE="${WORKSPACE:-$(dirname "$SCRIPT_DIR")}"

RSTUDIO_SRC="${RSTUDIO_SRC:-$WORKSPACE/rstudio}"
BUILD_DIR="${BUILD_DIR:-$RSTUDIO_SRC/build}"

OPENBSD_INCLUDE_DIR="${OPENBSD_INCLUDE_DIR:-$BUILD_DIR/openbsd-include}"
ESBUILD_NATIVE_DIR="${ESBUILD_NATIVE_DIR:-$WORKSPACE/esbuild-native}"
ESBUILD_BINARY_PATH="${ESBUILD_BINARY_PATH:-$ESBUILD_NATIVE_DIR/esbuild-0.15.18.bin}"

export JAVA_HOME="${JAVA_HOME:-/usr/local/jdk-17}"
export PATH="$JAVA_HOME/bin:$PATH"
export RSTUDIO_TOOLS_ROOT=/opt/rstudio-tools/amd64
say() {
    printf '\n==> %s\n' "$*"
}

if [ ! -d "$RSTUDIO_SRC" ]; then
    echo "RStudio source tree not found: $RSTUDIO_SRC" >&2
    exit 1
fi

for f in \
    /usr/local/lib/libsoci_core.a \
    /usr/local/lib/libsoci_sqlite3.a \
    /usr/local/lib/libsoci_postgresql.a
do
    if [ ! -f "$f" ]; then
        echo "Required SOCI library missing: $f" >&2
        exit 1
    fi
done

if [ ! -x "$JAVA_HOME/bin/java" ]; then
    echo "Java not found at $JAVA_HOME/bin/java" >&2
    exit 1
fi

mkdir -p "$OPENBSD_INCLUDE_DIR"

ln -sfn /usr/local/include/soci "$OPENBSD_INCLUDE_DIR/soci"
ln -sfn /usr/local/include/inotify "$OPENBSD_INCLUDE_DIR/inotify"
ln -sfn /usr/local/include/uuid "$OPENBSD_INCLUDE_DIR/uuid"
ln -sfn /usr/local/include/security "$OPENBSD_INCLUDE_DIR/security"
ln -sfn /usr/local/include/sqlite3.h "$OPENBSD_INCLUDE_DIR/sqlite3.h"
ln -sfn /usr/local/include/sqlite3ext.h "$OPENBSD_INCLUDE_DIR/sqlite3ext.h"

if [ ! -x "$ESBUILD_BINARY_PATH" ]; then
    echo "Native OpenBSD esbuild binary not found: $ESBUILD_BINARY_PATH" >&2
    exit 1
fi

export ESBUILD_BINARY_PATH

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

say "Configuring RStudio Server"
export Boost_ROOT=/opt/rstudio-tools/amd64/boost/boost_1_91_0
export BOOST_ROOT="$Boost_ROOT"
cmake .. -G Ninja \
  -DRSTUDIO_TARGET=Server \
  -DCMAKE_BUILD_TYPE=Release \
  -DRSTUDIO_UNIT_TESTS_DISABLED=ON \
  -DQUARTO_ENABLED=FALSE \
  -DRSTUDIO_ENABLE_COPILOT=FALSE \
  -DDL_LIB="" \
  -DDL_LIBRARIES="" \
  -DRT_LIBRARIES="" \
  -DCMAKE_CXX_FLAGS="-I$OPENBSD_INCLUDE_DIR -I/usr/local/include/postgresql" \
  -DPAM_INCLUDE_DIR="$OPENBSD_INCLUDE_DIR" \
  -DSOCI_CORE_LIB=/usr/local/lib/libsoci_core.a \
  -DSOCI_SQLITE_LIB=/usr/local/lib/libsoci_sqlite3.a \
  -DSOCI_POSTGRESQL_LIB=/usr/local/lib/libsoci_postgresql.a

say "Building RStudio Server"
ninja

say "Checking resulting binaries"

for f in \
    "$BUILD_DIR/src/cpp/server/rserver" \
    "$BUILD_DIR/src/cpp/session/rsession" \
    "$BUILD_DIR/src/cpp/server/pam/rserver-pam" \
    "$BUILD_DIR/src/cpp/session/postback/rpostback"
do
    if [ -x "$f" ]; then
        echo "OK: $f"
    else
        echo "MISSING: $f" >&2
        exit 1
    fi
done

say "Build completed"

"$BUILD_DIR/src/cpp/session/rsession" --version || true

cat <<'EOF'

Next step:

  ./setup-runtime.sh

The working development port uses a few build-tree compatibility symlinks
before rserver/rsession are run directly from the build directory.
EOF
