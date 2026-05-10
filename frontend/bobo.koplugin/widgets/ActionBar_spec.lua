---@diagnostic disable: undefined-global, undefined-field

-- Tests for the persistent bottom action bar.
--   * Constructs one tappable cell per action with a glyph TextWidget
--     and a label TextWidget stacked vertically.
--   * Tapping anywhere in the cell (not just on the glyph) fires the
--     action's callback.
--   * Cells are evenly sized so the row distributes across the width.

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

local text_widget_calls = {}
local text_widget_stub = stub_class()
local _orig_tw_new = text_widget_stub.new
text_widget_stub.new = function(self, opts)
  table.insert(text_widget_calls, opts or {})
  local inst = _orig_tw_new(self, opts)
  inst.getSize = function() return { w = 30, h = 22 } end
  return inst
end

local vertical_group_stub = stub_class()
vertical_group_stub.new = function(self, opts)
  local inst = setmetatable(opts or {}, self)
  inst._is_vertical_group = true
  inst.getSize = function() return { w = 80, h = 50 } end
  return inst
end

local horizontal_group_stub = stub_class()
horizontal_group_stub.new = function(self, opts)
  local inst = setmetatable(opts or {}, self)
  inst._is_horizontal_group = true
  return inst
end

local frame_container_stub = stub_class()
frame_container_stub.new = function(self, opts)
  local inst = setmetatable(opts or {}, self)
  inst._is_frame_container = true
  inst.getSize = function() return { w = opts and opts.width or 600, h = 60 } end
  return inst
end

local center_container_stub = stub_class()
center_container_stub.new = function(self, opts)
  local inst = setmetatable(opts or {}, self)
  inst._is_center_container = true
  return inst
end

local input_container_stub = stub_class()
input_container_stub.new = function(self, opts)
  local inst = setmetatable(opts or {}, self)
  inst._is_input_container = true
  return inst
end

local uimanager_stub = {
  setDirty = function() end,
}

package.loaded["ffi/blitbuffer"]                       = {
  COLOR_BLACK = "BLACK",
  COLOR_WHITE = "WHITE",
}
package.loaded["ui/widget/container/centercontainer"]  = center_container_stub
package.loaded["device"]                               = { screen = screen_stub }
package.loaded["ui/font"]                              = { getFace = function(_, name) return { name = name } end }
package.loaded["ui/widget/container/framecontainer"]   = frame_container_stub
package.loaded["ui/geometry"]                          = { new = function(_, opts) return opts end }
package.loaded["ui/gesturerange"]                      = stub_class()
package.loaded["ui/widget/horizontalgroup"]            = horizontal_group_stub
package.loaded["ui/widget/container/inputcontainer"]   = input_container_stub
package.loaded["ui/widget/textwidget"]                 = text_widget_stub
package.loaded["ui/uimanager"]                         = uimanager_stub
package.loaded["ui/widget/verticalgroup"]              = vertical_group_stub
package.loaded["ui/widget/verticalspan"]               = stub_class()

package.loaded["widgets/ActionBar"] = nil
local ActionBar = require("widgets/ActionBar")

local function build_actions()
  return {
    search_count  = 0,
    sort_count    = 0,
    view_count    = 0,
    refresh_count = 0,
  }
end

local function build_bar(counts)
  return ActionBar:new {
    width = 600,
    actions = {
      { glyph = "S", label = "Search",  callback = function() counts.search_count  = counts.search_count  + 1 end },
      { glyph = "F", label = "Sort",    callback = function() counts.sort_count    = counts.sort_count    + 1 end },
      { glyph = "V", label = "View",    callback = function() counts.view_count    = counts.view_count    + 1 end },
      { glyph = "R", label = "Refresh", callback = function() counts.refresh_count = counts.refresh_count + 1 end },
    },
  }
end

local function find_cells(bar)
  -- The outer FrameContainer wraps a HorizontalGroup whose positional children
  -- are the action cells.
  local frame = bar[1]
  assert(frame and frame._is_frame_container)
  local row
  for _, child in pairs(frame) do
    if type(child) == "table" and child._is_horizontal_group then
      row = child
      break
    end
  end
  assert(row, "expected HorizontalGroup row inside the frame")
  local cells = {}
  for i, child in ipairs(row) do
    if type(child) == "table" and child._is_input_container then
      cells[#cells + 1] = child
    end
  end
  return cells
end

describe("ActionBar widget", function()
  before_each(function()
    text_widget_calls = {}
  end)

  it("builds one tappable cell per action", function()
    local counts = build_actions()
    local bar = build_bar(counts)
    local cells = find_cells(bar)
    assert.equal(4, #cells)
  end)

  it("renders both the glyph and the label for each action", function()
    build_bar(build_actions())
    local glyphs = {}
    local labels = {}
    for _, opts in ipairs(text_widget_calls) do
      if opts.text == "S" or opts.text == "F" or opts.text == "V" or opts.text == "R" then
        glyphs[opts.text] = true
      end
      if opts.text == "Search" or opts.text == "Sort" or opts.text == "View" or opts.text == "Refresh" then
        labels[opts.text] = true
      end
    end
    assert.is_true(glyphs.S and glyphs.F and glyphs.V and glyphs.R)
    assert.is_true(labels.Search and labels.Sort and labels.View and labels.Refresh)
  end)

  it("fires the matching callback when a cell is tapped", function()
    local counts = build_actions()
    local bar = build_bar(counts)
    local cells = find_cells(bar)

    cells[1]:onTap()
    cells[3]:onTap()
    cells[3]:onTap()

    assert.equal(1, counts.search_count)
    assert.equal(0, counts.sort_count)
    assert.equal(2, counts.view_count)
    assert.equal(0, counts.refresh_count)
  end)

  it("distributes cells evenly across the bar width", function()
    local bar = build_bar(build_actions())
    local cells = find_cells(bar)
    local expected_w = math.floor(600 / 4)
    for _, cell in ipairs(cells) do
      assert.equal(expected_w, cell.dimen.w)
    end
  end)
end)
