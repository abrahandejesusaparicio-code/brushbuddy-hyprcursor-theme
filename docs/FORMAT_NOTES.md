# hyprcursor format notes (learned the hard way)

Target versions: Hyprland 0.56.2, hyprcursor/hyprcursor-util 0.1.13, on
CachyOS. Not an official spec — this is what we actually observed on real
hardware after several failed builds.

## meta.hl: the five real keys

Confirmed by extracting a known-working Bibata-Modern-Ice theme with
`hyprcursor-util --extract` and reading its output directly, and matching
the official `hyprwm/hyprcursor/docs/MAKING_THEMES.md`:

```
resize_algorithm = bilinear   # bilinear | nearest | none
hotspot_x = 0.140625           # fraction 0.0-1.0, NOT pixels
hotspot_y = 0.0703125          # x+ is east, y+ is south
define_override = arrow        # extra names this shape should also answer to
define_override = default
define_size = 24, frame.png    # static: size(px), filename
define_size = 24, f0.png, 117  # animated: size(px), filename, delay(ms)
```

Repeated `define_size` entries of the **same size** form an animation
sequence, in file order. Hotspot is fixed for the whole shape — it does not
vary per animation frame.

We deliberately never used `nominal_size` even though later hyprcursor-util
versions (0.1.11+) support it — the proven-working Bibata reference doesn't
use it, so neither do we.

## The actual root cause of "invisible cursor" (this took a while)

Our first build declared exactly **one** size variant per shape: the
source artwork's native 256×256 resolution, relying on `resize_algorithm =
bilinear` to scale it down to whatever size Hyprland actually requested
(`XCURSOR_SIZE=24` on this machine). Result: completely blank cursor, no
errors anywhere.

`resize_algorithm` does **not** appear to act as a universal runtime
"scale whatever you've got" fallback when zero declared sizes are close to
the requested one. The fix that was empirically confirmed to work, repeatedly,
across default/pointer/wait shapes: declare an **exact size match** for
whatever `XCURSOR_SIZE` your session actually uses (24px here), in addition
to keeping the original high-res source (256px) for quality at other
scales/DPIs. Every shape in this repo's `working-state/` therefore has two
`define_size` groups per animation: one full frame set at 24px, one full
frame set at 256px.

We did not exhaustively test whether a smaller ladder (e.g. just 24px alone)
would have been sufficient, or whether Bibata's full 14-size ladder
(16/20/22/24/28/32/40/48/56/64/72/80/88/96) is actually required for full
robustness across different displays/scales. 24+256 is simply the
combination that was proven live on this machine's single 1x-scale display.

## The mouse-redraw trap (caused a lot of false debugging)

Hyprland does not seem to repaint the cursor sprite just because the active
theme changed — only on the next pointer move/hover event. This produced
wildly inconsistent-looking test results early on: identical files, same
`hyprctl setcursor` command, and the outcome depended entirely on whether the
tester was moving the mouse during the test window. A stationary cursor after
a theme swap looks indistinguishable from a genuinely blank/failed load.

**Every live test must actively move the mouse during the test window**, or
the result is meaningless. `tools/safe_test.sh` now prints an explicit
warning about this before every switch.

## Source file quirks (Brushbuddy pack specifically)

- The three files named `*.cur` actually have an `ICONDIR.idType = 1` (ICO)
  header, not `2` (CUR). Their would-be hotspot fields are therefore the ICO
  `wPlanes`/`wBitCount` fields instead, not a real hotspot.
- The `.ani` files' embedded frame records are genuinely typed as CUR
  (`type=2`), but every single embedded frame reports hotspot `(0,0)` — not
  usable data either.
- Net effect: **no source file in this pack carries a usable authored
  hotspot.** All hotspot values in `working-state/*/meta.hl` are visual
  starting guesses based on each shape's alpha-channel bounding box (top-left
  corner for the default/pointer shapes, centered for the wait/spinner
  shape), confirmed clickable/hoverable in live testing but not refined
  further.
- Frame counts/timing (from `docs/FACTCHECK.txt`): default/classic 7 frames
  @ 117ms, pointer/link 2 frames @ 83ms, wait/loading 46 frames @ 83ms.

## Detection/patching notes

`tools/patch_bibata.py` matches Bibata shape directories to our
default/pointer/wait categories by directory name **and** by scanning each
directory's own existing `define_override` lines — this is how it correctly
found that Bibata spreads "pointer" coverage across three separate real
directories (`hand1`, `hand2`, `link`), and "wait" coverage across two
(`wait`, `left_ptr_watch`, the latter of which also carries several
hashed KDE/GNOME cursor-spec aliases like
`08e8e1c95fe2fc01f976f1e063a24ccd` that get preserved automatically since the
patcher copies whatever overrides already exist on the matched directory).

Resize-direction cursors are a separate, not-yet-patched set of 12
directories, each with a CSS-style `define_override` (`n-resize`,
`nesw-resize`, `col-resize`, etc.) — mapping documented for the v0.6 pass but
not yet built as of v0.5.
