# Changelog

## v0.1 — first attempt, plain Xcursor
Parsed the 6 source `.cur`/`.ani` files by hand (no existing Linux tool reads
`.ani`), built PNG frames + `xcursorgen` configs, compiled a plain Xcursor
theme, wired it into `uwsm/env`/GTK/gsettings. `hyprctl setcursor` accepted it
without error but nothing visually changed — Hyprland's live theme-switch
appears to prefer its native hyprcursor format over plain Xcursor.

## v0.2 — first hyprcursor attempt
Reverse-engineered the hyprcursor "working-state" source format (no complete
public spec existed) by running `hyprcursor-util --extract` on the machine's
already-working Bibata-Modern-Ice theme and reading its output directly.
Built a matching source tree, compiled successfully, installed live —
**cursor went completely invisible**. Immediately reverted to Bibata.
Root cause not yet understood at this point.

## v0.3 — collaborative debugging kit
Brought in a second AI collaborator ("Delamain") to build an
independent, isolated test kit (`brushbuddy-hyprcursor-kit.zip`): three
incremental stages (static-only → +2-frame pointer → +46-frame wait), a
Bibata-preserving patcher (`patch_bibata.py`), a strict validator, and a
bounded auto-reverting test harness (`safe_test.sh`) so no live test could
leave the machine cursorless for more than ~10 seconds. All code reviewed
line-by-line before running. Stage 1 (single static frame) reproduced the
invisible-cursor bug in isolation — ruled out animation/frame-count entirely.

## v0.4 — root cause found: size ladder + mouse-redraw trap
Isolated the fix: a single oversized (256px) source frame plus
`resize_algorithm = bilinear` is **not** sufficient at Hyprland's actual
requested size (`XCURSOR_SIZE=24`) — needs an explicit size variant at/near
24px. Confirmed, then immediately reproduced a false negative on the exact
same files — turned out Hyprland only redraws the cursor sprite on a
move/hover event, so a stationary mouse during a test window is
indistinguishable from a real failure. Once that variable was controlled
for, results became fully reproducible. `safe_test.sh` updated to warn about
this explicitly before every switch.

## v0.5 — shipped
Kit v2: every shape now carries a proven 24px + 256px `define_size` ladder.
All three stages (static default, 2-frame pointer, 46-frame wait)
individually confirmed rendering and animating correctly via bounded live
tests. `patch_bibata.py` extended to write the same size ladder when patching
a real Bibata copy. Built the full patched-Bibata theme
(`Brushbuddy-Bibata`), diffed against the untouched original Bibata
extraction to confirm only the 6 intended shape directories + `manifest.hl`
changed, compiled (56 shapes total), installed permanently (uwsm env, GTK
3/4 settings, gsettings, live `systemctl --user set-environment` +
`hyprctl setcursor`), confirmed working end-to-end on the real desktop.
Leftover probe themes and the broken v0.2 build cleaned up.

## v0.6 — resize cursors + hotspot fix
Extended the pointer animation to all 12 resize-direction shapes (`top_side`,
`bottom_side`, `left_side`, `right_side`, all 4 corners,
`fd_double_arrow`/`bd_double_arrow`, `sb_h_double_arrow`/`sb_v_double_arrow`),
via a new `resize_pointer` category in `patch_bibata.py` that reuses the
existing 2-frame pointer source frames (no new art needed) rather than
mixing them into the `pointer` category directly. Deliberate visual
tradeoff, confirmed intentional: all resize directions now show the same
animation, directional distinction is gone (Hyprland still knows which
resize operation is happening semantically — only the on-screen cursor
shape lost the distinction). Patched 18 total shapes (6 from v0.5 + 12 new),
diffed clean against the untouched Bibata source, compiled (56 shapes),
installed in place over the existing `Brushbuddy-Bibata` theme.

Also fixed the hotspots: the original bounding-box-corner guess placed the
click point at the tip of the witch hat (default) / tip of a raised paw
(pointer) — technically inside the artwork, but a tiny, awkward target far
from where the eye naturally aims. Moved to the midpoint between the
character's two eyes for both `default` and the `pointer` family (which the
12 resize shapes inherit), confirmed by visual crosshair overlay + live
click/hover testing to feel natural.

## v0.7 — six-size raster ladder (24/32/48/64/96/256)
User wanted a bigger cursor than the 24px we'd been testing at. First
surprise: 24px was never a hardware ceiling, just the size we happened to
match when fixing the original invisible-cursor bug — but requesting 48px
on the v0.6 build (which only had exact `define_size` anchors at 24 and
256) rendered *smaller* than 24px, not bigger. Reproduced twice, live,
with controlled mouse movement both times, so it wasn't the redraw quirk
again — a genuine, separate bug, most likely in how hyprcursor 0.1.13's
`resize_algorithm = bilinear` interpolates between two very far-apart
anchors (256/24 ≈ 10.7x). Root cause not traced into the library; the
diagnosis is described, not proven.

Fix: stopped relying on interpolation across a wide gap entirely. Every
Brushbuddy shape now gets six explicit raster anchors — 24/32/48/64/96/256px,
pre-rendered from the 256px master via Pillow LANCZOS downscale — so any
commonly-requested size has an exact or near match. `bilinear` is still set
as the nominal fallback for odd in-between sizes, but that fallback is
**not actually confirmed to scale**: live-tested 40px (between the 32 and 48
anchors) and it rendered at the same size as 32px, not scaled up toward 48.
No crash, no invisible cursor — just silently snapped to the nearest
defined anchor instead of interpolating. Practical takeaway: don't rely on
`resize_algorithm` doing real scaling at all on this hyprcursor version —
only request sizes that have an exact `define_size` entry.

