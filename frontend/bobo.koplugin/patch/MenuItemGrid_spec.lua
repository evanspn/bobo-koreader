---@diagnostic disable: undefined-global, undefined-field

-- Tests for the grid menu item layout: covers and titles must share a
-- centered VerticalGroup with a span between them, and the title TextWidget
-- must be constrained to the cover's horizontal slot so long titles
-- truncate cleanly instead of bleeding into adjacent cells.

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
  return _orig_tw_new(self, opts)
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
package.loaded["ui/widget/container/framecontainer"] = stub_class()
package.loaded["ffi/blitbuffer"]                     = { TRANSPARENT = 0, COLOR_WHITE = 1, COLOR_BLACK = 2, COLOR_DARK_GRAY = 3 }
package.loaded["ui/widget/horizontalgroup"]          = stub_class()
package.loaded["ui/widget/horizontalspan"]           = stub_class()
package.loaded["patch/MenuItemCover"]                = menu_item_cover_stub

package.loaded["patch/MenuItemGrid"] = nil
local MenuItemGrid = require("patch/MenuItemGrid")

local function build_instance()
  local inst = {
    dimen     = { w = 200, h = 320 },
    text      = "A very long manga title that would otherwise overflow into the neighboring cell",
    font      = "smallinfofont",
    font_size = 18,
    infont    = "infont",
    infont_size = 14,
    bold      = false,
    dim       = false,
  }
  return setmetatable(inst, { __index = MenuItemGrid })
end

describe("MenuItemGrid layout", function()
  before_each(function()
    text_widget_calls = {}
  end)

  it("constrains the title TextWidget to the cover's horizontal slot", function()
    local inst = build_instance()
    inst:init()

    local expected_img_width = inst.dimen.w - 6

    local title_call
    for _, opts in ipairs(text_widget_calls) do
      if opts.text == inst.text then
        title_call = opts
        break
      end
    end

    assert.is_truthy(title_call, "expected title TextWidget to be constructed")
    assert.equal(expected_img_width, title_call.max_width)
  end)

  it("places a VerticalSpan between the cover and the title in a centered group", function()
    local inst = build_instance()
    inst:init()

    -- Walk every VerticalGroup we constructed and find the one that holds
    -- both the cover and the title.
    local function children_of(group)
      local list = {}
      for _, v in ipairs(group) do table.insert(list, v) end
      return list
    end

    local cover_title_group
    for _, group in pairs(package.loaded["ui/widget/verticalgroup"]) do
      -- only the metatable; instance walking happens via the FrameContainer
      -- wrapping. Easier: rebuild and walk the constructed tree.
    end

    -- Build the tree again and traverse.
    text_widget_calls = {}
    inst = build_instance()
    inst:init()

    -- self[1] is the outermost FrameContainer; recursively look for a
    -- VerticalGroup whose children include the cover stub and a title with
    -- our text.
    local function find_cover_title_group(node, depth)
      if depth > 8 or type(node) ~= "table" then return nil end
      if node._is_vertical_group then
        local kids = children_of(node)
        local has_cover, title_idx, span_before_title
        for i, k in ipairs(kids) do
          if k == generated_cover then has_cover = i end
          if type(k) == "table" and k.text == inst.text then title_idx = i end
        end
        if has_cover and title_idx and title_idx > has_cover then
          for i = has_cover + 1, title_idx - 1 do
            if kids[i] and kids[i]._is_vertical_span then
              span_before_title = true
              break
            end
          end
          if span_before_title and node.align == "center" then
            return node
          end
        end
      end
      for _, child in pairs(node) do
        if type(child) == "table" then
          local found = find_cover_title_group(child, depth + 1)
          if found then return found end
        end
      end
      return nil
    end

    cover_title_group = find_cover_title_group(inst[1], 0)
    assert.is_truthy(cover_title_group,
      "expected a centered VerticalGroup containing cover, VerticalSpan, then title")
  end)
end)
