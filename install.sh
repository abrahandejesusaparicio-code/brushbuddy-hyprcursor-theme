#!/usr/bin/env bash
# Brushbuddy-Bibata installer for Hyprland.
#
# Installs a precompiled hyprcursor theme (no hyprcursor-util/Python/Pillow
# needed at install time -- those are only for contributors rebuilding the
# theme from source, see working-state/ and tools/).
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
THEME_NAME="Brushbuddy-Bibata"
THEME_SRC="$HERE/release/$THEME_NAME"
STATE_DIR="$HOME/.config/brushbuddy-hyprcursor"
STATE_FILE="$STATE_DIR/install-state"
DEST_DIR="$HOME/.local/share/icons/$THEME_NAME"
UWSM_ENV="$HOME/.config/uwsm/env"
GTK3_INI="$HOME/.config/gtk-3.0/settings.ini"
GTK4_INI="$HOME/.config/gtk-4.0/settings.ini"

SIZES=(24 32 48 64 96)
RECOMMENDED=32

DRY_RUN=0
NO_GTK=0
FLATPAK_SUPPORT=0
FORCE_SIZE=""

usage() {
    cat <<EOF
Usage: ./install.sh [options]

  --size N          Skip the interactive size wizard, install at N px
                     (must be one of: ${SIZES[*]})
  --no-gtk          Don't touch GTK settings.ini / gsettings
  --flatpak-support Also export GTK_THEME / XCURSOR_PATH for Flatpak apps
  --dry-run         Show what would happen, change nothing
  -h, --help        This message
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --size) FORCE_SIZE="$2"; shift 2 ;;
        --no-gtk) NO_GTK=1; shift ;;
        --flatpak-support) FLATPAK_SUPPORT=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

say()  { printf '%s\n' "$1"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '\033[33m⚠\033[0m %s\n' "$1"; }
err()  { printf '\033[31m✗\033[0m %s\n' "$1" >&2; }

# ---------------------------------------------------------------------------
# 1. Environment detection
# ---------------------------------------------------------------------------
say "Brushbuddy installer"
say ""
say "Detecting your environment..."

HAS_HYPRCTL=0;   command -v hyprctl >/dev/null 2>&1 && HAS_HYPRCTL=1
HAS_GSETTINGS=0; command -v gsettings >/dev/null 2>&1 && HAS_GSETTINGS=1
HAS_GTK3=0;      [ -f "$GTK3_INI" ] && HAS_GTK3=1
HAS_GTK4=0;      [ -f "$GTK4_INI" ] && HAS_GTK4=1
HAS_UWSM=0;      [ -f "$UWSM_ENV" ] && HAS_UWSM=1
HAS_FLATPAK=0;   command -v flatpak >/dev/null 2>&1 && HAS_FLATPAK=1

[ "$HAS_HYPRCTL" = 1 ]   && ok "Hyprland (hyprctl found)"   || err "Hyprland (hyprctl NOT found)"
[ "$HAS_GSETTINGS" = 1 ] && ok "GTK (gsettings found)"      || warn "gsettings not found -- GTK apps may not pick up the theme"
[ "$HAS_GTK3" = 1 ]      && ok "GTK 3 settings.ini"          || warn "No GTK 3 settings.ini -- skipping"
[ "$HAS_GTK4" = 1 ]      && ok "GTK 4 settings.ini"          || warn "No GTK 4 settings.ini -- skipping"
[ "$HAS_UWSM" = 1 ]      && ok "UWSM session (~/.config/uwsm/env)" || warn "No UWSM env file -- will print manual env-var instructions instead"
[ "$HAS_FLATPAK" = 1 ]   && warn "Flatpak detected -- sandboxed apps may not see this cursor theme (see --flatpak-support)"

if [ "$HAS_HYPRCTL" != 1 ]; then
    err "This installer is Hyprland-specific and hyprctl was not found. Aborting."
    exit 1
fi

if [ ! -d "$THEME_SRC" ]; then
    err "Precompiled theme not found at $THEME_SRC"
    err "(Did you download a release archive, or clone the full repo?)"
    exit 1
fi

say ""

