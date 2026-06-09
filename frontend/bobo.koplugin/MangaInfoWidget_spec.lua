---@diagnostic disable: undefined-global, undefined-field

-- Stubs for KOReader / bobo modules MangaInfoWidget.lua requires at load time.
-- We never call init(); tests build instances by hand with setmetatable and
-- exercise the layout math directly.

local function noop() end

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

local SCREEN_W, SCREEN_H = 800, 1000

local screen_stub = {
  getWidth      = function() return SCREEN_W end,
  getHeight     = function() return SCREEN_H end,
  getSize       = function() return { w = SCREEN_W, h = SCREEN_H } end,
  scaleBySize   = function(_, n) return n end,
  getScreenMode = function() return "portrait" end,
}

local size_stub = {
  padding = { fullscreen = 15, default = 5, large = 10 },
  span    = { vertical_large = 8, vertical_default = 4, horizontal_default = 4 },
  item    = { height_default = 30 },
  line    = { thick = 2 },
  border  = { default = 1, thin = 1, window = 1 },
}

-- Capture the ScrollTextWidget (the description box) construction so tests
-- can assert the height it was given.
local last_scroll_text = nil
local scroll_text_stub = {
  new = function(_, opts)
    last_scroll_text = opts
    return setmetatable(opts, {
      __index = { getSize = function() return { w = opts.width, h = opts.height } end },
    })
  end,
}

local TITLE_BAR_H = 80
local title_bar_stub = {
  new = function(_, _opts)
    return { getSize = function() return { w = SCREEN_W, h = TITLE_BAR_H } end }
  end,
}

package.loaded["ffi/blitbuffer"]                      = setmetatable({}, { __index = function() return 0 end })
package.loaded["ui/widget/container/centercontainer"] = stub_class()
package.loaded["device"]                              = {
  screen        = screen_stub,
  hasKeys       = function() return false end,
  isTouchDevice = function() return false end,
}
package.loaded["ui/font"]                             = { getFace = function() return {} end }
package.loaded["ui/widget/focusmanager"]              = stub_class()
package.loaded["ui/widget/container/framecontainer"]  = stub_class()
package.loaded["ui/geometry"]                         = { new = function(_, opts) return opts end }
package.loaded["ui/gesturerange"]                     = stub_class()
package.loaded["ui/widget/horizontalgroup"]           = stub_class()
package.loaded["ui/widget/horizontalspan"]            = stub_class()
package.loaded["ui/widget/imagewidget"]               = stub_class()
package.loaded["ui/widget/scrolltextwidget"]          = scroll_text_stub
package.loaded["ui/widget/inputtext"]                 = stub_class()
package.loaded["ui/widget/textviewer"]                = stub_class()
package.loaded["ui/widget/container/leftcontainer"]   = stub_class()
package.loaded["ui/widget/linewidget"]                = stub_class()
package.loaded["ui/widget/progresswidget"]            = stub_class()
package.loaded["ui/size"]                             = size_stub
package.loaded["ui/widget/textboxwidget"]             = stub_class()
package.loaded["ui/widget/textwidget"]                = stub_class()
package.loaded["ui/widget/titlebar"]                  = title_bar_stub
package.loaded["ui/uimanager"]                        = { show = noop, close = noop, setDirty = noop }
package.loaded["ui/widget/verticalgroup"]             = stub_class()
package.loaded["ui/widget/verticalspan"]              = stub_class()
package.loaded["ui/widget/infomessage"]               = stub_class()
package.loaded["ui/trapper"]                          = { wrap = function(_, fn) fn() end }
package.loaded["gettext+"]                            = function(s) return s end
package.loaded["ffi/util"]                            = { template = function(s) return s end }
package.loaded["LoadingDialog"]                       = { showAndRun = function(_, _msg, fn) return fn() end }
package.loaded["Backend"]                             = { createCancelId = function() return 1 end }
package.loaded["ErrorDialog"]                         = { show = noop }
package.loaded["utils/calcLastReadText"]              = function() return "" end
package.loaded["utils/formatStats"]                   = {
  formatChapters       = function() return "—" end,
  formatPercentage     = function() return "0 %" end,
  formatCurrentChapter = function() return "—" end,
}

package.loaded["MangaInfoWidget"] = nil
local MangaInfoWidget = require("MangaInfoWidget")

local function fixed_size_widget(h)
  return { getSize = function() return { w = SCREEN_W, h = h } end }
end

local function make_widget()
  return setmetatable({
    padding = size_stub.padding.fullscreen,
    layout = {},
    medium_font_face = {},
    small_font_face = {},
    large_font_face = {},
  }, { __index = MangaInfoWidget })
end

describe("MangaInfoWidget fits all contents on the screen", function()
  before_each(function()
    last_scroll_text = nil
  end)

  it("getStatusContent gives the description exactly the remaining screen height", function()
    -- Regression: the description box used a fixed height, so on smaller
    -- portrait screens (cover + headers + stats already eat most of the
    -- height) the page overflowed past the screen bottom.
    local widget = make_widget()
    widget.genBookInfoGroup   = function() return fixed_size_widget(400) end
    widget.genHeader          = function() return fixed_size_widget(50) end
    widget.genStatisticsGroup = function() return fixed_size_widget(120) end
    local captured_height
    widget.genSummaryGroup = function(_, _width, _manga, available_height)
      captured_height = available_height
      return fixed_size_widget(available_height)
    end

    widget:getStatusContent(SCREEN_W, { title = "T" })

    -- 1000 (screen) - 80 (title bar) - 400 (book info)
    -- - 50 (stats header) - 120 (stats) - 50 (description header)
    assert.equal(300, captured_height)
  end)

  it("genSummaryGroup sizes the description box to the given space minus its top spacer", function()
    local widget = make_widget()

    widget:genSummaryGroup(SCREEN_W, { description = "a description" }, 300)

    assert.is_not_nil(last_scroll_text, "the description ScrollTextWidget must be built")
    -- 300 leftover - 8 (span.vertical_large above the box)
    assert.equal(292, last_scroll_text.height)
  end)

  it("genSummaryGroup clamps tiny leftover space to a readable scrolling minimum", function()
    local widget = make_widget()

    widget:genSummaryGroup(SCREEN_W, { description = "a description" }, 40)

    -- The box scrolls, so a small window still works — but below ~80px it
    -- becomes unusable, so that's the floor.
    assert.equal(80, last_scroll_text.height)
  end)

  it("genSummaryGroup survives a missing height (defensive default to the minimum)", function()
    local widget = make_widget()

    widget:genSummaryGroup(SCREEN_W, { description = "a description" }, nil)

    assert.equal(80, last_scroll_text.height)
  end)
end)
