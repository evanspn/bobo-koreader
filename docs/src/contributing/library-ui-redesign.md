# Library UI Redesign

Design plan for the Library grid view (`LibraryView.lua` + `patch/MenuItemGrid.lua`). **Target device: Kobo Libra Colour (E Ink Kaleido 3).** Greyscale Kobos are explicitly out of scope for this redesign — color is used as a primary signal, not an enhancement.

## Why we're redoing it

The current grid renders flat: covers float on the page with no frame, the title bar packs six icons across one row with no breathing room, and the unread count is a small text glyph buried under the cover. There is no visual signal for "currently reading", "new chapters", or read progress — every cell looks identical.

## Hardware constraints (Kaleido 3)

The Libra Colour layers a color filter array (CFA) on top of a 300 ppi greyscale e-ink panel.

| Property | Value | Implication for design |
|---|---|---|
| Color resolution | ~150 ppi (half of greyscale) | Don't carry detail in color — no thin colored lines, no colored small text |
| Total colors | 4096 | Plenty for our needs, but only ~16 are reliably distinguishable |
| Saturation | Muted vs LCD due to CFA | Prefer saturated primaries (red/blue/orange/green); pastels wash out |
| Refresh | Slow, ghosting on partial refresh | No animations, minimize per-cell widget count |

**Rule of thumb:** black + white + greys carry structure and text; color is reserved for **state** (unread, in-progress, currently reading).

## Design tokens

Use KOReader's `Blitbuffer` color constants where possible; introduce a small accent palette via `Blitbuffer.Color8()` / `ColorRGB24()`.

### Palette

| Token | Value | Use |
|---|---|---|
| `bobo.ink` | `COLOR_BLACK` | Primary text, cover frames, progress bar fill |
| `bobo.ink_dim` | `COLOR_DARK_GRAY` | Secondary text (timestamps, source name) |
| `bobo.rule` | `COLOR_LIGHT_GRAY` | Dividers, progress track |
| `bobo.page` | `COLOR_WHITE` | Background |
| `bobo.accent` | `ColorRGB24(0xC0, 0x39, 0x2B)` (deep red) | Unread badge fill |
| `bobo.accent_alt` | `ColorRGB24(0x1F, 0x6F, 0xB9)` (deep blue) | "Currently reading" border |
| `bobo.accent_warn` | `ColorRGB24(0xE6, 0x82, 0x2E)` (warm orange) | Optional: stale (>30d) library items |

Accents reuse the existing `Avatar.lua` palette so the color identity stays consistent across the app. Values picked for Kaleido 3: full saturation, mid-luminance so they read against both the warm-light page and an unlit cool page.

### Spacing

Reuse KOReader's `Size.padding.*` and `Size.span.*`; add named multiples in code rather than magic numbers. Cell internal padding stays at `Size.padding.fullscreen` (matches today). Cover-to-title gap goes from `Size.span.vertical_default` to `Size.span.vertical_default * 2` to give the title room.

### Typography

| Element | Font | Size | Weight |
|---|---|---|---|
| Title bar title | `tfont` | unchanged | bold |
| Cover title | `cfont` | unchanged | **bold** (currently regular) |
| Mandatory line | `infont` | unchanged | regular, `ink_dim` |
| Badge | `infont` | -2 | bold, white on accent |
| Footer page indicator | `cfont` | unchanged | regular |

## Component redesigns

### 1. Cover card (`patch/MenuItemGrid.lua`)

```
┌─────────────────┐
│ ╔═════════════╗▓│   ← cover (img_width × img_height)
│ ║             ║▓│     framed with 1px ink_dim border
│ ║   COVER     ║▓│     drop-shadow: 2-3px offset rule rectangle
│ ║             ║▓│
│ ║         ╔══╗║▓│   ← unread badge: top-right, accent fill,
│ ║         ║33║║▓│     white bold text, only when unread > 0
│ ║         ╚══╝║▓│
│ ║▓▓▓▓▓░░░░░░░║▓│   ← progress bar: 3px, ink fill / rule track
│ ╚═════════════╝▓│     hidden when total_chapters unknown
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │
│  Super Ball Girls │   ← bold title
│  just now         │   ← timestamp only (badge replaces 🔔33)
└─────────────────┘
```

Key changes vs today:

