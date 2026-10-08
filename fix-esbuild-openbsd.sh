#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
WORKSPACE="${WORKSPACE:-$(dirname "$SCRIPT_DIR")}"
RSTUDIO_SRC="${RSTUDIO_SRC:-$WORKSPACE/rstudio}"
QUARTO="${QUARTO:-$RSTUDIO_SRC/src/gwt/lib/quarto}"
NATIVE="${ESBUILD_NATIVE_DIR:-$WORKSPACE/esbuild-native}"

replace()
{
    version="$1"
    target="$2"
    source="$NATIVE/esbuild-$version.bin"

    echo "==> esbuild $version"
    echo "    $target"

    [ -x "$source" ] || {
        echo "Missing native binary: $source" >&2
        exit 1
    }

    [ -f "$target" ] || {
        echo "Missing target: $target" >&2
        exit 1
    }

    if [ ! -f "$target.npm-original" ]; then
        cp -p "$target" "$target.npm-original"
    fi

    cp "$source" "$target"
    chmod +x "$target"

    "$target" --version
}

cd "$QUARTO"

replace 0.16.17 \
  node_modules/@esbuild/openbsd-x64/bin/esbuild

replace 0.15.18 \
  node_modules/esbuild-openbsd-64/bin/esbuild

replace 0.17.19 \
  node_modules/tsup/node_modules/@esbuild/openbsd-x64/bin/esbuild

replace 0.25.6 \
  node_modules/tsx/node_modules/@esbuild/openbsd-x64/bin/esbuild

echo
echo "All native OpenBSD esbuild binaries installed."
