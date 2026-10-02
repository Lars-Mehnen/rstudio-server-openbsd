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

RSTUDIO_SRC="${RSTUDIO_SRC:-$HOME/temp/rstudio}"
BUILD_DIR="${BUILD_DIR:-$RSTUDIO_SRC/build}"

export JAVA_HOME="${JAVA_HOME:-/usr/local/jdk-17}"
export PATH="$JAVA_HOME/bin:$PATH"

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

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

say "Configuring RStudio Server"

cmake .. -G Ninja \
  -DRSTUDIO_TARGET=Server \
  -DCMAKE_BUILD_TYPE=Release \
  -DRSTUDIO_USE_SYSTEM_BOOST=1 \
  -DRSTUDIO_UNIT_TESTS_DISABLED=ON \
  -DQUARTO_ENABLED=FALSE \
  -DRSTUDIO_ENABLE_COPILOT=FALSE \
  -DDL_LIB="" \
  -DDL_LIBRARIES="" \
  -DRT_LIBRARIES="" \
  -DCMAKE_CXX_FLAGS="-I/usr/local/include/postgresql" \
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
