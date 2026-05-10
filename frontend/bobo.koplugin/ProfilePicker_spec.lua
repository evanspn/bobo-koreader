---@diagnostic disable: undefined-global, undefined-field

-- Smoke tests for ProfilePicker. The visual layout is hard to test in
-- isolation, so the goal here is narrow: pin that tapping a cell calls
-- `on_select(profile)`. That's the contract that broke when cells were
-- WidgetContainers without their own tap handlers.

local function noop() end

local function stub_class(proto)
  local cls = proto or {}
  cls.__index = cls
  cls.extend = function(self, t)
    local sub = setmetatable(t or {}, { __index = self })
    sub.__index = sub
    sub.extend = self.extend
    sub.new = function(_, opts)
      local inst = setmetatable(opts or {}, sub)
      if inst.init then inst:init() end
      return inst
    end
    return sub
  end
  cls.new = function(_, opts)
    local inst = setmetatable(opts or {}, cls)
    if inst.init then inst:init() end
    return inst
  end
  return cls
end

-- Geom: minimal copy + contains semantics so the cell's dimen can be
-- inspected and updated.
local function stub_geom()
  local Geom = {}
  Geom.new = function(_, t)
    local g = t or {}
    g.copy = function(self)
      return setmetatable({ x = self.x, y = self.y, w = self.w, h = self.h }, getmetatable(self))
    end
    return g
  end
  return Geom
end

-- InputContainer base: collect onTap from subclasses and surface it.
local input_container_base = stub_class()

-- Avatar: only its identity matters for this test.
package.loaded["Avatar"] = stub_class({
  getSize = function() return { w = 100, h = 100 } end,
})

package.loaded["ffi/blitbuffer"]                          = { COLOR_WHITE = "WHITE" }
package.loaded["ui/widget/button"]                        = stub_class()
package.loaded["ui/widget/container/centercontainer"]     = stub_class()
package.loaded["device"]                                  = {
  isTouchDevice = function() return true end,
  screen        = { scaleBySize = function(_, n) return n end, getWidth = function() return 800 end, getHeight = function() return 1200 end },
}
package.loaded["ui/font"]                                 = { getFace = function() return {} end }
package.loaded["ui/widget/container/framecontainer"]      = stub_class()
package.loaded["ui/geometry"]                             = stub_geom()
package.loaded["ui/gesturerange"]                         = stub_class()
package.loaded["ui/widget/horizontalgroup"]               = stub_class({
  -- Mimic the real HorizontalGroup: getSize returns the sum of children
  -- widths, which the test doesn't actually need.
  getSize = function() return { w = 0, h = 0 } end,
})
package.loaded["ui/widget/horizontalspan"]                = stub_class()
package.loaded["ui/widget/container/inputcontainer"]      = input_container_base
package.loaded["ui/size"]                                 = { padding = { button = 8 } }
package.loaded["ui/widget/textwidget"]                    = stub_class({
  getSize = function() return { w = 50, h = 20 } end,
})
package.loaded["ui/uimanager"]                            = { show = noop, close = noop }
package.loaded["ui/widget/verticalgroup"]                 = stub_class({
  getSize = function() return { w = 100, h = 150 } end,
})
package.loaded["ui/widget/verticalspan"]                  = stub_class()
package.loaded["gettext+"]                                = function(s) return s end

package.loaded["ProfilePicker"] = nil
local ProfilePicker = require("ProfilePicker")