# ---------------------------------------------------------------------------
# 2. Detect current cursor state (for backup/rollback)
# ---------------------------------------------------------------------------
detect_current() {
    local var="$1" fallback="$2" src=""
    local val="${!var:-}"
    if [ -z "$val" ] && [ "$HAS_UWSM" = 1 ]; then
        # handles both  export FOO="bar"  and  export FOO=32  (no quotes)
        val="$(grep -oP "(?<=export ${var}=)[\"']?[^\"'\\n]+[\"']?" "$UWSM_ENV" 2>/dev/null \
               | tail -1 | tr -d '"'"'"'')"
    fi
    [ -z "$val" ] && val="$fallback"
    printf '%s' "$val"
}

# If Brushbuddy is already installed (e.g. re-running this to change size),
# reuse the EXISTING backup instead of re-detecting -- otherwise "previous"
# would become "Brushbuddy itself", and uninstall.sh would restore config to
# point at Brushbuddy right after deleting the Brushbuddy directory.
REUSE_BACKUP=0
if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
    if [ "${PREVIOUS_HYPRCURSOR_THEME:-}" != "$THEME_NAME" ] && [ -n "${PREVIOUS_HYPRCURSOR_THEME:-}" ]; then
        REUSE_BACKUP=1
        PREV_HYPRCURSOR_THEME="$PREVIOUS_HYPRCURSOR_THEME"
        PREV_HYPRCURSOR_SIZE="$PREVIOUS_HYPRCURSOR_SIZE"
        PREV_XCURSOR_THEME="$PREVIOUS_XCURSOR_THEME"
        PREV_XCURSOR_SIZE="$PREVIOUS_XCURSOR_SIZE"
        PREV_GTK_SIZE="$PREVIOUS_GTK_SIZE"
        say "Brushbuddy is already installed -- reusing your original backup (${PREV_HYPRCURSOR_THEME} @ ${PREV_HYPRCURSOR_SIZE}px) instead of overwriting it."
    fi
fi

if [ "$REUSE_BACKUP" != 1 ]; then
    PREV_HYPRCURSOR_THEME="$(detect_current HYPRCURSOR_THEME Bibata-Modern-Ice)"
    PREV_HYPRCURSOR_SIZE="$(detect_current HYPRCURSOR_SIZE 24)"
    PREV_XCURSOR_THEME="$(detect_current XCURSOR_THEME Bibata-Modern-Ice)"
    PREV_XCURSOR_SIZE="$(detect_current XCURSOR_SIZE 24)"
    PREV_GTK_SIZE="24"
    if [ "$HAS_GTK3" = 1 ]; then
        v="$(grep -oP '(?<=gtk-cursor-theme-size=)\d+' "$GTK3_INI" 2>/dev/null | head -1)"
        [ -n "$v" ] && PREV_GTK_SIZE="$v"
    fi
fi

if [ "$DRY_RUN" = 1 ]; then
    say "--- DRY RUN: no files will be changed ---"
    say "Would back up current state to: $STATE_FILE"
    say "  Previous cursor theme: $PREV_HYPRCURSOR_THEME @ ${PREV_HYPRCURSOR_SIZE}px"
    say "Would install theme to: $DEST_DIR"
    [ "$NO_GTK" = 0 ] && say "Would configure GTK settings.ini + gsettings" || say "Would skip GTK (--no-gtk)"
    [ "$HAS_UWSM" = 1 ] && say "Would update: $UWSM_ENV" || say "Would print manual env-var instructions (no UWSM env file found)"
    say "Would run: hyprctl setcursor $THEME_NAME <chosen size>"
    say ""
    say "No files were changed."
    exit 0
fi

# ---------------------------------------------------------------------------
# 3. Install the theme files (safe: doesn't change what's active yet)
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$DEST_DIR")"
rm -rf "$DEST_DIR"
cp -a "$THEME_SRC" "$DEST_DIR"
ok "Cursor theme copied to $DEST_DIR"

