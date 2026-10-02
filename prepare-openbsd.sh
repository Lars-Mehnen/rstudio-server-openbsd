#!/bin/sh
#
# prepare-openbsd.sh
#
# Prepare an OpenBSD amd64 system for building RStudio Server from source.
#
# This script is based on the working OpenBSD/RStudio build described in
# README-rstudio-openbsd.md. It intentionally avoids modifying /etc/login.conf
# automatically and does not build SOCI or esbuild; those are handled separately.
#
# Tested context:
#   OpenBSD current/snapshot (amd64)
#   RStudio Server 2026.10 development tree
#
# Run as a normal user. Root privileges are requested only via doas when needed.
#

set -eu

say() {
    printf '\n==> %s\n' "$*"
}

warn() {
    printf '\nWARNING: %s\n' "$*" >&2
}

have() {
    command -v "$1" >/dev/null 2>&1
}

# ----------------------------------------------------------------------
# Basic platform checks
# ----------------------------------------------------------------------

say "Checking platform"

OS="$(uname -s)"
ARCH="$(uname -m)"

if [ "$OS" != "OpenBSD" ]; then
    echo "This script is intended for OpenBSD, not: $OS" >&2
    exit 1
fi

if [ "$ARCH" != "amd64" ]; then
    warn "This setup was tested on amd64; current architecture is $ARCH."
fi

uname -a

# ----------------------------------------------------------------------
# Package installation
# ----------------------------------------------------------------------

say "Installing / updating required packages"

if ! have pkg_add; then
    echo "pkg_add not found." >&2
    exit 1
fi

# Package names are deliberately kept generic where OpenBSD resolves the
# current package flavor/version automatically.
#
# If a package name changes on a future snapshot, install the equivalent
# package manually and rerun this script.

PKGS="
cmake
ninja
git
python3
apache-ant
jdk-17
node
boost
postgresql-client
sqlite3
libinotify
gmake
go
bash
"

for pkg in $PKGS; do
    printf '  %-24s ' "$pkg"
    if pkg_info -e "$pkg" >/dev/null 2>&1; then
        echo "already installed"
    else
        echo "installing"
        if ! doas pkg_add -D snap "$pkg"; then
            warn "Could not install package '$pkg'. Install the matching OpenBSD package manually."
        fi
    fi
done

# ----------------------------------------------------------------------
# Java
# ----------------------------------------------------------------------

say "Checking Java 17"

JAVA_HOME=/usr/local/jdk-17

if [ -x "$JAVA_HOME/bin/java" ]; then
    "$JAVA_HOME/bin/java" -version || true
else
    warn "$JAVA_HOME/bin/java was not found."
fi

cat <<EOF

For the RStudio build use:

  export JAVA_HOME=/usr/local/jdk-17
  export PATH="\$JAVA_HOME/bin:\$PATH"

EOF

# ----------------------------------------------------------------------
# Node / npm / corepack / yarn
# ----------------------------------------------------------------------

say "Checking Node toolchain"

if have node; then
    node --version
else
    warn "node not found"
fi

if have npm; then
    npm --version
else
    warn "npm not found"
fi

# RStudio's GWT/Panmirror build used Yarn classic.
if have corepack; then
    say "Enabling Corepack / Yarn classic"
    corepack enable 2>/dev/null || true
    corepack prepare yarn@1.22.22 --activate 2>/dev/null || true
else
    warn "corepack not found; install/enable Yarn 1.22.22 manually."
fi

if have yarn; then
    yarn --version
else
    warn "yarn not found; RStudio's frontend build expects Yarn classic."
fi

# ----------------------------------------------------------------------
# Go
# ----------------------------------------------------------------------

say "Checking Go toolchain"

if have go; then
    go version
else
    warn "go not found; build-esbuild.sh requires Go."
fi

# ----------------------------------------------------------------------
# PostgreSQL / libpq
# ----------------------------------------------------------------------

say "Checking PostgreSQL client development files"

if [ -f /usr/local/include/postgresql/libpq-fe.h ]; then
    echo "Found /usr/local/include/postgresql/libpq-fe.h"
else
    warn "libpq header not found at /usr/local/include/postgresql/libpq-fe.h"
fi

if ls /usr/local/lib/libpq.so.* >/dev/null 2>&1; then
    ls -l /usr/local/lib/libpq.so.* | head -5
else
    warn "libpq shared library not found under /usr/local/lib"
fi

# ----------------------------------------------------------------------
# libinotify / libexecinfo
# ----------------------------------------------------------------------

say "Checking OpenBSD compatibility libraries"

if [ -f /usr/local/include/inotify/sys/inotify.h ]; then
    echo "Found libinotify header"
else
    warn "libinotify header not found"
fi

if ls /usr/local/lib/inotify/libinotify.so.* >/dev/null 2>&1; then
    ls -l /usr/local/lib/inotify/libinotify.so.* | head -5
else
    warn "libinotify shared library not found"
fi

if ls /usr/lib/libexecinfo.so.* >/dev/null 2>&1; then
    ls -l /usr/lib/libexecinfo.so.* | head -5
else
    warn "libexecinfo was not found under /usr/lib"
fi

