---@diagnostic disable: undefined-global, undefined-field

-- Stub the KOReader widget system before requiring Settings.lua.
-- Each stub is just enough for Settings:init() to run without crashing.

-- Base widget class stub. new() calls init() so crash tests work correctly.
local function stub_class(proto)
  local cls = proto or {}
  cls.__index = cls
  cls.extend = function(self, t)
    local sub = setmetatable(t or {}, { __index = self })
    sub.__index = sub
    sub.extend = self.extend
    sub.new = function(_, opts)
      local inst = setmetatable(opts or {}, sub)
      -- call init() if it exists, same as KOReader's Widget:new()
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

-- Geom stub: new() returns the table with a copy() method attached.
local function stub_geom()
  return {
    new = function(_, t)
      local g = t or {}
      g.copy = function(self)
        local c = {}
        for k, v in pairs(self) do c[k] = v end
        return c
      end
      return g
    end
  }
end

local screen_stub = {
  getWidth    = function() return 800 end,
  getHeight   = function() return 600 end,
  scaleBySize = function(_, n) return n end,
}
local device_stub = {
  screen        = screen_stub,
  isKindle      = function() return false end,
  hasKeys       = function() return false end,
  isTouchDevice = function() return false end,
}
local size_stub = {
  border  = { window = 2, button = 1 },
  padding = { large = 16, button = 8 },
  radius  = { button = 5 },
}
local font_stub    = { getFace = function(_, name, _size) return { name = name } end }
local paths_stub   = { getHomeDirectory = function() return "/home/user" end }
local blitbuffer_stub = { COLOR_WHITE = 0, COLOR_DARK_GRAY = 1 }

local uimanager_stub = {
  show     = function() end,
  setDirty = function() end,
  close    = function() end,
}

-- TitleBar must return a valid height from getSize() so the scrollable
-- container height calculation (dimen.h - title_bar:getSize().h) works.
local title_bar_stub = stub_class({
  getSize = function() return { w = 800, h = 60 } end
})

-- SettingItem is stubbed so its real init() (which needs more widget deps)
-- is never called. Its new() returns a plain stub table.
local setting_item_stub = stub_class()

-- Global KOReader singletons.
G_reader_settings = {
  readSetting = function(_, _key, default) return default end,
  saveSetting = function() end,
}

-- Preload all KOReader modules required by Settings.lua.
package.loaded["ffi/blitbuffer"]                          = blitbuffer_stub
package.loaded["ui/widget/focusmanager"]                  = stub_class()
package.loaded["ui/widget/container/framecontainer"]      = stub_class()
package.loaded["ui/geometry"]                             = stub_geom()
package.loaded["ui/widget/horizontalgroup"]               = stub_class()
package.loaded["ui/widget/horizontalspan"]                = stub_class()
package.loaded["ui/widget/overlapgroup"]                  = stub_class()
package.loaded["device"]                                  = device_stub
package.loaded["ui/size"]                                 = size_stub
package.loaded["ui/widget/titlebar"]                      = title_bar_stub
package.loaded["ui/uimanager"]                            = uimanager_stub
package.loaded["ui/widget/verticalgroup"]                 = stub_class()
package.loaded["ui/widget/infomessage"]                   = stub_class()
package.loaded["gettext+"]                                = function(s) return s end
package.loaded["Paths"]                                   = paths_stub
package.loaded["ui/font"]                                 = font_stub
package.loaded["ui/widget/textwidget"]                    = stub_class()
package.loaded["ui/widget/container/scrollablecontainer"] = stub_class()
package.loaded["ui/widget/button"]                        = stub_class()
package.loaded["widgets/SettingItem"]                     = setting_item_stub
package.loaded["logger"]                                  = { info = function() end, warn = function() end, err = function() end }

-- Plugin-specific modules we control per-test.
local backend_stub      = {}
local error_dialog_stub = {}
package.loaded["Backend"]    = backend_stub
package.loaded["ErrorDialog"] = error_dialog_stub

-- Force a fresh load of Settings so it picks up the stubs above.
package.loaded["Settings"] = nil
local Settings = require("Settings")

-- ─── helpers ──────────────────────────────────────────────────────────────────

local function make_error_response(msg)
  return { type = "ERROR", message = msg }
end

local function make_success_response(body)
  return { type = "SUCCESS", body = body or {} }
end

-- ─── tests ────────────────────────────────────────────────────────────────────

describe("Settings.fetchAndShow", function()
  local shown_errors, shown_ui

  before_each(function()
    shown_errors = {}
    shown_ui     = {}
    error_dialog_stub.show = function(_, msg) table.insert(shown_errors, msg) end
    uimanager_stub.show    = function(_, w)   table.insert(shown_ui, w) end
  end)

  it("shows an error and does not open the UI when the backend call fails", function()
    backend_stub.getSettings = function()
      return make_error_response("connection refused")
    end

    Settings:fetchAndShow(function() end)

    assert.equal(1, #shown_errors)
    assert.equal("connection refused", shown_errors[1])
    assert.equal(0, #shown_ui)
  end)

  it("shows an error instead of crashing silently when widget init fails", function()
    backend_stub.getSettings = function() return make_success_response() end

    local original_init = Settings.init
    Settings.init = function() error("simulated init crash") end

    Settings:fetchAndShow(function() end)

    Settings.init = original_init

    assert.equal(1, #shown_errors)
    assert.is_true(shown_errors[1]:find("simulated init crash") ~= nil)
    assert.equal(0, #shown_ui)
  end)

  it("opens the settings UI when the backend succeeds", function()
    backend_stub.getSettings = function() return make_success_response() end

    Settings:fetchAndShow(function() end)

    assert.equal(0, #shown_errors)
    assert.equal(1, #shown_ui)
  end)
end)
