#!/usr/bin/env bash
# Brushbuddy-Bibata installer for Hyprland.
#
# Installs a precompiled hyprcursor theme (no hyprcursor-util/Python/Pillow
# needed at install time -- those are only for contributors rebuilding the
# theme from source, see working-state/ and tools/).
#
# This file has two halves: the detection/backup/persistence logic (the
# "brain") and a presentation layer on top of it (the "face") -- see
# docs/CHANGELOG.md v0.10 if you're wondering why it's laid out this way.
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
THEME_NAME="Brushbuddy-Bibata"
THEME_SRC="$HERE/release/$THEME_NAME"
STATE_DIR="$HOME/.config/brushbuddy-hyprcursor"
STATE_FILE="$STATE_DIR/install-state"
DEST_DIR="$HOME/.local/share/icons/$THEME_NAME"
UWSM_ENV="$HOME/.config/uwsm/env"
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
HYPR_LUA_MAIN="$HOME/.config/hypr/hyprland.lua"
HYPR_LUA_ENV="$HOME/.config/hypr/config/environment.lua"
GTK3_INI="$HOME/.config/gtk-3.0/settings.ini"
GTK4_INI="$HOME/.config/gtk-4.0/settings.ini"
MARKER="# brushbuddy-cursor-install"
LUA_MARKER="-- brushbuddy-cursor-install"

SIZES=(24 32 48 64 96)
RECOMMENDED=32

DRY_RUN=0
NO_GTK=0
FLATPAK_SUPPORT=0
VERBOSE=0
FORCE_SIZE=""

usage() {
    cat <<EOF
Usage: ./install.sh [options]

  --size N          Skip the interactive size wizard, install at N px
                     (must be one of: ${SIZES[*]})
  --no-gtk          Don't touch GTK settings.ini / gsettings
  --flatpak-support Also export GTK_THEME / XCURSOR_PATH for Flatpak apps
  --dry-run         Show what would happen, change nothing
  --verbose         Show file paths and exactly which persistence methods ran
  -h, --help        This message
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --size) FORCE_SIZE="$2"; shift 2 ;;
        --no-gtk) NO_GTK=1; shift ;;
        --flatpak-support) FLATPAK_SUPPORT=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --verbose) VERBOSE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Presentation layer -- colors (only on a real terminal, never a hardcoded
# background), and the little helpers everything below is built from.
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_TITLE=$'\033[35m'; C_BOLD=$'\033[1m'; C_OK=$'\033[32m'
    C_WARN=$'\033[33m';  C_ERR=$'\033[31m'; C_CYAN=$'\033[36m'
    C_DIM=$'\033[2m';    C_RESET=$'\033[0m'
else
    C_TITLE=""; C_BOLD=""; C_OK=""; C_WARN=""; C_ERR=""; C_CYAN=""; C_DIM=""; C_RESET=""
fi
RULE="────────────────────────────────────────────────"

say()    { printf '%s\n' "$1"; }
ok()     { printf '  %s✓%s %s\n' "$C_OK" "$C_RESET" "$1"; }
warn()   { printf '  %s⚠%s %s\n' "$C_WARN" "$C_RESET" "$1"; }
err()    { printf '  %s✗%s %s\n' "$C_ERR" "$C_RESET" "$1" >&2; }
detail() { [ "$VERBOSE" = 1 ] && printf '      %s↳%s %s\n' "$C_DIM" "$C_RESET" "$1"; return 0; }
rule()   { printf '%s\n' "$RULE"; }

size_label() {
    local s="$1"
    if [ "$s" = "$RECOMMENDED" ]; then printf 'recommended'; return; fi
    case "$s" in
        24) printf 'compact' ;;
        48) printf 'large' ;;
        64) printf 'extra large' ;;
        96) printf 'huge' ;;
        *)  printf '' ;;
    esac
}

print_welcome() {
    printf '        /\\\n'
    printf '       /  \\\n'
    printf '      /____\\\n'
    printf '     ( %s•ᴗ•%s )\n' "$C_TITLE" "$C_RESET"
    printf '\n'
    printf '  %s%sBrushbuddy%s → Hyprland\n' "$C_TITLE" "$C_BOLD" "$C_RESET"
    printf '  A tiny witch for your pointer.\n'
}

print_welcome
printf '\n'
rule
printf '\n'
say "  Checking your setup..."
printf '\n'

