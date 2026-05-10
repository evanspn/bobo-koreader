---@diagnostic disable: undefined-global, undefined-field

-- Tests for the cover-card grid menu item layout.
--
-- Each cell is a card: cover on top (with the unread badge floating in
-- the cover's top-right corner if applicable), and a tight under-cover
-- text band carrying the title (bold black, single-line ellipsized) and
-- a smaller dark-grey timestamp. The previous title-on-cover overlay
-- was rejected because it covered the bottom of every manga's art.

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

local screen_stub = {
  getWidth      = function() return 600 end,
  getHeight     = function() return 800 end,
  scaleBySize   = function(_, n) return n end,
  getScreenMode = function() return "portrait" end,
}

-- Recording stubs so we can assert on widget construction.
local text_widget_calls = {}
local text_widget_stub = stub_class()
local _orig_tw_new = text_widget_stub.new
text_widget_stub.new = function(self, opts)
  table.insert(text_widget_calls, opts or {})
  local inst = _orig_tw_new(self, opts)
  inst.getSize = function() return { w = 30, h = 16 } end
  return inst
end

local vertical_group_stub = stub_class()
vertical_group_stub.new = function(self, opts)
  local inst = setmetatable(opts or {}, self)
  inst._is_vertical_group = true
  return inst
end

local vertical_span_stub = stub_class()
vertical_span_stub.new = function(self, opts)
  local inst = setmetatable(opts or {}, self)
  inst._is_vertical_span = true
  return inst
end

local overlap_group_stub = stub_class()
overlap_group_stub.new = function(self, opts)
  local inst = setmetatable(opts or {}, self)
  inst._is_overlap_group = true
  return inst
end

local right_container_stub = stub_class()
right_container_stub.new = function(self, opts)
  local inst = setmetatable(opts or {}, self)
  inst._is_right_container = true
  return inst
end

local frame_container_stub = stub_class()
frame_container_stub.new = function(self, opts)
  local inst = setmetatable(opts or {}, self)
  inst._is_frame_container = true
  inst.getSize = function() return { w = 40, h = 20 } end
  return inst
end

local menu_item_stub = stub_class()

local generated_cover = { _is_cover = true }
local menu_item_cover_stub = {
  genCover = function(_, w, h)
    generated_cover._w = w
    generated_cover._h = h
    return generated_cover
  end,
}

local BLACK_COLOR = { name = "black" }
local DARK_GRAY_COLOR = { name = "dark_gray" }
local WHITE_COLOR = { name = "white" }

package.loaded["ui/gesturerange"]                    = stub_class()
package.loaded["ui/widget/verticalgroup"]            = vertical_group_stub
package.loaded["ui/widget/verticalspan"]             = vertical_span_stub
package.loaded["ui/size"]                            = {
  padding = { fullscreen = 8 },
  span    = { vertical_default = 4 },
}
package.loaded["ui/widget/textwidget"]               = text_widget_stub
package.loaded["MenuItem"]                           = menu_item_stub
package.loaded["device"]                             = { screen = screen_stub }
package.loaded["ui/font"]                            = { getFace = function(_, name) return { name = name } end }
package.loaded["ui/widget/container/framecontainer"] = frame_container_stub
package.loaded["ffi/blitbuffer"]                     = {
  TRANSPARENT     = 0,
  COLOR_WHITE     = WHITE_COLOR,
  COLOR_BLACK     = BLACK_COLOR,
  COLOR_DARK_GRAY = DARK_GRAY_COLOR,
  ColorRGB24      = function(r, g, b) return { r = r, g = g, b = b, _is_rgb = true } end,
}
package.loaded["ui/widget/horizontalgroup"]          = stub_class()
package.loaded["ui/widget/horizontalspan"]           = stub_class()
package.loaded["ui/widget/overlapgroup"]             = overlap_group_stub
package.loaded["ui/widget/container/rightcontainer"] = right_container_stub
package.loaded["ui/geometry"]                        = {
  new = function(_, opts) return opts end,
}
package.loaded["patch/MenuItemCover"]                = menu_item_cover_stub

package.loaded["patch/MenuItemGrid"] = nil
local MenuItemGrid = require("patch/MenuItemGrid")

local TEXT_BAND_H = 36 -- must match TEXT_BAND_HEIGHT in MenuItemGrid.lua

local function build_instance(overrides)
  local inst = {
    dimen     = { w = 200, h = 320 },
    text      = "A very long manga title that would otherwise overflow into the neighboring cell",
    font      = "smallinfofont",
    font_size = 18,
    infont    = "infont",
    infont_size = 14,
    bold      = false,
    dim       = false,
    mandatory = "2 hours",
    entry     = { manga = { unread_chapters_count = 0 } },
  }
  if overrides then
    for k, v in pairs(overrides) do inst[k] = v end
  end
  return setmetatable(inst, { __index = MenuItemGrid })
end

local function find_widget_call(predicate)
  for _, opts in ipairs(text_widget_calls) do
    if predicate(opts) then return opts end
  end
  return nil
end

local function walk(node, predicate, depth)
  depth = depth or 0
  if depth > 12 or type(node) ~= "table" then return nil end
  if predicate(node) then return node end
  for _, child in pairs(node) do
    if type(child) == "table" then
      local found = walk(child, predicate, depth + 1)
      if found then return found end
    end
  end
  return nil
end

describe("MenuItemGrid card layout", function()
  before_each(function()
    text_widget_calls = {}
  end)

  it("reserves the under-cover text band so the cover never carries text on top of it", function()
    local inst = build_instance()
    inst:init()

    -- Cover height = card_height - text_band_h.
    -- card_height = dimen.h - 2 * CARD_INSET (3 each side) = 314.
    -- text_band_h = 36 (Screen:scaleBySize is identity in tests).
    assert.equal(inst.dimen.w - 6, generated_cover._w)
    assert.equal(inst.dimen.h - 6 - TEXT_BAND_H, generated_cover._h)
  end)

  it("renders the title in bold black under the cover (not white over the cover art)", function()
    local inst = build_instance()
    inst:init()

    local title_call = find_widget_call(function(opts) return opts.text == inst.text end)
    assert.is_truthy(title_call, "expected title TextWidget to be constructed")
    assert.is_true(title_call.bold == true, "title should be bold")
    assert.equal(BLACK_COLOR, title_call.fgcolor,
      "title must be black on the page so it doesn't sit on top of the cover art")
    assert.is_true(title_call.max_width and title_call.max_width > 0,
      "title is constrained so it ellipsizes inside the text band")
  end)

  it("renders the timestamp in dark grey under the title when mandatory is set", function()
    local inst = build_instance({ mandatory = "just now" })
    inst:init()

    local ts_call = find_widget_call(function(opts) return opts.text == "just now" end)
    assert.is_truthy(ts_call, "timestamp text widget should exist when mandatory is non-empty")
    assert.equal(DARK_GRAY_COLOR, ts_call.fgcolor)
  end)

  it("omits the timestamp widget when mandatory is empty or nil", function()
    local inst = build_instance({ mandatory = "" })
    inst:init()

    local extras = 0
    for _, opts in ipairs(text_widget_calls) do
      if opts.text ~= inst.text and type(opts.text) == "string" and opts.text ~= "" then
        extras = extras + 1
      end
    end
    assert.equal(0, extras, "no extra TextWidgets should be created when mandatory is empty")
  end)

  it("places cover above the text band in a VerticalGroup (no overlap on the cover art)", function()
    local inst = build_instance()
    inst:init()

    -- The card root is now a VerticalGroup [cover_or_overlap, text_band], not
    -- an OverlapGroup. The cover is no longer covered by the text band.
    local card_vgroup = walk(inst[1], function(node)
      if not node._is_vertical_group then return false end
      local has_cover, has_text_band
      for _, k in ipairs(node) do
        if k == generated_cover then has_cover = true end
        -- The text band is a FrameContainer, not the cover.
        if type(k) == "table" and k._is_frame_container and not has_text_band and has_cover then
          has_text_band = true
        end
      end
      return has_cover and has_text_band
    end)
    assert.is_truthy(card_vgroup,
      "card root should stack [cover, text_band] in a VerticalGroup so the band sits below the cover")
  end)

  it("renders no unread badge when the manga has zero unread chapters", function()
    local inst = build_instance()
    inst:init()

    local right = walk(inst[1], function(node) return node._is_right_container end)
    assert.is_nil(right, "no badge / RightContainer should be created when unread is 0")
  end)

  it("renders an unread badge in the cover's top-right when unread > 0", function()
    local inst = build_instance({ entry = { manga = { unread_chapters_count = 12 } } })
    inst:init()

    local right = walk(inst[1], function(node) return node._is_right_container end)
    assert.is_truthy(right, "badge must be inside a RightContainer to float to the cover's right edge")

    -- The badge OverlapGroup wraps just the cover (so the badge floats over
    -- the cover art), not the entire card.
    local overlap = walk(inst[1], function(node) return node._is_overlap_group end)
    assert.is_truthy(overlap, "badge requires an OverlapGroup wrapping the cover")

    local badge_text = find_widget_call(function(opts) return opts.text == "12" end)
    assert.is_truthy(badge_text, "badge text widget should display the unread count")
    assert.is_true(badge_text.bold == true, "badge text should be bold")
  end)

  it("caps the unread badge at 99+", function()
    local inst = build_instance({ entry = { manga = { unread_chapters_count = 348 } } })
    inst:init()

    local badge_text = find_widget_call(function(opts) return opts.text == "99+" end)
    assert.is_truthy(badge_text, "badge text widget should display 99+ when count > 99")
  end)
end)