# Revert live cursor on any abnormal exit before the user has confirmed a size.
CONFIRMED=0
cleanup() {
    if [ "$CONFIRMED" != 1 ]; then
        hyprctl setcursor "$PREV_HYPRCURSOR_THEME" "$PREV_HYPRCURSOR_SIZE" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# 4. Choose a size -- live-tested, one at a time, wait for explicit approval
# ---------------------------------------------------------------------------
if [ -n "$FORCE_SIZE" ]; then
    valid=0
    for s in "${SIZES[@]}"; do [ "$s" = "$FORCE_SIZE" ] && valid=1; done
    if [ "$valid" != 1 ]; then
        err "--size $FORCE_SIZE is not one of the tested sizes (${SIZES[*]})"
        exit 1
    fi
    CHOSEN_SIZE="$FORCE_SIZE"
    hyprctl setcursor "$THEME_NAME" "$CHOSEN_SIZE" >/dev/null 2>&1
    ok "Installed at ${CHOSEN_SIZE}px (--size flag, wizard skipped)"
else
    idx=1
    for i in "${!SIZES[@]}"; do
        [ "${SIZES[$i]}" = "$RECOMMENDED" ] && idx=$((i+1))
    done
    CHOSEN_SIZE=""
    while [ -z "$CHOSEN_SIZE" ]; do
        cur="${SIZES[$((idx-1))]}"
        hyprctl setcursor "$THEME_NAME" "$cur" >/dev/null 2>&1
        say ""
        say "Trying size: ${cur}px$( [ "$cur" = "$RECOMMENDED" ] && echo ' (recommended)' )"
        warn "Move your mouse now to see it -- Hyprland only redraws the cursor on movement."
        read -r -p "Happy with this size? [Y]es / [b]igger / [s]maller / [l]ist / [q]uit: " ans
        case "${ans:-y}" in
            y|Y|"") CHOSEN_SIZE="$cur" ;;
            b|B) [ "$idx" -lt "${#SIZES[@]}" ] && idx=$((idx+1)) || warn "Already at the largest tested size (${SIZES[-1]}px)." ;;
            s|S) [ "$idx" -gt 1 ] && idx=$((idx-1)) || warn "Already at the smallest tested size (${SIZES[0]}px)." ;;
            l|L)
                say "Sizes: $(for i in "${!SIZES[@]}"; do printf '%d)%s ' "$((i+1))" "${SIZES[$i]}"; done)"
                read -r -p "Pick a number: " pick
                if [ "$pick" -ge 1 ] 2>/dev/null && [ "$pick" -le "${#SIZES[@]}" ] 2>/dev/null; then
                    idx="$pick"
                else
                    warn "Not a valid choice."
                fi
                ;;
            q|Q) say "Cancelled -- reverting to your previous cursor."; exit 130 ;;
            *) warn "Didn't understand that, try y/b/s/l/q." ;;
        esac
    done
    ok "Locked in ${CHOSEN_SIZE}px"
fi

CONFIRMED=1

# ---------------------------------------------------------------------------
# 5. Persist configuration
# ---------------------------------------------------------------------------
mkdir -p "$STATE_DIR/backups"
{
    echo "PREVIOUS_HYPRCURSOR_THEME=$PREV_HYPRCURSOR_THEME"
    echo "PREVIOUS_HYPRCURSOR_SIZE=$PREV_HYPRCURSOR_SIZE"
    echo "PREVIOUS_XCURSOR_THEME=$PREV_XCURSOR_THEME"
    echo "PREVIOUS_XCURSOR_SIZE=$PREV_XCURSOR_SIZE"
    echo "PREVIOUS_GTK_SIZE=$PREV_GTK_SIZE"
    echo "GTK_CONFIGURED=$([ "$NO_GTK" = 1 ] && echo 0 || echo 1)"
    echo "UWSM_ENV_FILE=$UWSM_ENV"
    echo "INSTALLED_SIZE=$CHOSEN_SIZE"
} > "$STATE_FILE"
if [ "$REUSE_BACKUP" = 1 ]; then
    ok "Original pre-Brushbuddy backup preserved (not overwritten)"
else
    [ "$HAS_UWSM" = 1 ] && cp "$UWSM_ENV" "$STATE_DIR/backups/uwsm-env.bak"
    [ "$HAS_GTK3" = 1 ] && cp "$GTK3_INI" "$STATE_DIR/backups/gtk3-settings.ini.bak"
    [ "$HAS_GTK4" = 1 ] && cp "$GTK4_INI" "$STATE_DIR/backups/gtk4-settings.ini.bak"
    ok "Previous cursor settings backed up to $STATE_DIR"