# ---------------------------------------------------------------------------
# 1. Environment detection
# ---------------------------------------------------------------------------
HAS_HYPRCTL=0;   command -v hyprctl >/dev/null 2>&1 && HAS_HYPRCTL=1
HAS_GSETTINGS=0; command -v gsettings >/dev/null 2>&1 && HAS_GSETTINGS=1
HAS_GTK3=0;      [ -f "$GTK3_INI" ] && HAS_GTK3=1
HAS_GTK4=0;      [ -f "$GTK4_INI" ] && HAS_GTK4=1
HAS_UWSM=0;      [ -f "$UWSM_ENV" ] && HAS_UWSM=1
HAS_HYPR_CONF=0; [ -f "$HYPR_CONF" ] && HAS_HYPR_CONF=1
HAS_HYPR_LUA=0;  [ -f "$HYPR_LUA_MAIN" ] && [ -f "$HYPR_LUA_ENV" ] && HAS_HYPR_LUA=1
HAS_FLATPAK=0;   command -v flatpak >/dev/null 2>&1 && HAS_FLATPAK=1

if [ "$HAS_HYPRCTL" = 1 ]; then
    hypr_via=""
    [ "$HAS_UWSM" = 1 ]      && hypr_via="UWSM"
    [ "$HAS_HYPR_CONF" = 1 ] && hypr_via="${hypr_via:+$hypr_via + }hyprland.conf"
    [ "$HAS_HYPR_LUA" = 1 ]  && hypr_via="${hypr_via:+$hypr_via + }Lua config"
    [ -z "$hypr_via" ] && hypr_via="no persistent config found"
    printf '  %s✓%s %-14s %s\n' "$C_OK" "$C_RESET" "Hyprland" "$hypr_via"
else
    err "Hyprland (hyprctl NOT found)"
fi

gtk_bits=""
[ "$HAS_GTK3" = 1 ] && gtk_bits="GTK 3"
[ "$HAS_GTK4" = 1 ] && gtk_bits="${gtk_bits:+$gtk_bits + }GTK 4"
[ -n "$gtk_bits" ] && printf '  %s✓%s %-14s %s\n' "$C_OK" "$C_RESET" "GTK" "$gtk_bits"
[ "$HAS_GSETTINGS" = 1 ] && printf '  %s✓%s %-14s %s\n' "$C_OK" "$C_RESET" "gsettings" "available"
[ "$HAS_FLATPAK" = 1 ] && warn "Flatpak detected -- add --flatpak-support to grant it access too"
printf '\n'

if [ "$HAS_UWSM" != 1 ] && [ "$HAS_HYPR_CONF" != 1 ] && [ "$HAS_HYPR_LUA" != 1 ]; then
    warn "No place to persist the cursor choice was found (no UWSM env,"
    say  "    hyprland.conf, or Lua config wrapper) -- it'll apply now but won't"
    say  "    survive a reboot. Add these to your Hyprland startup config by hand:"
    say  "      env = HYPRCURSOR_THEME,$THEME_NAME"
    say  "      env = HYPRCURSOR_SIZE,<size>"
    say  "      env = XCURSOR_THEME,$THEME_NAME"
    say  "      env = XCURSOR_SIZE,<size>"
    printf '\n'
fi

if [ -z "$gtk_bits" ] && [ "$HAS_GSETTINGS" != 1 ]; then
    warn "GTK settings could not be found -- Brushbuddy will still work inside Hyprland."
    printf '\n'
fi

if [ "$HAS_HYPRCTL" != 1 ]; then
    err "This installer is Hyprland-specific and hyprctl was not found. Aborting."
    exit 1
fi

