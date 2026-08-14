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
Brought in a second AI collaborator ("Delamain", ChatGPT) to build an
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

## Planned — v0.6
Extend the pointer animation to the 12 resize-direction cursor shapes
(`n-resize` through `nwse-resize`/`col-resize`/`row-resize`) so resizing a
window shows the same hand animation as hovering a link. Mapping of all 12
Bibata directories to their CSS resize names already documented in
`docs/FORMAT_NOTES.md`; not yet built.
