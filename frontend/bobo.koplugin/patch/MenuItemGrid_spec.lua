---@diagnostic disable: undefined-global, undefined-field

-- Tests for the grid menu item layout.
--   * Cover and title share a centered VerticalGroup with a span between
--     them; the title TextWidget is constrained to the cover's horizontal
--     slot so long titles truncate cleanly instead of bleeding into
--     adjacent cells.
--   * The title TextWidget renders bold (post-redesign).
--   * When the entry has unread chapters, a corner badge is overlaid on the
--     cover's top-right via OverlapGroup + RightContainer. When there are
--     no unread chapters, no badge is rendered. Counts > 99 collapse to
--     "99+".

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
  getWidth    = function() return 600 end,
  getHeight   = function() return 800 end,
  scaleBySize = function(_, n) return n end,
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

-- MenuItemRaw is the bobo MenuItem base class. We want a class that supports
-- `extend`, ignores the heavy parent init, and lets MenuItemGrid:init() run
-- against a fake instance.
local menu_item_stub = stub_class()

-- Stub the cover renderer so we can run init() without ImageWidget machinery.
local generated_cover = { _is_cover = true }
local menu_item_cover_stub = {
  genCover = function(_, w, h)
    generated_cover._w = w
    generated_cover._h = h
    return generated_cover
  end,
}

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
  COLOR_WHITE     = 1,
  COLOR_BLACK     = 2,
  COLOR_DARK_GRAY = 3,
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

describe("MenuItemGrid layout", function()
  before_each(function()
    text_widget_calls = {}
  end)

  it("constrains the title TextWidget to the cover's horizontal slot", function()
    local inst = build_instance()
    inst:init()

    local expected_img_width = inst.dimen.w - 6
    local title_call = find_widget_call(function(opts) return opts.text == inst.text end)

    assert.is_truthy(title_call, "expected title TextWidget to be constructed")
    assert.equal(expected_img_width, title_call.max_width)
  end)

  it("renders the title bold so it pops against the cover frame", function()
    local inst = build_instance()
    inst:init()

    local title_call = find_widget_call(function(opts) return opts.text == inst.text end)
    assert.is_truthy(title_call)
    assert.is_true(title_call.bold == true)
  end)

  it("places a VerticalSpan between the cover and the title in a centered group", function()
    local inst = build_instance()
    inst:init()

    local cover_title_group = walk(inst[1], function(node)
      if not node._is_vertical_group then return false end
      local has_cover_idx, title_idx, span_between
      for i, k in ipairs(node) do
        if k == generated_cover then has_cover_idx = i end
        -- Cover may be wrapped in an OverlapGroup once a badge is rendered.
        if type(k) == "table" and k._is_overlap_group then has_cover_idx = i end
        if type(k) == "table" and k.text == "A very long manga title that would otherwise overflow into the neighboring cell" then
          title_idx = i
        end
      end
      if has_cover_idx and title_idx and title_idx > has_cover_idx then
        for i = has_cover_idx + 1, title_idx - 1 do
          if node[i] and node[i]._is_vertical_span then
            span_between = true
            break
          end
        end
        if span_between and node.align == "center" then return true end
      end
      return false
    end)
    assert.is_truthy(cover_title_group,
      "expected a centered VerticalGroup containing cover, VerticalSpan, then title")
  end)

  it("renders no unread badge when the manga has zero unread chapters", function()
    local inst = build_instance()
    inst:init()

    local badge_overlap = walk(inst[1], function(node) return node._is_overlap_group end)
    assert.is_nil(badge_overlap,
      "no OverlapGroup should be created when there are no unread chapters")
  end)

  it("renders an unread badge over the cover when unread > 0", function()
    local inst = build_instance({ entry = { manga = { unread_chapters_count = 12 } } })
    inst:init()

    local badge_overlap = walk(inst[1], function(node) return node._is_overlap_group end)
    assert.is_truthy(badge_overlap, "expected an OverlapGroup wrapping the cover + badge")

    local has_right_container = walk(badge_overlap, function(node) return node._is_right_container end)
    assert.is_truthy(has_right_container,
      "badge must be inside a RightContainer so it floats to the cover's right edge")

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
