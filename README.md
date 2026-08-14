# Brushbuddy → Hyprcursor

A custom animated cursor theme for Hyprland, built from a "Brushbuddy witch hat"
Windows cursor pack (`.cur`/`.ani`) and merged into a Bibata-Modern-Ice base so
only the default pointer, link/hand pointer, and busy/wait cursors are replaced
— everything else (resize handles, text cursor, crosshair, etc.) stays exactly
as Bibata ships it.

**Status: v0.7** — all 18 shapes (default, pointer, wait, 12 resize
directions) confirmed working at multiple cursor sizes, installed live on
the target machine (Sentinel-home, Hyprland 0.56.2, hyprcursor 0.1.13) at
`XCURSOR_SIZE=32`. Every shape now carries an explicit six-raster ladder
(24/32/48/64/96/256px) instead of just two sizes — see `docs/CHANGELOG.md`
for why that mattered (a real, reproduced-twice bug where an in-between size
rendered *smaller* than a smaller requested size).

This repo is documentation + source, not a redistribution of Bibata. To build
the full merged theme you need your own local Bibata-Modern-Ice install and
the `hyprcursor-util` from the `hyprcursor` package.

## Repo layout

```
originals/         The 6 source Windows cursor files (3 static .cur, 3 animated .ani)
working-state/      The hyprcursor "working-state" source for our 18 patched shapes
                     (left_ptr, hand1, hand2, link, left_ptr_watch, wait, plus 12
                     resize-direction shapes) — each with an explicit six-size
                     define_size ladder (24/32/48/64/96/256px) per animation frame
tools/               Scripts used to build/test/patch (see below)
docs/
  FACTCHECK.txt      Raw source-file analysis (frame counts, timing, header quirks)
  FORMAT_NOTES.md     What we learned about the hyprcursor format the hard way
  CHANGELOG.md        Version history / debugging journey, v0.1 → v0.7
```

## Tools

- `extract_ani.py` — parses Windows `.ani` (RIFF/ACON) files and pulls out PNG
  frames + per-frame timing, no Pillow required (frames are PNG-backed CUR records).
- `validate_theme.py` — checks a hyprcursor working-state tree's `meta.hl` files
  for correct keys and that every referenced size/image actually exists.
- `patch_bibata.py` — takes a `hyprcursor-util --extract`'d Bibata-Modern-Ice
  tree, auto-detects which of its shape directories correspond to
  default/pointer/wait/resize (by name + existing `define_override` aliases),
  and produces a **patched copy** with Brushbuddy frames swapped in at an
  explicit 24/32/48/64/96/256px ladder — the original extraction is never
  modified.
- `build_stage.sh` / `safe_test.sh` — compile a working-state tree with
  `hyprcursor-util --create` and (for `safe_test.sh`) install it under a
  scratch theme name, switch to it live, then **automatically revert** to a
  known-good fallback theme after N seconds — used for every live test on the
  real machine so a bad build never leaves the cursor broken for long.

## How to build the full merged theme yourself

```bash
# 1. Extract your own installed Bibata-Modern-Ice into working-state form
hyprcursor-util --extract ~/.local/share/icons/Bibata-Modern-Ice \
    --output /tmp/bibata-extracted

# 2. Patch a copy with the Brushbuddy shapes from this repo
python3 tools/patch_bibata.py \
    /tmp/bibata-extracted/extracted_Bibata-Modern-Ice \
    /tmp/Brushbuddy-Bibata-working \
    --apply
# (patch_bibata.py reads Brushbuddy source frames from its sibling
#  extracted/{classic,pointer,wait}/ directory — see tools/patch_bibata.py
#  header for the exact layout it expects, or point EXTRACTED at
#  working-state/hyprcursors/ frame_*.png files in this repo)

# 3. Rename the copy's identity so it doesn't claim to be Bibata
sed -i 's/^name = .*/name = Brushbuddy-Bibata/' /tmp/Brushbuddy-Bibata-working/manifest.hl

# 4. Validate, then compile
python3 tools/validate_theme.py /tmp/Brushbuddy-Bibata-working
hyprcursor-util --create /tmp/Brushbuddy-Bibata-working --output /tmp/Brushbuddy-Bibata-build

# 5. Install
cp -a /tmp/Brushbuddy-Bibata-build/theme_Brushbuddy-Bibata \
      ~/.local/share/icons/Brushbuddy-Bibata

# 6. Point your session at it (Hyprland/UWSM example — ~/.config/uwsm/env):
#   export HYPRCURSOR_THEME="Brushbuddy-Bibata"
#   export HYPRCURSOR_SIZE=32
#   export XCURSOR_THEME="Brushbuddy-Bibata"
#   export XCURSOR_SIZE=32
# then live-apply without logging out:
#   systemctl --user set-environment XCURSOR_THEME=Brushbuddy-Bibata XCURSOR_SIZE=32 \
#       HYPRCURSOR_THEME=Brushbuddy-Bibata HYPRCURSOR_SIZE=32
#   hyprctl setcursor Brushbuddy-Bibata 32
```

Also update GTK's `gtk-cursor-theme-name` in `~/.config/gtk-3.0/settings.ini`
and `gtk-4.0/settings.ini`, and `gsettings set org.gnome.desktop.interface
cursor-theme Brushbuddy-Bibata`, for full GTK-app coverage.

**Important:** after any `hyprctl setcursor`, move the mouse. Hyprland does
not appear to redraw the cursor sprite purely because the theme changed
underneath it — only on the next move/hover event. A stationary cursor right
after a theme switch can look identical to a failed/blank load even when the
switch actually succeeded. See `docs/FORMAT_NOTES.md`.

## Credits

- Source cursor art: "Brushbuddy" witch-hat pack (third-party, not authored here)
- Format reverse-engineering, `.ani` parsing, and machine-specific testing: Claude (Anthropic)
- hyprcursor tooling (`patch_bibata.py`, `validate_theme.py`, size-ladder fix): Delamain (ChatGPT)
- Testing, verification, and final calls on every live cursor swap: Ace
