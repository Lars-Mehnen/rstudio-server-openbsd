#!/bin/sh
set -eu

REPO="${1:-$HOME/temp/rstudio}"

if [ ! -d "$REPO/.git" ]; then
    echo "RStudio git repository not found: $REPO" >&2
    exit 1
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

cp "$SCRIPT_DIR/OPENBSD.md" "$REPO/OPENBSD.md"

if ! grep -q '^## OpenBSD support$' "$REPO/README.md"; then
    python3 - "$REPO/README.md" "$SCRIPT_DIR/README_OPENBSD_NOTE.md" <<'PY'
from pathlib import Path
import sys

readme = Path(sys.argv[1])
note = Path(sys.argv[2]).read_text().rstrip() + "\n\n"
text = readme.read_text()
lines = text.splitlines(keepends=True)

seen_h1 = False
in_paragraph = False
insert_at = None

for i, line in enumerate(lines):
    stripped = line.strip()
    if not seen_h1:
        if stripped.startswith("# "):
            seen_h1 = True
        continue
    if not in_paragraph:
        if stripped:
            in_paragraph = True
    else:
        if not stripped:
            insert_at = i + 1
            break

if insert_at is None:
    insert_at = len(lines)

readme.write_text("".join(lines[:insert_at]) + note + "".join(lines[insert_at:]))
PY
fi

echo "Installed: $REPO/OPENBSD.md"
echo "Updated:   $REPO/README.md"
