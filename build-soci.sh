#!/bin/sh
#
# Build and install SOCI 4.0.3 for the OpenBSD RStudio Server port.
#
# Run as a normal user. Installation into /usr/local uses doas.
#

set -eu

WORKDIR="${WORKDIR:-$HOME/temp}"
PREFIX="${PREFIX:-/usr/local}"
SOCI_VERSION="${SOCI_VERSION:-v4.0.3}"
SRC="$WORKDIR/soci"

say() {
    printf '\n==> %s\n' "$*"
}

say "Preparing SOCI ${SOCI_VERSION}"

mkdir -p "$WORKDIR"

if [ ! -d "$SRC/.git" ]; then
    git clone --branch "$SOCI_VERSION" --depth 1 \
        https://github.com/SOCI/soci.git "$SRC"
else
    cd "$SRC"
    git fetch --tags
    git checkout "$SOCI_VERSION"
fi

rm -rf "$SRC/build"
mkdir -p "$SRC/build"
cd "$SRC/build"

say "Configuring SOCI"

cmake .. -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DSOCI_TESTS=OFF \
  -DWITH_BOOST=ON \
  -DWITH_POSTGRESQL=ON \
  -DWITH_SQLITE3=ON \
  -DWITH_MYSQL=OFF \
  -DWITH_ORACLE=OFF \
  -DWITH_ODBC=OFF \
  -DBoost_ROOT=/usr/local \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5

say "Building SOCI"
ninja

say "Installing SOCI into $PREFIX"
doas ninja install

say "Checking installed libraries"

for lib in \
    "$PREFIX/lib/libsoci_core.a" \
    "$PREFIX/lib/libsoci_sqlite3.a" \
    "$PREFIX/lib/libsoci_postgresql.a"
do
    if [ -f "$lib" ]; then
        echo "OK: $lib"
    else
        echo "MISSING: $lib" >&2
        exit 1
    fi
done

say "SOCI build/install completed"
