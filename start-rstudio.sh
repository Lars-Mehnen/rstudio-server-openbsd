#!/bin/sh
#
# Start the development-build RStudio Server on localhost:8787.
#
# This intentionally runs in the foreground and as the current user.
# It is for testing the port, not for production deployment.
#

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
WORKSPACE="${WORKSPACE:-$(dirname "$SCRIPT_DIR")}"
RSTUDIO_SRC="${RSTUDIO_SRC:-$WORKSPACE/rstudio}"
BUILD_CPP="$RSTUDIO_SRC/build/src/cpp"

RSERVER="$BUILD_CPP/server/rserver"
RSESSION="$BUILD_CPP/session/rsession"
R_BIN="${R_BIN:-/usr/local/bin/R}"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8787}"
DATA_DIR="${DATA_DIR:-/tmp/rstudio-server-test}"
PID_FILE="${PID_FILE:-$DATA_DIR/rserver.pid}"
WWW_DIR="${WWW_DIR:-$RSTUDIO_SRC/src/gwt/www}"
SERVER_USER="${SERVER_USER:-$USER}"

say() {
    printf '\n==> %s\n' "$*"
}

for f in "$RSERVER" "$RSESSION" "$R_BIN"; do
    if [ ! -x "$f" ]; then
        echo "Executable not found: $f" >&2
        exit 1
    fi
done

if [ ! -d "$WWW_DIR" ]; then
    echo "Web assets directory not found: $WWW_DIR" >&2
    exit 1
fi

mkdir -p "$DATA_DIR"

if netstat -na -f inet 2>/dev/null | grep -q "[.]$PORT .*LISTEN"; then
    echo "Port $PORT is already in use." >&2
    echo "Check with:" >&2
    echo "  ps aux | grep '[r]server'" >&2
    echo "  netstat -na -f inet | grep $PORT" >&2
    exit 1
fi

say "Starting RStudio Server development build"
echo "Open: http://$HOST:$PORT/"
echo "Press Ctrl-C to stop."

exec "$RSERVER" \
  --server-daemonize=0 \
  --server-user="$SERVER_USER" \
  --server-data-dir="$DATA_DIR" \
  --server-pid-file="$PID_FILE" \
  --www-address="$HOST" \
  --www-port="$PORT" \
  --rsession-path="$RSESSION" \
  --rsession-which-r="$R_BIN" \
  --www-local-path="$WWW_DIR"
