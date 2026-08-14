#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 stage1-static|stage2-pointer|stage3-animations [seconds] [size] [fallback-theme]"
  exit 2
fi

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$1"
SECONDS_TO_TEST="${2:-10}"
SIZE="${3:-48}"
FALLBACK="${4:-Bibata-Modern-Ice}"
SRC="$HERE/$STAGE"

case "$STAGE" in
  stage1-static) THEME="Brushbuddy-Static-Probe" ;;
  stage2-pointer) THEME="Brushbuddy-Pointer-Probe" ;;
  stage3-animations) THEME="Brushbuddy-Animation-Probe" ;;
  *) echo "Unknown stage: $STAGE" >&2; exit 2 ;;
esac

command -v hyprcursor-util >/dev/null || { echo "hyprcursor-util not found" >&2; exit 127; }
command -v hyprctl >/dev/null || { echo "hyprctl not found" >&2; exit 127; }

TMP="$(mktemp -d)"
DEST="$HOME/.local/share/icons/$THEME"
mkdir -p "$HOME/.local/share/icons"

revert() {
  echo
  echo "Reverting to $FALLBACK at size $SIZE..."
  hyprctl setcursor "$FALLBACK" "$SIZE" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap revert EXIT INT TERM

echo "Compiling $STAGE..."
hyprcursor-util --create "$SRC" --output "$TMP"

mapfile -t BUILT < <(find "$TMP" -mindepth 1 -maxdepth 2 -type f -name manifest.hl -printf '%h\n' | sort -u)
if [[ "${#BUILT[@]}" -ne 1 ]]; then
  echo "Expected exactly one built theme directory, found ${#BUILT[@]}:" >&2
  printf '  %s\n' "${BUILT[@]}" >&2
  exit 3
fi

rm -rf "$DEST"
cp -a "${BUILT[0]}" "$DEST"

echo "Switching to $THEME for $SECONDS_TO_TEST seconds at size $SIZE."
echo
echo "IMPORTANT: MOVE THE PHYSICAL MOUSE continuously during the test window."
echo "Hyprland may not redraw the cursor sprite until a move/hover event occurs."
echo "A stationary cursor can therefore look like a failed or blank theme swap."
echo "Even if it looks blank, this script will automatically switch back."
hyprctl setcursor "$THEME" "$SIZE"
sleep "$SECONDS_TO_TEST"