if [ ! -d "$THEME_SRC" ]; then
    err "Precompiled theme not found at $THEME_SRC"
    err "(Did you download a release archive, or clone the full repo?)"
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Detect current cursor state (for backup/rollback)
# ---------------------------------------------------------------------------
detect_current() {
    local var="$1" fallback="$2" val=""
    # The UWSM env file is checked FIRST and the live process/systemd
    # environment only as a fallback -- not the other way around. Brushbuddy
    # itself calls `systemctl --user set-environment`, and that value can
    # keep showing up in every new shell's environment (including this
    # script's own) even after uninstall.sh has correctly restored the file.
    # Trusting the live env first meant a reinstall right after an uninstall
    # could "detect" Brushbuddy-Bibata as the user's own previous theme --
    # corrupting the backup chain into a self-reference. The file is what
    # actually persists across a reboot, so it's the correct source of truth.
    if [ "$HAS_UWSM" = 1 ]; then
        # handles both  export FOO="bar"  and  export FOO=32  (no quotes)
        val="$(grep -oP "(?<=export ${var}=)[\"']?[^\"'\\n]+[\"']?" "$UWSM_ENV" 2>/dev/null \
               | tail -1 | tr -d '"'"'"'')"
    fi
    [ -z "$val" ] && val="${!var:-}"
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
        say "  Brushbuddy's already installed -- keeping your original backup"
        say "  (${PREV_HYPRCURSOR_THEME} @ ${PREV_HYPRCURSOR_SIZE}px) instead of overwriting it."
        printf '\n'
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
    rule
    printf '\n'
    say "  Brushbuddy dry run -- nothing will be changed"
    printf '\n'
    say "  Would install theme to:"
    say "    $DEST_DIR"
    printf '\n'
    say "  Would configure:"
    if [ -n "$FORCE_SIZE" ]; then dr_size="${FORCE_SIZE}px"; else dr_size="${RECOMMENDED}px by default (or pick one with --size N)"; fi
    printf '    %-14s %s\n' "Hyprcursor" "$THEME_NAME @ $dr_size"
    [ "$HAS_UWSM" = 1 ]      && printf '    %-14s %s\n' "UWSM" "environment persistence"
    [ "$HAS_HYPR_CONF" = 1 ] && printf '    %-14s %s\n' "hyprland.conf" "environment persistence"
    [ "$HAS_HYPR_LUA" = 1 ]  && printf '    %-14s %s\n' "Lua wrapper" "environment persistence"
    if [ "$NO_GTK" = 0 ]; then printf '    %-14s %s\n' "GTK" "settings.ini + gsettings"; else printf '    %-14s %s\n' "GTK" "skipped (--no-gtk)"; fi
    printf '\n'
    say "  No files were changed."
    exit 0
fi

# ---------------------------------------------------------------------------
# 3. Install the theme files (safe: doesn't change what's active yet).
#    Done now, silently -- it has to happen before the size wizard below so
#    hyprctl has something to preview, but we report it later as part of the
#    "Installing Brushbuddy..." checklist so the flow reads top-to-bottom.
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$DEST_DIR")"
rm -rf "$DEST_DIR"
cp -a "$THEME_SRC" "$DEST_DIR"

# Revert live cursor AND remove the just-copied theme dir on any abnormal
# exit before the user has confirmed a size -- otherwise a cancelled wizard
# (or a crash) leaves Brushbuddy-Bibata sitting in ~/.local/share/icons with
# no install-state to match it, which then makes uninstall.sh unable to find
# anything to restore.
CONFIRMED=0
cleanup() {
    if [ "$CONFIRMED" != 1 ]; then
        hyprctl setcursor "$PREV_HYPRCURSOR_THEME" "$PREV_HYPRCURSOR_SIZE" >/dev/null 2>&1 || true
        rm -rf "$DEST_DIR"
    fi
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# 4. Choose a size -- live-tested, one at a time, wait for explicit approval
# ---------------------------------------------------------------------------
rule
printf '\n'

if [ -n "$FORCE_SIZE" ]; then
    valid=0
    for s in "${SIZES[@]}"; do [ "$s" = "$FORCE_SIZE" ] && valid=1; done
    if [ "$valid" != 1 ]; then
        err "--size $FORCE_SIZE is not one of the tested sizes (${SIZES[*]})"
        exit 1
    fi
    CHOSEN_SIZE="$FORCE_SIZE"
    hyprctl setcursor "$THEME_NAME" "$CHOSEN_SIZE" >/dev/null 2>&1
    say "  Skipping the size wizard -- installing at ${CHOSEN_SIZE}px (--size)"
else
    say "  Pick your Brushbuddy size"
    idx=1
    for i in "${!SIZES[@]}"; do
        [ "${SIZES[$i]}" = "$RECOMMENDED" ] && idx=$((i+1))
    done
    CHOSEN_SIZE=""
    first_try=1
    while [ -z "$CHOSEN_SIZE" ]; do
        cur="${SIZES[$((idx-1))]}"
        hyprctl setcursor "$THEME_NAME" "$cur" >/dev/null 2>&1
        printf '\n'
        if [ "$cur" = "$RECOMMENDED" ]; then
            printf '  Trying %s%spx%s  %s★ recommended%s\n' "$C_CYAN" "$cur" "$C_RESET" "$C_DIM" "$C_RESET"
        else
            printf '  Trying %s%spx%s\n' "$C_CYAN" "$cur" "$C_RESET"
        fi
        printf '\n'
        if [ "$first_try" = 1 ]; then
            warn "Give Brushbuddy a little wiggle."
            say  "    Hyprland may not redraw the cursor until it moves."
            first_try=0
        else
            warn "Give Brushbuddy a little wiggle."
        fi
        printf '\n'
        say "  [Enter/Y] Keep it    [B] Bigger    [S] Smaller"
        say "  [L] All sizes        [Q] Cancel"
        printf '\n'
        read -r -p "› " ans
        case "${ans:-y}" in
            y|Y|"") CHOSEN_SIZE="$cur" ;;
            b|B) [ "$idx" -lt "${#SIZES[@]}" ] && idx=$((idx+1)) || warn "Already at the largest tested size (${SIZES[-1]}px)." ;;
            s|S) [ "$idx" -gt 1 ] && idx=$((idx-1)) || warn "Already at the smallest tested size (${SIZES[0]}px)." ;;
            l|L)
                printf '\n'
                say "  Available sizes"
                printf '\n'
                for i in "${!SIZES[@]}"; do
                    sz="${SIZES[$i]}"
                    label="$(size_label "$sz")"
                    marker=" "
                    [ "$((i+1))" = "$idx" ] && marker="${C_CYAN}›${C_RESET}"
                    printf '  %s %3spx   %s\n' "$marker" "$sz" "$label"
                done
                printf '\n'
                read -r -p "  Pick a number [1-${#SIZES[@]}]: " pick
                if [ "$pick" -ge 1 ] 2>/dev/null && [ "$pick" -le "${#SIZES[@]}" ] 2>/dev/null; then
                    idx="$pick"
                else
                    warn "Not a valid choice."
                fi
                ;;
            q|Q) say "  Cancelled -- reverting to your previous cursor."; exit 130 ;;
            *) warn "Didn't understand that -- try Enter, B, S, L, or Q." ;;
        esac
    done
    printf '\n'
    ok "${CHOSEN_SIZE}px looks good. Locking it in."