fi

if [ "$HAS_UWSM" = 1 ]; then
    if grep -q '^export HYPRCURSOR_THEME=' "$UWSM_ENV"; then
        sed -i "s/^export HYPRCURSOR_THEME=.*/export HYPRCURSOR_THEME=\"$THEME_NAME\"/" "$UWSM_ENV"
    else
        echo "export HYPRCURSOR_THEME=\"$THEME_NAME\"" >> "$UWSM_ENV"
    fi
    if grep -q '^export HYPRCURSOR_SIZE=' "$UWSM_ENV"; then
        sed -i "s/^export HYPRCURSOR_SIZE=.*/export HYPRCURSOR_SIZE=$CHOSEN_SIZE/" "$UWSM_ENV"
    else
        echo "export HYPRCURSOR_SIZE=$CHOSEN_SIZE" >> "$UWSM_ENV"
    fi
    if grep -q '^export XCURSOR_THEME=' "$UWSM_ENV"; then
        sed -i "s/^export XCURSOR_THEME=.*/export XCURSOR_THEME=\"$THEME_NAME\"/" "$UWSM_ENV"
    else
        echo "export XCURSOR_THEME=\"$THEME_NAME\"" >> "$UWSM_ENV"
    fi
    if grep -q '^export XCURSOR_SIZE=' "$UWSM_ENV"; then
        sed -i "s/^export XCURSOR_SIZE=.*/export XCURSOR_SIZE=$CHOSEN_SIZE/" "$UWSM_ENV"
    else
        echo "export XCURSOR_SIZE=$CHOSEN_SIZE" >> "$UWSM_ENV"
    fi
    ok "Hyprland (UWSM) environment configured"
else
    warn "No UWSM env file found. Add these to your Hyprland startup config manually:"
    say "    env = HYPRCURSOR_THEME,$THEME_NAME"
    say "    env = HYPRCURSOR_SIZE,$CHOSEN_SIZE"
    say "    env = XCURSOR_THEME,$THEME_NAME"
    say "    env = XCURSOR_SIZE,$CHOSEN_SIZE"
fi

if [ "$NO_GTK" != 1 ]; then
    if [ "$HAS_GTK3" = 1 ]; then
        sed -i "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$THEME_NAME/" "$GTK3_INI"
        sed -i "s/^gtk-cursor-theme-size=.*/gtk-cursor-theme-size=$CHOSEN_SIZE/" "$GTK3_INI"
    fi
    if [ "$HAS_GTK4" = 1 ]; then
        sed -i "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$THEME_NAME/" "$GTK4_INI"
        sed -i "s/^gtk-cursor-theme-size=.*/gtk-cursor-theme-size=$CHOSEN_SIZE/" "$GTK4_INI"
    fi
    if [ "$HAS_GSETTINGS" = 1 ]; then
        gsettings set org.gnome.desktop.interface cursor-theme "$THEME_NAME" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface cursor-size "$CHOSEN_SIZE" 2>/dev/null || true
    fi
    ok "GTK configured"
else
    warn "Skipped GTK configuration (--no-gtk)"
fi

if [ "$FLATPAK_SUPPORT" = 1 ] && [ "$HAS_FLATPAK" = 1 ]; then
    flatpak override --user --filesystem="$HOME/.local/share/icons:ro" 2>/dev/null \
        && ok "Flatpak apps granted read access to ~/.local/share/icons" \
        || warn "Could not set Flatpak override -- you may need to run this manually"
fi

# ---------------------------------------------------------------------------
# 6. Apply live
# ---------------------------------------------------------------------------
systemctl --user set-environment \
    XCURSOR_THEME="$THEME_NAME" XCURSOR_SIZE="$CHOSEN_SIZE" \
    HYPRCURSOR_THEME="$THEME_NAME" HYPRCURSOR_SIZE="$CHOSEN_SIZE" 2>/dev/null || true
hyprctl setcursor "$THEME_NAME" "$CHOSEN_SIZE" >/dev/null 2>&1
ok "Current session updated"

say ""
say "Brushbuddy installed successfully 🧙"
say ""
say "Move your mouse to refresh the cursor."
say "Not happy with it? Run ./uninstall.sh to restore your previous cursor."
