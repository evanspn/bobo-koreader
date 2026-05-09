# KOReader UI Guide for Kobo

This guide documents the patterns and pitfalls for building widget UIs in the bobo Lua plugin, which runs inside KOReader on Kobo devices. It captures lessons learned the hard way.

## Widget lifecycle

KOReader widgets follow a Lua OOP pattern built on metatables:

```lua
local MyWidget = FocusManager:extend {
  some_field = "default",
}

function MyWidget:init()
  -- Build child widgets here.
  -- self.dimen must be set before returning.
  self[1] = FrameContainer:new { ... }
end
```

`Widget:new(opts)` creates an instance, merges `opts` onto it, and calls `init()` immediately. All layout must be done inside `init()` — not in field defaults at class-level.

## Dimensions: lazy vs eager

**The most common crash source.** KOReader widgets compute their dimensions lazily. Accessing `.dimen` before a widget has been laid out returns `nil`.

| What you want | Wrong | Right |
|---|---|---|
| TitleBar height | `title_bar.dimen.h` | `title_bar:getSize().h` |
| ScrollableContainer scrollbar width | hardcoded constant | `ScrollableContainer:getScrollbarWidth()` |

Always use `getSize()` on widgets whose dimensions depend on content or rendering.

## Layout widths and the scrollbar

`ScrollableContainer` draws its scrollbar **inside** its own `dimen` bounds. Any child widget set to the container's full width will be clipped by the scrollbar.

**Pattern for full-width items inside a ScrollableContainer:**

```lua
local padding   = Size.padding.large
local border    = Size.border.window
local item_width = Screen:getWidth() - 2 * border - 2 * padding
                   - ScrollableContainer:getScrollbarWidth()
```

Reference: `CustomDialog.lua` line 72.

**Typical container nesting in a full-screen dialog:**

```
FrameContainer          (border_size padding, full screen)
  OverlapGroup
    VerticalGroup
      TitleBar
      HorizontalGroup
        HorizontalSpan  (left padding)
        ScrollableContainer   ← dimen.w = item_width (no scrollbar yet)
          VerticalGroup
            ... items, each width = item_width - scrollbar_width
```

Setting an item to `item_width` (the container width) instead of subtracting the scrollbar width causes the item to overflow outside the visible area.

## The `_` (gettext) variable

The plugin uses `local _ = require("gettext+")` as the translation function. **Never use `_` as a throwaway loop variable** in the same scope — the standard `for _, v in ipairs(t)` pattern shadows it:

```lua
-- BAD: _ inside the loop refers to the integer index, not gettext
for _, item in ipairs(list) do
  label = _("Translate me")  -- crashes: attempt to call a number
end

-- GOOD
for _i, item in ipairs(list) do
  label = _("Translate me")
end
```

## Silent crashes via Trapper

`Trapper:wrap(fn)` runs `fn` inside a coroutine. **Lua errors thrown inside a coroutine are silently swallowed** — no crash dialog, no log entry at default log levels. This is the reason a crashing `init()` produces a settings page that simply does nothing.

Wrap widget construction in `pcall` when called from a user action:

```lua
function MyWidget:fetchAndShow(callback)
  local response = Backend.getSomething()
  if response.type == "ERROR" then
    ErrorDialog:show(response.message)
    return
  end

  local ok, result = pcall(function()
    return MyWidget:new { data = response.body, on_return_callback = callback }
  end)

  if not ok then
    ErrorDialog:show(_("Failed to open") .. ": " .. tostring(result))
    return
  end

  UIManager:show(result)
end
```

## Class-level mutable state

Class-level table fields are **shared across all instances**:

```lua
local MyWidget = SomeBase:extend {
  items = {},  -- shared! mutating self.items mutates the class table
}
```

Always initialize mutable fields in `init()`:

```lua
function MyWidget:init()
  self.items = {}  -- instance-local copy
end
```

## Testing with busted

The plugin uses [busted](https://lunarmodules.github.io/busted/) with LuaJIT. KOReader modules are stubbed via `package.loaded` before `require("MyModule")`.

**Global KOReader singletons** (like `G_reader_settings`) must be set with `_G.` prefix so they are visible to the module under test regardless of how busted scopes the spec file's environment:

```lua
-- BAD: may only set the value in the spec's sandboxed environment
G_reader_settings = { readSetting = function() end }

-- GOOD
_G.G_reader_settings = { readSetting = function() end }
```

**Colon vs dot in stubs.** KOReader modules use colon-call syntax (`ErrorDialog:show(msg)`), which passes the table itself as the first argument. Stub functions must account for this:

```lua
-- BAD: msg receives the ErrorDialog table, not the message string
error_dialog_stub.show = function(msg) ... end

-- GOOD
error_dialog_stub.show = function(_, msg) ... end
```

Run the test suite:

```bash
busted --lua luajit -C frontend/bobo.koplugin .
```