- **Frame + drop shadow.** Wrap `cover_widget` in a `FrameContainer` with `bordersize=1, color=bobo.rule`. Behind it, lay a 2px-offset filled rectangle in `bobo.rule` to fake a shadow. On greyscale this looks like a card; on color it stays subtle (the rule grey reads the same).
- **Unread badge.** Replace the trailing `🔔 33` glyph with a `FrameContainer` positioned via `OverlapGroup` over the cover's top-right. Background `bobo.accent`, white bold text, `bordersize=0`, padding `Size.padding.tiny`. Shape: rounded-rectangle approximation (KOReader has `radius` on `FrameContainer`).
- **Progress bar.** New 3px-tall row at the bottom of the cover. Fill = `read_chapters / total_chapters` in `bobo.ink`; track = `bobo.rule`. Backend already returns `unread_chapters_count`; we need to surface `total_chapters` (or compute `read = total - unread`) — see [Data wiring](#data-wiring).
- **Bold title.** Set `bold = true` on the title `TextWidget`. Drop the `🔔 N` from the mandatory line entirely (it's now the badge).
- **Currently-reading highlight.** If `manga.id == continue_reading_target`, swap the cover frame color to `bobo.accent_alt` and bump `bordersize` to 2. (Optional, behind a setting.)

### 2. Title bar (`LibraryView:patchTitleBar`)

The current bar has six tap targets across the top (settings, playlist, sort, bell, search, close). On a 7" Libra at portrait that's ~80px per target — fine, but visually crowded.

Redesign:

```
┌───────────────────────────────────────────────┐
│ ⚙          Library          🔍   🔔 0     ✕   │
└───────────────────────────────────────────────┘
```

- Collapse `settings` (⚙) + `playlist` (column.two) + `sort` (align.center) into a single overflow icon (`FA_ELLIPSIS_VERTICAL`) on the left that opens a small action menu listing the three.
- Keep search, notification bell, and close on the right.
- Title typography: existing TitleBar bold is fine; add a 1px `bobo.rule` underline rule across the full bar to separate it from the grid.

The collapse is the highest-leverage change for "looks less busy" without losing functionality.

### 3. Footer pagination

Today: `«   ‹   Page 1 of 3   ›   »` — five tap targets in a row.

Redesign:

```
        ‹       1 / 3       ›
```

- Drop `«` / `»` (jump-to-end). Hold-tap on `‹`/`›` can do the same — document it.
- Center the indicator; bump `‹` and `›` to 1.5× the current icon size for thumbable targets.
- On the only-one-page case, hide the footer entirely (today it shows greyed-out arrows).

### 4. Empty state

When the library is empty, the view currently renders one wrapped sentence in the grid. Replace with a centered illustration block:

```
        ┌──────┐
        │  📖  │       ← FA_BOOK in bobo.accent, 64px
        └──────┘
     Your library is empty
   Hold a manga in search to add it
        [ Search now ]   ← button, accent_alt
```

## Data wiring

The backend `GET /library` response already includes per-manga `unread_chapters_count` and `last_read`. For the progress bar we need `total_chapters` (or `read_chapters`) — confirm via:

- `backend/server/src/routes/library.rs` — check the serialized struct.
- If absent, add `read_chapters: i64` and `total_chapters: i64` to the response (the chapter table already has read state).

Lua side: thread the new fields through `LibraryView:generateItemTableFromMangas` into the `item_table` entry, and read them in `MenuItemGrid:init` to size the progress bar.

## Implementation phases

Each phase ships as its own PR (per CLAUDE.md: one PR per piece of work).

| Phase | Scope | Files |
|---|---|---|
| 1 | Framed covers + drop shadow + bold title | `patch/MenuItemGrid.lua` |
| 2 | Corner unread badge (color, with greyscale fallback) | `patch/MenuItemGrid.lua`, `LibraryView.lua` (data) |
| 3 | Progress bar | `patch/MenuItemGrid.lua`, `LibraryView.lua`, possibly `backend/server/src/routes/library.rs` |
| 4 | Title bar overflow collapse + underline rule | `LibraryView.lua` (`patchTitleBar`) |
| 5 | Footer simplification | `widgets/Menu.lua` or `patch/MenuCustom.lua` (whichever owns the page row) |
| 6 | Empty state polish | `LibraryView.lua` (`generateEmptyViewItemTable`) |
| 7 | Currently-reading highlight (opt-in setting) | `LibraryView.lua`, `Settings.lua`, `patch/MenuItemGrid.lua` |

Each phase needs a `*_spec.lua` test alongside the touched module (CLAUDE.md rule). Run:

```
busted --lua luajit -C frontend/bobo.koplugin .
```

before pushing.

## Open questions

1. Do we want a per-user toggle to fall back to the old flat grid? (Probably no — the new grid still works monochrome.)
2. Progress bar at bottom of cover, or as a thin pill below the title? Bottom-of-cover is more "manga app", below-title is more "library catalog".
3. Should the unread badge cap at "99+"? Today it shows raw counts (e.g. 348).
