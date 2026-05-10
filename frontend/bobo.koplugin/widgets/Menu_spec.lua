---@diagnostic disable: undefined-global, undefined-field

-- Stub the KOReader BaseMenu enough to test the bobo Menu wrapper's rotation
-- override in isolation.

local function noop() end

-- Track Screen rotation state so the override's "are we already in this
-- rotation?" check can be observed from the test.
local screen_state = { rotation = 0 }
local screen_stub = {
  getRotationMode  = function() return screen_state.rotation end,
  setRotationMode  = function(_, r) screen_state.rotation = r end,
  scaleBySize      = function(_, n) return n end,
}

local close_calls = {}
local uimanager_stub = {
  show     = noop,
  close    = function(_, w) table.insert(close_calls, w) end,
  setDirty = noop,
  nextTick = function(_, fn) fn() end,
}

-- Minimal BaseMenu stub: extend() returns a class with new()/extend() so
-- bobo's `Menu = BaseMenu:extend{}` path works. init/updateItems are no-ops
-- the bobo wrapper calls into.
local function stub_class(proto)
  local cls = proto or {}
  cls.__index = cls
  cls.extend = function(self, t)
    local sub = setmetatable(t or {}, { __index = self })
    sub.__index = sub
    sub.extend  = self.extend
    sub.new     = function(_, opts)
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

local base_menu_stub = stub_class({
  init        = noop,
  updateItems = noop,
})

package.loaded["ui/widget/menu"]    = base_menu_stub
package.loaded["ui/network/manager"] = { isConnected = function() return true end }
package.loaded["device"]             = { screen = screen_stub }
package.loaded["ui/uimanager"]       = uimanager_stub
package.loaded["logger"]             = { info = noop, warn = noop, err = noop }
package.loaded["gettext+"]           = function(s) return s end
package.loaded["Icons"]              = { FA_ELLIPSIS_VERTICAL = "•", WIFI_OFF = "X" }

package.loaded["widgets/Menu"] = nil
local Menu = require("widgets/Menu")

describe("widgets/Menu:onSetRotationMode", function()
  before_each(function()
    screen_state.rotation = 0
    close_calls = {}
  end)

  -- Regression: KOReader's BaseMenu:onSetRotationMode reaches through
  -- self._manager.ui.view, but bobo views are shown standalone via
  -- UIManager:show so `_manager` is never set. Without this override, any
  -- rotation event with `_recreate_func` set crashes with
  -- "attempt to index field '_manager' (a nil value)".
  it("does not touch _manager (it stays nil for standalone views)", function()
    local recreated = false
    local view = Menu:new {
      _recreate_func = function() recreated = true end,
    }
    -- _manager is intentionally NOT set — that's the standalone-view shape.
    assert.is_nil(view._manager)

    -- Should not raise.
    local handled = view:onSetRotationMode(1)

    assert.equal(true, handled)
    assert.equal(1, screen_state.rotation)
    assert.equal(true, recreated)
    assert.equal(view, close_calls[1])
  end)

  it("is a no-op when rotation matches the current screen rotation", function()
    screen_state.rotation = 2
    local recreated = false
    local view = Menu:new {
      _recreate_func = function() recreated = true end,
    }

    local handled = view:onSetRotationMode(2)

    assert.equal(false, handled)
    assert.equal(false, recreated)
    assert.equal(0, #close_calls)
  end)

  it("is a no-op when no rotation is supplied", function()
    local view = Menu:new {
      _recreate_func = function() error("should not run") end,
    }

    local handled = view:onSetRotationMode(nil)

    assert.equal(false, handled)
    assert.equal(0, #close_calls)
  end)

  it("still flips the rotation even if _recreate_func is unset", function()
    local view = Menu:new {}

    local handled = view:onSetRotationMode(3)

    assert.equal(false, handled)
    assert.equal(3, screen_state.rotation)
    assert.equal(0, #close_calls)
  end)
end)
