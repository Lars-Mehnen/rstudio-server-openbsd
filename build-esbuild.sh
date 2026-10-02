#!/bin/sh
#
# Build OpenBSD-native esbuild binaries used by the RStudio frontend build.
#
# Working versions for the successful port:
#   0.15.18
#   0.16.17
#   0.17.19
#   0.25.6
#
# Requirements:
#   git
#   go
#
# Optional:
#   LOCAL_X_SYS=/path/to/golang.org/x/sys
#
# If LOCAL_X_SYS points to a local x/sys checkout, this script adds a temporary
# go.mod replace directive before building. This was useful on the original
# machine when fetching x/sys directly was unreliable.
#

set -eu

WORKDIR="${WORKDIR:-$HOME/temp}"
DEST="${DEST:-$WORKDIR/esbuild-native}"
VERSIONS="${VERSIONS:-0.15.18 0.16.17 0.17.19 0.25.6}"

say() {
    printf '\n==> %s\n' "$*"
}

if ! command -v go >/dev/null 2>&1; then
    echo "Go is required. Install the OpenBSD go package first." >&2
    exit 1
fi

mkdir -p "$DEST"

for ver in $VERSIONS; do
    src="$WORKDIR/esbuild-$ver"

    say "Building esbuild $ver"

    if [ ! -d "$src/.git" ]; then
        git clone --branch "v$ver" --depth 1 \
            https://github.com/evanw/esbuild.git "$src"
    else
        cd "$src"
        git fetch --tags
        git checkout "v$ver"
    fi

    cd "$src"

    # Remove an old temporary replace if one exists.
    if grep -q '^replace golang.org/x/sys =>' go.mod 2>/dev/null; then
        go mod edit -dropreplace=golang.org/x/sys
    fi

    if [ -n "${LOCAL_X_SYS:-}" ]; then
        if [ ! -d "$LOCAL_X_SYS" ]; then
            echo "LOCAL_X_SYS does not exist: $LOCAL_X_SYS" >&2
            exit 1
        fi
        say "Using local golang.org/x/sys checkout: $LOCAL_X_SYS"
        go mod edit -replace="golang.org/x/sys=$LOCAL_X_SYS"
    fi

    go build -o "$DEST/esbuild-$ver.bin" ./cmd/esbuild
    chmod +x "$DEST/esbuild-$ver.bin"

    "$DEST/esbuild-$ver.bin" --version
done

say "Built OpenBSD-native esbuild binaries"
ls -lh "$DEST"/esbuild-*.bin

cat <<EOF

Binaries are in:

  $DEST

The working RStudio port used these binaries to replace npm-distributed
esbuild executables that crashed with SIGILL on OpenBSD.

You may still need to point specific frontend builds to them via:

  ESBUILD_BINARY_PATH=$DEST/esbuild-<version>.bin

or wrapper/symlink replacements in the relevant node_modules tree.
EOF