fi

CONFIRMED=1

# ---------------------------------------------------------------------------
# 5. Persist configuration (same detection/backup/write logic as before --
#    only the messages below it changed. See docs/CHANGELOG.md v0.9 for why
#    every one of these paths exists.)
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
    echo "HYPR_CONF_CONFIGURED=$HAS_HYPR_CONF"
    echo "HYPR_LUA_CONFIGURED=$HAS_HYPR_LUA"
    echo "INSTALLED_SIZE=$CHOSEN_SIZE"
} > "$STATE_FILE"

BACKED_UP_MSG="Previous cursor backed up"
if [ "$REUSE_BACKUP" = 1 ]; then
    BACKED_UP_MSG="Original cursor backup preserved"
else
    [ "$HAS_UWSM" = 1 ]      && cp "$UWSM_ENV" "$STATE_DIR/backups/uwsm-env.bak"
    [ "$HAS_GTK3" = 1 ]      && cp "$GTK3_INI" "$STATE_DIR/backups/gtk3-settings.ini.bak"
    [ "$HAS_GTK4" = 1 ]      && cp "$GTK4_INI" "$STATE_DIR/backups/gtk4-settings.ini.bak"
    [ "$HAS_HYPR_CONF" = 1 ] && cp "$HYPR_CONF" "$STATE_DIR/backups/hyprland-conf.bak"
    [ "$HAS_HYPR_LUA" = 1 ]  && cp "$HYPR_LUA_ENV" "$STATE_DIR/backups/environment-lua.bak"
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
fi

# Classic hyprland.conf (non-UWSM sessions) and CachyOS's Lua config wrapper
# both need writing too -- HYPRCURSOR_THEME in uwsm/env is only ever read on
# uwsm-launched sessions, so on a machine that boots Hyprland directly (e.g.
# a display manager's plain "Hyprland" entry) or via CachyOS's Lua config,
# uwsm/env alone leaves the theme reverting to default on every reboot with
# no error. Write every path that applies so it persists regardless of how
# the session is launched.
if [ "$HAS_HYPR_CONF" = 1 ]; then
    sed -i "/${MARKER}/,+4d" "$HYPR_CONF"
    {
        echo "$MARKER"
        echo "env = HYPRCURSOR_THEME,$THEME_NAME"
        echo "env = HYPRCURSOR_SIZE,$CHOSEN_SIZE"
        echo "env = XCURSOR_THEME,$THEME_NAME"
        echo "env = XCURSOR_SIZE,$CHOSEN_SIZE"
    } >> "$HYPR_CONF"