# ----------------------------------------------------------------------
# R
# ----------------------------------------------------------------------

say "Checking R"

if have R; then
    R --version | head -3
    RHOME="$(R RHOME 2>/dev/null || true)"
    echo "R_HOME=$RHOME"

    if [ -n "$RHOME" ]; then
        if ls "$RHOME"/lib/libR.so.* >/dev/null 2>&1; then
            ls -l "$RHOME"/lib/libR.so*
        else
            warn "Versioned libR.so was not found under $RHOME/lib"
        fi

        if [ ! -e "$RHOME/lib/libR.so" ]; then
            cat <<EOF

RStudio expects an unversioned libR.so.
After verifying the installed version, create a symlink, for example:

  doas ln -s $RHOME/lib/libR.so.42.0 $RHOME/lib/libR.so

Do NOT run that command blindly if your libR version differs.

EOF
        fi
    fi
else
    warn "R is not installed."
fi

# ----------------------------------------------------------------------
# Pandoc tool path
# ----------------------------------------------------------------------

say "Checking Pandoc"

if have pandoc; then
    pandoc --version | head -2

    # RStudio's build expected this tool path in the working setup.
    PANDOC_DIR=/opt/rstudio-tools/amd64/pandoc/3.2
    PANDOC_LINK="$PANDOC_DIR/pandoc"

    if [ ! -e "$PANDOC_LINK" ]; then
        echo "Creating RStudio Pandoc compatibility path:"
        echo "  $PANDOC_LINK -> $(command -v pandoc)"
        doas mkdir -p "$PANDOC_DIR"
        doas ln -s "$(command -v pandoc)" "$PANDOC_LINK"
    fi
else
    warn "pandoc is not installed. Install an OpenBSD pandoc package before building RStudio."
fi

# ----------------------------------------------------------------------
# RStudio source-tree helper assets
# ----------------------------------------------------------------------

RSTUDIO_SRC="${RSTUDIO_SRC:-$HOME/temp/rstudio}"

if [ -d "$RSTUDIO_SRC" ]; then
    say "Preparing RStudio helper assets in $RSTUDIO_SRC"

    # MathJax
    if [ -x "$RSTUDIO_SRC/dependencies/common/install-mathjax" ]; then
        if [ ! -d /opt/rstudio-tools/amd64/mathjax-27 ]; then
            echo "Installing MathJax..."
            (
                cd "$RSTUDIO_SRC/dependencies/common"
                doas ./install-mathjax
            )
        fi

        if [ -d /opt/rstudio-tools/amd64/mathjax-27 ] &&
           [ ! -e "$RSTUDIO_SRC/dependencies/mathjax-27" ]; then
            (
                cd "$RSTUDIO_SRC/dependencies"
                ln -s /opt/rstudio-tools/amd64/mathjax-27 mathjax-27
            )
        fi
    else
        warn "MathJax installer not found; source tree may not be present yet."
    fi

    # Dictionaries
    if [ -x "$RSTUDIO_SRC/dependencies/common/install-dictionaries" ]; then
        if [ ! -d /opt/rstudio-tools/amd64/dictionaries ]; then
            echo "Installing RStudio dictionaries..."
            (
                cd "$RSTUDIO_SRC/dependencies/common"
                doas ./install-dictionaries
            )
        fi
    else
        warn "Dictionary installer not found."
    fi
else
    warn "RStudio source tree not found at $RSTUDIO_SRC"
    echo "Set RSTUDIO_SRC if your checkout is elsewhere."
fi

# ----------------------------------------------------------------------
# Login limits
# ----------------------------------------------------------------------

say "Checking shell resource limits"

ulimit -a || true

cat <<'EOF'

RStudio's frontend build needed higher OpenBSD login-class limits.

The working 'staff' login class used approximately:

    :datasize-cur=6G:\
    :datasize-max=infinity:\
    :maxproc-max=512:\
    :maxproc-cur=256:\
    :openfiles-cur=4096:\
    :openfiles-max=8192:\

Edit /etc/login.conf manually, preserving the rest of your staff entry.

Then run:

    doas cap_mkdb /etc/login.conf

IMPORTANT:
Log out completely and log in again before building, otherwise the new
limits will not apply to your shell.

EOF

# ----------------------------------------------------------------------
# Manual components still required
# ----------------------------------------------------------------------

say "Preparation summary"

cat <<'EOF'

Base preparation completed.

Still required before building RStudio:

  1. Build and install SOCI 4.0.3
       ./build-soci.sh
       cd ~/temp/soci/build
       doas ninja install

  2. Prepare the OpenBSD-native esbuild binaries used by the RStudio tree.
     This requires Go.
     Working versions were:
       0.15.18
       0.16.17
       0.17.19
       0.25.6

  3. Ensure the OpenBSD RStudio source patches are applied / restore the
     working Git bundle.

  4. Apply the login.conf changes shown above and log in again.

  5. Run:
       ./build-rstudio.sh

  6. After a successful build:
       ./setup-runtime.sh

Notes:
  - Quarto was disabled in the working build.
  - RStudio unit tests were disabled in the working build.
  - The current development setup still emits an r-ldpath warning.
EOF