Also fixed `validate_theme.py`'s scope bug from v0.5/v0.6 (it required the
full size ladder on *every* shape in the tree, including untouched native
Bibata shapes that never had more than a handful of sizes — 50 false-positive
failures every run). Now detects Brushbuddy-generated files by their
`frame_<size>_<NNN>.png` naming pattern and only enforces the ladder on
those.

Landed on **32px** as the actual permanent default after live-testing 24,
32, 40, and 48 — 24 felt too small, 48 felt too big, 32 (an exact ladder
anchor, not interpolated) felt right. Updated `~/.config/uwsm/env`, GTK 3/4
`gtk-cursor-theme-size`, `gsettings`, live `systemctl --user
set-environment`, and `hyprctl setcursor` accordingly.

**Known behavior on hyprcursor 0.1.13:** with only two widely-spaced raster
variants (24px and 256px) and `resize_algorithm = bilinear`, requesting an
in-between size (48px tested) produced a cursor visually *smaller* than the
smaller of the two variants. Exact cause unconfirmed — mitigated, not fixed,
by providing explicit intermediate raster sizes instead of relying on
interpolation across a wide size gap.

**Correction:** further testing (40px, between the close 32/48 anchors)
showed `resize_algorithm = bilinear` doesn't interpolate at all on this
hyprcursor version, not even across narrow gaps — it just silently snaps to
the nearest smaller defined size. Only request sizes with an exact
`define_size` entry.

## v0.8 — installer, uninstaller, precompiled release
Added `install.sh` / `uninstall.sh` so installing no longer requires knowing
what UWSM, GTK settings.ini, gsettings, or `hyprctl setcursor` even are.
`release/Brushbuddy-Bibata/` ships the precompiled theme so end users never
need `hyprcursor-util`, Python, or Pillow — those stay dev-only, for
rebuilding from `working-state/` via `tools/`.

`install.sh`:
- Detects Hyprland/GTK/UWSM/gsettings/Flatpak and reports what it found
- Backs up current cursor settings before changing anything
- Interactive size wizard that **waits for explicit per-size confirmation**
  (y/bigger/smaller/list/quit) instead of auto-advancing through sizes —
  each candidate is applied live with a mouse-movement reminder before
  asking
- `--size`/`--no-gtk`/`--dry-run`/`--flatpak-support` flags for non-wizard use

`uninstall.sh` restores whatever was active before install and removes the
Brushbuddy theme files.

**Bug found and fixed during testing:** running `install.sh` a second time
(e.g. to pick a different size) while Brushbuddy was already installed
captured "Brushbuddy-Bibata" itself as the "previous" theme to restore to.
Running `uninstall.sh` afterward then restored config to point at
Brushbuddy-Bibata *and* deleted the Brushbuddy-Bibata directory in the same
run — a dangling theme reference, cursor left broken. Reproduced directly:
ran the installer twice, then uninstalled, confirmed the config pointed at a
now-deleted directory. Fixed two ways: `install.sh` now detects an existing
non-self-referential backup and reuses it instead of overwriting (so the
*true* original survives any number of resizes), and `uninstall.sh` refuses
to delete the theme directory if the recorded "previous" theme is Brushbuddy
itself (belt-and-suspenders, in case the backup chain breaks some other
way). Verified fixed with a full round-trip test: simulated a genuine
pre-Brushbuddy backup, resized via `--size 48`, confirmed the original
backup survived untouched, then uninstalled and confirmed correct restore
with no dangling reference.

## v0.9 — cursor didn't survive a reboot (fixed)
**Bug found in the field:** on a machine that boots Hyprland directly from a
display manager's plain "Hyprland" session entry (no UWSM), or via CachyOS's
Lua config wrapper (`~/.config/hypr/hyprland.lua` + `config/*.lua`) instead
of a plain `hyprland.conf`, `install.sh` only ever wrote
`HYPRCURSOR_THEME`/`HYPRCURSOR_SIZE` to `~/.config/uwsm/env` — a file that is
never read outside a uwsm-launched session — then fell back to just
*printing* manual `env = ...` lines for the user to add by hand. Nothing
wrote them automatically. Result: the cursor applied fine live, but silently
reverted to the default theme after every reboot, with no error to explain
why.

Fixed by having `install.sh` also detect and write, when present:
- `~/.config/hypr/hyprland.conf` (classic non-UWSM Hyprland), as
  `env = HYPRCURSOR_THEME,...` lines inside a marked, idempotent block
- `~/.config/hypr/config/environment.lua` (CachyOS's Lua config wrapper),
  as `hl.env(...)` calls inside the same kind of marked block

Both are backed up before the first write and restored by `uninstall.sh`,
matching the existing UWSM/GTK backup-and-restore pattern. The "no
persistence path found, here's what to add by hand" fallback now only
triggers if *none* of UWSM env, `hyprland.conf`, or the Lua wrapper exist.
Verified fixed on the machine that originally hit the bug (CachyOS, Lua
config wrapper, no UWSM): cursor now stays set across a full power off/on.