fi

if [ "$HAS_HYPR_LUA" = 1 ]; then
    sed -i "/${LUA_MARKER}/,+4d" "$HYPR_LUA_ENV"
    {
        echo "$LUA_MARKER"
        echo "hl.env(\"HYPRCURSOR_THEME\", \"$THEME_NAME\")"
        echo "hl.env(\"HYPRCURSOR_SIZE\", \"$CHOSEN_SIZE\")"
        echo "hl.env(\"XCURSOR_THEME\", \"$THEME_NAME\")"
        echo "hl.env(\"XCURSOR_SIZE\", \"$CHOSEN_SIZE\")"
    } >> "$HYPR_LUA_ENV"
fi

HYPR_CONFIGURED=0
[ "$HAS_UWSM" = 1 ] || [ "$HAS_HYPR_CONF" = 1 ] || [ "$HAS_HYPR_LUA" = 1 ] && HYPR_CONFIGURED=1

GTK_DONE=0
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
    { [ "$HAS_GTK3" = 1 ] || [ "$HAS_GTK4" = 1 ] || [ "$HAS_GSETTINGS" = 1 ]; } && GTK_DONE=1
fi

FLATPAK_RESULT=""
if [ "$FLATPAK_SUPPORT" = 1 ] && [ "$HAS_FLATPAK" = 1 ]; then
    if flatpak override --user --filesystem="$HOME/.local/share/icons:ro" 2>/dev/null; then
        FLATPAK_RESULT="ok"
    else
        FLATPAK_RESULT="warn"
    fi
fi

# ---------------------------------------------------------------------------
# 6. Apply live, then show the checklist -- everything above already
#    happened; this just reports it in a sensible, fixed order.
# ---------------------------------------------------------------------------
systemctl --user set-environment \
    XCURSOR_THEME="$THEME_NAME" XCURSOR_SIZE="$CHOSEN_SIZE" \
    HYPRCURSOR_THEME="$THEME_NAME" HYPRCURSOR_SIZE="$CHOSEN_SIZE" 2>/dev/null || true
hyprctl setcursor "$THEME_NAME" "$CHOSEN_SIZE" >/dev/null 2>&1

printf '\n'
rule
printf '\n'
say "  Installing Brushbuddy..."
printf '\n'

ok "$BACKED_UP_MSG"
[ "$REUSE_BACKUP" != 1 ] && detail "$STATE_DIR"

ok "Theme installed"
detail "$DEST_DIR"

if [ "$HYPR_CONFIGURED" = 1 ]; then
    ok "Hyprland configured"
    [ "$HAS_UWSM" = 1 ]      && detail "$UWSM_ENV"
    [ "$HAS_HYPR_CONF" = 1 ] && detail "$HYPR_CONF"
    [ "$HAS_HYPR_LUA" = 1 ]  && detail "$HYPR_LUA_ENV"
fi

if [ "$NO_GTK" = 1 ]; then
    warn "Skipped GTK configuration (--no-gtk)"
elif [ "$GTK_DONE" = 1 ]; then
    ok "GTK configured"
fi

[ "$FLATPAK_RESULT" = "ok" ]   && ok "Flatpak apps granted access"
[ "$FLATPAK_RESULT" = "warn" ] && warn "Could not set Flatpak override -- you may need to run this manually"

ok "Current session updated"
[ "$HYPR_CONFIGURED" = 1 ] && ok "Reboot persistence enabled"

# ---------------------------------------------------------------------------
# 7. Success
# ---------------------------------------------------------------------------
printf '\n'
printf '  ╭────────────────────────────────────────────────╮\n'
printf '  │                                                │\n'
printf '  │        %s%sBrushbuddy is now following you.%s        │\n' "$C_BOLD" "$C_TITLE" "$C_RESET"
printf '  │                                                │\n'
printf '  │                       🧙                       │\n'
printf '  │                                                │\n'
printf '  ╰────────────────────────────────────────────────╯\n'
printf '\n'
printf '  Theme   %s\n' "$THEME_NAME"
printf '  Size    %s%spx%s\n' "$C_CYAN" "$CHOSEN_SIZE" "$C_RESET"
printf '  Base    Bibata-Modern-Ice\n'
printf '\n'
say "  Wiggle your mouse if the little guy hasn't appeared yet."
printf '\n'
say "  To send him home:"
say "    ./uninstall.sh"
