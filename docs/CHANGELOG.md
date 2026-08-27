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

## v0.10 — friendlier installer UI + two real bugs found while testing it

The installer worked but read like a technically-correct shell script, not
something anyone actually designed. Rewrote the presentation layer only
(branding header, compact grouped environment detection instead of a wall of
✓/✗ lines, a redesigned size wizard where Enter means "keep it," a labeled
`[L]` size list, a single "Installing Brushbuddy..." checklist instead of
messages interleaved with detection output, a boxed success screen, and a
new `--verbose` flag for anyone who wants exact file paths). Detection,
backup, and persistence logic is untouched -- same brain, nicer face.

Testing that surfaced two real bugs, both now fixed:

1. **Cancelling the size wizard left orphaned files.** `install.sh` copies
   the theme to `~/.local/share/icons/` *before* the size wizard runs (it
   needs the files on disk for the live `hyprctl setcursor` preview), but if
   the wizard was quit or interrupted before a size was confirmed, nothing
   ever cleaned that copy up, and `install-state` was never written. Running
   `uninstall.sh` afterward found no state to restore from and just gave up
   -- even though the cursor itself was never actually switched. `cleanup()`
   now removes the orphaned theme dir on any unconfirmed exit, and
   `uninstall.sh` gained a fallback: if there's no state file but leftover
   theme files exist, it cleans them up and says so, instead of dead-ending.

2. **`detect_current()` trusted the wrong source for "what was installed
   before."** It checked the live process/systemd environment first, and
   the UWSM env file only as a fallback. But `install.sh` itself calls
   `systemctl --user set-environment`, and on at least one machine that
   value kept showing up in *every new shell's* environment even after
   `uninstall.sh` had correctly restored the UWSM env file. Result: running
   `install.sh` again shortly after an `uninstall.sh` could "detect"
   Brushbuddy-Bibata as the user's own previous theme, corrupting the
   backup chain into a self-reference (the exact failure mode v0.8's
   self-reference guard was built to catch -- it did catch it, but only
   after the chain was already broken). Fixed by checking the UWSM env file
   first and falling back to the live environment only when there's no file
   to check -- the file is what actually persists across a reboot, so it's
   the correct source of truth. Reproduced on this repo's own dev machine
   with an install → uninstall → install → uninstall cycle, confirmed fixed
   the same way.

Also added a `LICENSE` (GPL-3.0): the shipped theme is a derivative of
Bibata-Modern-Ice, which is GPL-3.0, so this repo has to carry the same
license forward -- not a free choice, an inherited one.

## v0.11 — real resize/move/text art, 18 → 23 patched shapes

Korada_art dropped a second, much bigger art pack: 9 shapes instead of 3
(classic/link/loading re-supplied unchanged, plus six new ones -- move,
text hover, and horizontal/vertical/diagonal×2 resize). Since v0.6, all 12
resize-direction cursors had been faking it by reusing the 2-frame pointer
animation ("directional distinction is gone" -- a deliberate, documented
tradeoff at the time), and `move`/`text` shipped as untouched stock Bibata
because no Brushbuddy art existed for them. This version removes both
limitations.

`originals/` reorganized into `originals/animated/` (9 files, what the
build actually reads) and `originals/static/` (9 single-frame idle-pose
`.ani` files -- despite the name, not `.cur` -- kept as archival reference,
not fed into the pipeline; see `docs/FACTCHECK.txt`).

`tools/patch_bibata.py` split the old single `resize_pointer` catch-all
into four real categories (`resize_h`, `resize_v`, `resize_diag1` for
NWSE/↖↘, `resize_diag2` for NESW/↗↙ -- orientation confirmed by extracting
and eyeballing the actual frames, not guessed) and added `move` and `text`
categories, matched against Bibata's real shape directories (`move`,
`pointer-move`, `grabbing` / `xterm`, `text`, `vertical-text`). Also had to
teach it that a `DELAYS[kind]` entry can be a per-frame list instead of one
constant: unlike classic/pointer/wait/text, four of the six new source
animations have genuinely uneven frame timing (resize shapes step
83/33/83/33ms, move steps 283/83/117/83/117/83ms) -- a single averaged
delay would have flattened the authored motion. Dry run against a fresh
Bibata extraction detected all 23 target shapes with zero category
conflicts and zero missing-shape warnings on the first attempt; compiled
clean (56 shapes total, only the 23 patched dirs + `manifest.hl` differ
from an untouched Bibata extraction).

Hotspots for all six new categories start at geometric center (0.5, 0.5),
same convention as `wait` -- explicitly a starting guess, not a tuned
value (see `docs/FACTCHECK.txt`).

**Live visual verification hit a wall this session.** The usual process
(switch theme, move the mouse, look) needs a human actually looking at the
screen. Attempting it via automated screenshot (`grim`, after a real
`hyprctl setcursor` swap and synthetic mouse movement via `ydotool`) came
back with the cursor completely invisible in every capture, across three
different hover targets -- because Hyprland renders the cursor sprite on a
hardware overlay plane that screenshot tools compositing from the
framebuffer don't see. This isn't a theme bug; it's a blind spot in the
verification method. What *is* confirmed: `hyprctl setcursor` accepted the
new theme and reverted cleanly, `validate_theme.py` passes, the diff
against untouched Bibata is exactly the 23 intended directories, and every
new source frame was reviewed by hand for correct art/orientation before
the resize-direction mapping was written. What's *not* confirmed: how any
of the 6 new shapes actually look and feel live on screen, hotspot
placement included. Do a live pass before calling this final.

`README.md` updated: intro paragraph no longer claims resize directions
share one animation or that move/text stay stock Bibata; status line bumped
to v0.11 with the 18→23 shape count and the live-verification caveat above;
repo layout section reflects the `originals/animated/` + `originals/static/`
split and the four real resize categories.
