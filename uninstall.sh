#!/usr/bin/env bash
# Restores whatever cursor theme/size was active before install.sh ran.
set -uo pipefail

THEME_NAME="Brushbuddy-Bibata"
STATE_DIR="$HOME/.config/brushbuddy-hyprcursor"
STATE_FILE="$STATE_DIR/install-state"
DEST_DIR="$HOME/.local/share/icons/$THEME_NAME"
UWSM_ENV="$HOME/.config/uwsm/env"
GTK3_INI="$HOME/.config/gtk-3.0/settings.ini"
GTK4_INI="$HOME/.config/gtk-4.0/settings.ini"

ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '\033[33m⚠\033[0m %s\n' "$1"; }
err()  { printf '\033[31m✗\033[0m %s\n' "$1" >&2; }

if [ ! -f "$STATE_FILE" ]; then
    err "No install-state found at $STATE_FILE -- was Brushbuddy installed with install.sh?"
    err "If you installed it manually, you'll need to restore your old cursor theme by hand."
    exit 1
fi
# shellcheck disable=SC1090
source "$STATE_FILE"

echo "Restoring previous cursor:"
echo "  $PREVIOUS_HYPRCURSOR_THEME @ ${PREVIOUS_HYPRCURSOR_SIZE}px"
echo ""

if [ -f "$STATE_DIR/backups/uwsm-env.bak" ] && [ -f "$UWSM_ENV" ]; then
    cp "$STATE_DIR/backups/uwsm-env.bak" "$UWSM_ENV"
    ok "Hyprland (UWSM) environment restored"
fi

if [ "${GTK_CONFIGURED:-0}" = 1 ]; then
    [ -f "$STATE_DIR/backups/gtk3-settings.ini.bak" ] && [ -f "$GTK3_INI" ] && \
        cp "$STATE_DIR/backups/gtk3-settings.ini.bak" "$GTK3_INI"
    [ -f "$STATE_DIR/backups/gtk4-settings.ini.bak" ] && [ -f "$GTK4_INI" ] && \
        cp "$STATE_DIR/backups/gtk4-settings.ini.bak" "$GTK4_INI"
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface cursor-theme "$PREVIOUS_HYPRCURSOR_THEME" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface cursor-size "${PREVIOUS_GTK_SIZE:-24}" 2>/dev/null || true
    fi
    ok "GTK restored"
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl --user set-environment \
        XCURSOR_THEME="$PREVIOUS_XCURSOR_THEME" XCURSOR_SIZE="$PREVIOUS_XCURSOR_SIZE" \
        HYPRCURSOR_THEME="$PREVIOUS_HYPRCURSOR_THEME" HYPRCURSOR_SIZE="$PREVIOUS_HYPRCURSOR_SIZE" 2>/dev/null || true
fi
if command -v hyprctl >/dev/null 2>&1; then
    hyprctl setcursor "$PREVIOUS_HYPRCURSOR_THEME" "$PREVIOUS_HYPRCURSOR_SIZE" >/dev/null 2>&1
fi
ok "Environment restored"

if [ "$PREVIOUS_HYPRCURSOR_THEME" = "$THEME_NAME" ]; then
    warn "Previous theme was recorded as $THEME_NAME itself -- not deleting $DEST_DIR"
    warn "(this means the backup chain was broken before uninstall ran; Brushbuddy is still installed)"
else
    rm -rf "$DEST_DIR"
    ok "Brushbuddy removed"
fi
rm -f "$STATE_FILE"
rm -rf "$STATE_DIR/backups"

echo ""
echo "Move your mouse to see your previous cursor again."