describe("ProfilePicker cell tap dispatch", function()
  it("calls on_select with the tapped profile", function()
    local profiles = {
      { id = 1, name = "Bob", color = "blue", active = true },
      { id = 2, name = "Alice", color = "red", active = false },
    }
    local selected
    local picker = ProfilePicker:new {
      profiles = profiles,
      on_select = function(p) selected = p end,
    }

    -- The picker constructs a HorizontalGroup of cells. Walk its child
    -- structure to find the cells and fire their tap handlers directly,
    -- which is what the gesture dispatcher does once a tap lands inside
    -- their lazy range.
    local row
    -- frame -> center -> body -> ... -> row (HorizontalGroup of cells)
    -- We don't depend on exact layout depth; instead grab the cells
    -- directly from picker.cells if exposed, or by scanning the body.
    -- Simpler: replicate what KOReader would do by invoking the cell
    -- on_tap closures via the public API. The picker stores cells inside
    -- the HorizontalGroup at index 1 (with HorizontalSpans at even idx).
    -- We exposed the cells implicitly via the row, so dive in:
    local frame = picker[1]
    local center = frame[1]
    local body = center[1]
    -- body = VerticalGroup{ title, span, row, span, manage_btn }
    -- row is at index 3.
    row = body[3]

    -- Cells are at odd indices (1, 3) with spans between.
    local cell_alice = row[3]
    assert.is_function(cell_alice.on_tap)
    cell_alice:onTap()

    assert.is_table(selected)
    assert.equal(2, selected.id)
    assert.equal("Alice", selected.name)
  end)

  it("each cell sets up its own ges_events.Tap with a lazy range", function()
    local profiles = { { id = 1, name = "Bob" } }
    local picker = ProfilePicker:new {
      profiles = profiles,
      on_select = noop,
    }
    local row = picker[1][1][1][3]
    local cell = row[1]

    assert.is_table(cell.ges_events)
    assert.is_table(cell.ges_events.Tap)
    -- The range MUST be a function (lazy) — passing self.dimen directly
    -- would freeze the range at the cell's pre-paint position (0, 0).
    local first_range = cell.ges_events.Tap[1]
    assert.is_function(first_range.range)
  end)
end)

describe("ProfilePicker rotation handling", function()
  before_each(function()
    -- The Device stub must report a stable rotation so onSetRotationMode
    -- can detect that "new rotation differs from current" and trigger a
    -- reshow.
    package.loaded["device"].screen.getRotationMode = function() return 0 end
    package.loaded["device"].screen.setRotationMode = function() end
  end)

  it("ProfilePicker.show stashes a _recreate closure", function()
    -- The closure is what onSetRotationMode / onScreenResize call to
    -- rebuild the widget against the new screen dimensions. Without it,
    -- the picker's old layout sticks around after rotation.
    local opts = { profiles = { { id = 1, name = "Bob" } }, on_select = noop }
    local picker = ProfilePicker.show(opts)
    assert.is_function(picker._recreate)
  end)

  it("onSetRotationMode triggers a reshow when rotation actually changes", function()
    local picker = ProfilePicker:new {
      profiles = { { id = 1, name = "Bob" } },
      on_select = noop,
    }
    local recreate_calls = 0
    picker._recreate = function() recreate_calls = recreate_calls + 1 end

    local handled = picker:onSetRotationMode(1) -- 1 ≠ 0 → real change
    assert.is_true(handled)
    assert.equal(1, recreate_calls,
      "rotating to a different mode must rebuild the picker")
  end)

  it("onSetRotationMode is a no-op when rotation is unchanged", function()
    local picker = ProfilePicker:new {
      profiles = { { id = 1, name = "Bob" } },
      on_select = noop,
    }
    local recreate_calls = 0
    picker._recreate = function() recreate_calls = recreate_calls + 1 end

    local handled = picker:onSetRotationMode(0) -- same as current
    assert.is_false(handled)
    assert.equal(0, recreate_calls)
  end)

  it("onScreenResize triggers a reshow", function()
    -- ScreenResize fires when the framebuffer dimensions change for any
    -- reason (rotation, window resize on desktop, etc.). The picker must
    -- rebuild so its centered layout uses the new screen size.
    local picker = ProfilePicker:new {
      profiles = { { id = 1, name = "Bob" } },
      on_select = noop,
    }
    local recreate_calls = 0
    picker._recreate = function() recreate_calls = recreate_calls + 1 end

    picker:onScreenResize({ w = 1200, h = 800 })
    assert.equal(1, recreate_calls)
  end)
end)
