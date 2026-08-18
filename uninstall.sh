#!/usr/bin/env bash
# Restores whatever cursor theme/size was active before install.sh ran.
set -uo pipefail

THEME_NAME="Brushbuddy-Bibata"
STATE_DIR="$HOME/.config/brushbuddy-hyprcursor"
STATE_FILE="$STATE_DIR/install-state"
DEST_DIR="$HOME/.local/share/icons/$THEME_NAME"
UWSM_ENV="$HOME/.config/uwsm/env"
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
HYPR_LUA_ENV="$HOME/.config/hypr/config/environment.lua"
GTK3_INI="$HOME/.config/gtk-3.0/settings.ini"
GTK4_INI="$HOME/.config/gtk-4.0/settings.ini"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_RESET=$'\033[0m'
else
    C_OK=""; C_WARN=""; C_ERR=""; C_RESET=""
fi

say()  { printf '%s\n' "$1"; }
ok()   { printf '  %s✓%s %s\n' "$C_OK" "$C_RESET" "$1"; }
warn() { printf '  %s⚠%s %s\n' "$C_WARN" "$C_RESET" "$1"; }
err()  { printf '  %s✗%s %s\n' "$C_ERR" "$C_RESET" "$1" >&2; }

if [ ! -f "$STATE_FILE" ]; then
    if [ -d "$DEST_DIR" ]; then
        # install.sh copies theme files before the size wizard runs, so a
        # cancelled/interrupted install can leave them behind with nothing
        # recorded in install-state. Nothing to restore in that case -- the
        # cursor was never actually switched -- but the leftover files are
        # safe to clean up.
        warn "No install-state found -- looks like a previous install was"
        warn "cancelled before it finished. Your cursor was never actually"
        warn "switched, but leftover Brushbuddy files were found."
        rm -rf "$DEST_DIR"
        ok "Leftover Brushbuddy files removed"
        printf '\n'
        say "Nothing else to restore. You're already on your normal cursor."
        exit 0
    fi
    err "No install-state found at $STATE_FILE -- was Brushbuddy installed with install.sh?"
    err "If you installed it manually, you'll need to restore your old cursor theme by hand."
    exit 1
fi
# shellcheck disable=SC1090
source "$STATE_FILE"

say "Restoring your previous cursor..."
printf '\n'
say "  $PREVIOUS_HYPRCURSOR_THEME @ ${PREVIOUS_HYPRCURSOR_SIZE}px"
printf '\n'

HYPR_RESTORED=0
if [ -f "$STATE_DIR/backups/uwsm-env.bak" ] && [ -f "$UWSM_ENV" ]; then
    cp "$STATE_DIR/backups/uwsm-env.bak" "$UWSM_ENV"
    HYPR_RESTORED=1
fi
if [ "${HYPR_CONF_CONFIGURED:-0}" = 1 ] && [ -f "$STATE_DIR/backups/hyprland-conf.bak" ] && [ -f "$HYPR_CONF" ]; then
    cp "$STATE_DIR/backups/hyprland-conf.bak" "$HYPR_CONF"
    HYPR_RESTORED=1
fi
if [ "${HYPR_LUA_CONFIGURED:-0}" = 1 ] && [ -f "$STATE_DIR/backups/environment-lua.bak" ] && [ -f "$HYPR_LUA_ENV" ]; then
    cp "$STATE_DIR/backups/environment-lua.bak" "$HYPR_LUA_ENV"
    HYPR_RESTORED=1
fi
[ "$HYPR_RESTORED" = 1 ] && ok "Hyprland restored"

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

printf '\n'
say "Back to normal. Brushbuddy has gone home."
say "(Move your mouse if the old cursor doesn't show up right away.)"
