# My Omarchy brand assets

My Omarchy uses an original **Portal M** identity. The mark combines a stable
virtual-machine boundary, a geometric `M`, and a central entry path into a
personal Omarchy workspace.

## Core assets

- App icon source: [`macos/OmarchyIcon.svg`](../../macos/OmarchyIcon.svg)
- Construction diagram: [`portal-m-construction.svg`](portal-m-construction.svg)
- Brand board: [`my-omarchy-brand-board.svg`](my-omarchy-brand-board.svg)

The app icon is the source for generated macOS icon representations. Do not
commit generated PNG or ICNS files unless a later release process explicitly
requires them.

## Palette

| Token | Value | Usage |
| --- | --- | --- |
| `my-omarchy-ink` | `#151A1D` | Icon background and dark surfaces |
| `my-omarchy-paper` | `#EFF6F3` | Primary symbol fill |
| `my-omarchy-portal` | `#D8F275` | VM boundary and primary accent |
| `my-omarchy-signal` | `#2AD6B5` | Entry path and secondary accent |

These tokens define brand assets only. They do not imply a Phase 1B change to
the app UI theme.

## Usage rules

1. Use the symbol alone for AppIcon, favicon, DMG icon, and compact surfaces.
2. Use the text `My Omarchy` as the wordmark. Do not place wordmark text inside
   the AppIcon.
3. Keep the mark on a dark or neutral background with enough contrast for the
   paper and portal colors.
4. Keep the outer VM boundary visible at small sizes. Avoid adding shadows,
   texture, thin strokes, or extra glyphs inside the icon.
5. Do not use the predecessor product's app icon, official upstream brand mark,
   or third-party artwork as a My Omarchy logo.

## Source and trademark self-check

The Portal M artwork is made from SVG primitives and paths in this repository.
It does not reuse the predecessor app icon, the official upstream mark, or an
external logo file.

Engineering self-check:

- The source SVG contains `My Omarchy` title and Portal M description.
- The symbol is a letter/boundary/entry composition, not the prior geometric
  maze-style mark.
- The README explains that this is an independent product maintained at
  `superops-team/my-omarchy`.
- Upstream Omarchy remains credited as the Linux desktop run inside the VM, but
  the My Omarchy visual identity does not imply upstream endorsement.

This review is an engineering provenance check, not legal clearance.
