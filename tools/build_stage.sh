#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 stage1-static|stage2-pointer|stage3-animations [output-parent]"
  exit 2
fi
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$1"
OUT="${2:-$HERE/build}"
SRC="$HERE/$STAGE"
[[ -d "$SRC" ]] || { echo "No such stage: $SRC" >&2; exit 2; }
command -v hyprcursor-util >/dev/null || { echo "hyprcursor-util not found" >&2; exit 127; }
mkdir -p "$OUT"
echo "Brushbuddy v5 ladder: 24/32/48/64/96/256"
echo "+ hyprcursor-util --create '$SRC' --output '$OUT'"
hyprcursor-util --create "$SRC" --output "$OUT"
echo
echo "Build output:"
find "$OUT" -maxdepth 2 -type f -name manifest.hl -print
