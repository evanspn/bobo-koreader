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

Each cell is a card: the cover image takes the top portion (with the unread badge floating in its top-right corner), and a tight text band beneath the cover carries the title and timestamp. The earlier title-on-cover overlay was rejected because it ate the bottom of every manga's art — Berserk's sword, the Vagabond seal, the Bleach logo all got obscured. Title text now lives outside the cover entirely.

```
┌─────────────────┐
│╔═══════════════╗│   ← cover frame (1px black border)
│║           ╔══╗║│
│║           ║33║║│   ← unread badge: cover top-right, accent
│║           ╚══╝║│     fill, white bold text, only when unread > 0
│║               ║│
│║     COVER     ║│   ← cover_height = card_height - text_band_h
│║               ║│
│║               ║│
│╚═══════════════╝│
│ Super Ball Gi…  │   ← title: bold black, single line, ellipsized
│ just now        │   ← timestamp: smaller, dark grey
└─────────────────┘
```

Key elements:

- **Cover does not get covered.** `MenuItemCover.genCover` is called with `card_width × cover_height`, where `cover_height = card_height − text_band_h`. The 1px black border *around* the cover is the visual top of the card; the text band sits beneath it on the page background, which reads as part of the same cell.
- **Tight text band.** `text_band_h = 36px` (vs KOReader's 44px default). Title is `cfont` bold; timestamp drops to `infont_size − 2`. Single line each, ellipsized at `card_width − 2 × 4px` padding. Net effect: each cell is ~30% taller cover than the original `MenuItemGrid` layout, but with no overlay.
- **Unread badge.** `FrameContainer` positioned via `OverlapGroup` + `RightContainer` over the cover's top-right (the OverlapGroup now wraps just the cover, not the whole card). Background `bobo.accent`, white bold text, `bordersize=0`, `radius=3`. Capped at `99+`.
- **Progress bar (Phase 3).** Will sit at the bottom edge of the cover (1–2px above the cover frame's bottom). Fill = `read_chapters / total_chapters` in `bobo.ink`; track = `bobo.rule`. Needs `total_chapters` on the backend response — see [Data wiring](#data-wiring).
- **Currently-reading highlight (Phase 7).** When implemented, swap the cover frame color to `bobo.accent_alt` and bump `bordersize` to 2.

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

### 3. Footer + persistent action bar

The Libra Colour has hardware page-turn buttons, so on-screen pagination chevrons are dead weight. Modal flows are also slow on e-ink (every menu open/close is a refresh), so common actions need to live on the screen, not in the overflow menu.

The redesign replaces KOReader's pagination chevron row entirely with:

```
┌──────────────────────────────────────┐
│  🔍       ⛛       ▦      ↻           │
│ Search   Sort    View   Refresh      │
│           Page 1 of 3                │
└──────────────────────────────────────┘
```

- **Action bar.** A new `widgets/ActionBar.lua` renders four evenly-spaced `Search · Sort · View · Refresh` cells (Font Awesome glyph + small label) across the full width. Each cell is an `InputContainer` with a `Tap` `GestureRange` covering the whole cell area, not just the glyph. Glyphs come from `Icons.lua` (no dependency on the koreader icon-SVG set).
- **View toggles view mode.** Cycles `grid → cover → base → grid` via `Backend.setSettings(library_view_mode)` + `updateItems`.
- **Page label.** Keeps the existing `self.page_info_text` Button so KOReader's `BaseMenu:updatePageInfo` continues to update the count on page change. The chevron Buttons (`page_info_left_chev` etc.) still exist on `self` so `setEnabled` calls don't error — they're just not in the new `self.page_info` layout, so they don't render.
- **Search moves out of the title bar.** The right side becomes just `bell + close`, since Search is now in the action bar (no duplication).

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
