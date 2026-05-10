---@diagnostic disable: undefined-global, undefined-field

-- Tests that CustomDialog's navbar title widget is constructed with a
-- max_width so long titles don't overflow the dialog frame on narrow Kobo
-- screens.

local function stub_class(proto)
  local cls = proto or {}
  cls.__index = cls
  cls.extend  = function(self, t)
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

local screen_state = { w = 600, h = 800 }
local screen_stub = {
  getWidth    = function() return screen_state.w end,
  getHeight   = function() return screen_state.h end,
  getSize     = function() return { w = screen_state.w, h = screen_state.h } end,
  scaleBySize = function(_, n) return n end,
}

local device_stub = {
  screen        = screen_stub,
  hasKeys       = function() return false end,
  isTouchDevice = function() return false end,
  input         = { group = { Any = {} } },
}

local geom_stub = {
  new = function(_, opts)
    local g = opts or {}
    g.copy = function(self)
      local c = {}
      for k, v in pairs(self) do c[k] = v end
      return c
    end
    return g
  end
}

-- Recording TextWidget stub.
local text_widget_calls = {}
local text_widget_stub = stub_class()
local _orig_tw_new = text_widget_stub.new
text_widget_stub.new = function(self, opts)
  table.insert(text_widget_calls, opts or {})
  return _orig_tw_new(self, opts)
end

-- Each `option` returned by `generate` has a dimen with a numeric height so
-- the height-summing loop in CustomDialog:init() works.
local function fake_check(_)
  return { dimen = { h = 30 } }
end

package.loaded["device"]                                  = device_stub
package.loaded["ui/geometry"]                             = geom_stub
package.loaded["ui/widget/infomessage"]                   = stub_class()
package.loaded["ui/font"]                                 = { getFace = function(_, name) return { name = name } end }
package.loaded["ui/gesturerange"]                         = stub_class()
package.loaded["ffi/blitbuffer"]                          = { COLOR_WHITE = 0 }
package.loaded["ui/size"]                                 = { radius = { window = 8 } }
package.loaded["ui/widget/container/framecontainer"]      = stub_class()
package.loaded["ui/widget/container/centercontainer"]     = stub_class()
package.loaded["ui/widget/container/movablecontainer"]    = stub_class()
package.loaded["ui/widget/container/scrollablecontainer"] = stub_class({ getScrollbarWidth = function() return 6 end })
package.loaded["ui/widget/textwidget"]                    = text_widget_stub
package.loaded["ui/widget/horizontalgroup"]               = stub_class()
package.loaded["ui/widget/verticalgroup"]                 = stub_class()

package.loaded["CustomDialog"] = nil
local CustomDialog = require("CustomDialog")

describe("CustomDialog navbar", function()
  before_each(function()
    text_widget_calls = {}
  end)

  it("constrains the title TextWidget so it can't bleed past the dialog edge", function()
    CustomDialog:new {
      title = "A really long dialog title that would otherwise overflow on narrow devices",
      options = { {}, {} },
      generate = fake_check,
      key_events = {},
      ges_events = {},
    }

    -- The navbar TextWidget is the only one with our title text.
    local title_widget
    for _, opts in ipairs(text_widget_calls) do
      if opts.text and tostring(opts.text):find("really long dialog title") then
        title_widget = opts
        break
      end
    end

    assert.is_truthy(title_widget, "expected navbar TextWidget to be constructed")
    assert.is_truthy(title_widget.max_width, "navbar title missing max_width")
    -- Whatever the constraint resolves to, it must leave room for the
    -- horizontal padding on both sides.
    assert.is_true(title_widget.max_width < screen_state.w)
    assert.is_true(title_widget.max_width > 0)
  end)
end)
