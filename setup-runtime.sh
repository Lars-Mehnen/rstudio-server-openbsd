#!/bin/sh
#
# Set up the runtime layout used by the successful OpenBSD development build.
#
# This is NOT yet a polished package/install layout. It creates compatibility
# symlinks so rserver and rsession can run directly from the build tree.
#

set -eu

RSTUDIO_SRC="${RSTUDIO_SRC:-$HOME/temp/rstudio}"
BUILD_CPP="$RSTUDIO_SRC/build/src/cpp"
SOURCE_R="$RSTUDIO_SRC/src/cpp/r/R"

say() {
    printf '\n==> %s\n' "$*"
}

safe_link() {
    target="$1"
    link="$2"

    if [ -L "$link" ]; then
        current="$(readlink "$link")"
        if [ "$current" = "$target" ]; then
            echo "OK: $link -> $target"
            return
        fi
        echo "Replacing symlink: $link -> $current"
        rm "$link"
    elif [ -e "$link" ]; then
        echo "Refusing to replace non-symlink path: $link" >&2
        exit 1
    fi

    ln -s "$target" "$link"
    echo "Created: $link -> $target"
}

if [ ! -d "$BUILD_CPP" ]; then
    echo "Build tree not found: $BUILD_CPP" >&2
    exit 1
fi

say "Creating build-tree runtime links"

cd "$BUILD_CPP"
safe_link "server/db" "db"
safe_link "../../../src/cpp/r/R" "R"
safe_link "../../../src/cpp/session/resources" "resources"

say "Creating generated R module link"

if [ ! -d "$SOURCE_R" ]; then
    echo "R source directory not found: $SOURCE_R" >&2
    exit 1
fi

cd "$SOURCE_R"
safe_link "../../../../build/src/cpp/session/modules/R" "modules"

say "Checking required runtime resources"

for f in \
    "$BUILD_CPP/db/CreateTables.sqlite" \
    "$BUILD_CPP/R/Tools.R" \
    "$BUILD_CPP/R/modules/ModuleTools.R" \
    "$BUILD_CPP/R/modules/NotebookAlternateEngines.R" \
    "$BUILD_CPP/resources/schema/user-prefs-schema.json" \
    "$BUILD_CPP/resources/schema/user-state-schema.json"
do
    if [ -f "$f" ]; then
        echo "OK: $f"
    else
        echo "MISSING: $f" >&2
        exit 1
    fi
done

say "Checking R shared library compatibility link"

R_BIN="${R_BIN:-/usr/local/bin/R}"

if [ -x "$R_BIN" ]; then
    R_HOME="$("$R_BIN" RHOME)"
    echo "R_HOME=$R_HOME"

    if [ -e "$R_HOME/lib/libR.so" ]; then
        echo "OK: $R_HOME/lib/libR.so"
    else
        versioned="$(ls "$R_HOME"/lib/libR.so.* 2>/dev/null | head -1 || true)"
        if [ -n "$versioned" ]; then
            echo
            echo "RStudio expects an unversioned libR.so."
            echo "Run:"
            echo
            echo "  doas ln -s $versioned $R_HOME/lib/libR.so"
            echo
        else
            echo "No versioned libR.so found under $R_HOME/lib" >&2
        fi
    fi
else
    echo "R executable not found: $R_BIN" >&2
fi

say "Checking /var/lib/rstudio-server"

if [ -d /var/lib/rstudio-server ]; then
    ls -ld /var/lib/rstudio-server
else
    cat <<'EOF'

For the current non-root development test, create the state directory with:

  doas mkdir -p /var/lib/rstudio-server
  doas chown "$USER":"$(id -gn)" /var/lib/rstudio-server
  doas chmod 700 /var/lib/rstudio-server

For a real installation, use a dedicated rstudio-server service account instead.
EOF
fi

say "Runtime setup completed"

cat <<EOF

Known remaining development warning:

  r-ldpath script not found at:
    $BUILD_CPP/bin/r-ldpath

The current tested build still starts and runs RStudio Server despite that warning.

Next:

  ./start-rstudio.sh
EOF
