-- A persistent bottom action bar: a row of icon-with-label cells evenly
-- spaced across a fixed width. Designed for the Library screen so common
-- actions (search, sort, view-mode toggle, refresh) stay one tap away
-- without opening a modal menu — modal flows are slow on e-ink and the
-- Libra Colour has hardware page-turn buttons, so on-screen pagination
-- chevrons aren't pulling their weight either. The chevron row is
-- replaced by this bar plus a small page-of-page label below.
--
-- Each cell renders a Font Awesome glyph (large) over a label (small)
-- and is tappable across its whole area, not just the glyph. Glyphs
-- come from Icons.lua so we don't depend on the koreader icon-SVG set
-- being present.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen

local GLYPH_FONT_SIZE = 22
local LABEL_FONT_SIZE = 12

--- @class ActionBarAction
--- @field glyph string  Font-Awesome codepoint (from Icons.lua)
--- @field label string  Short human label rendered under the glyph
--- @field callback function

--- @class ActionBar : InputContainer
--- @field width number       Total bar width in scaled px
--- @field actions ActionBarAction[]
local ActionBar = InputContainer:extend {
  width = nil,
  actions = nil,
}

function ActionBar:init()
  self.width = self.width or Screen:getWidth()

  local cell_padding = Screen:scaleBySize(6)
  local cell_width = math.floor(self.width / #self.actions)

  local cells = {}
  local max_cell_height = 0
  for _, action in ipairs(self.actions) do
    local cell = self:_buildCell(action, cell_width, cell_padding)
    table.insert(cells, cell)
    if cell.dimen.h > max_cell_height then max_cell_height = cell.dimen.h end
  end
  -- Equal heights so the row aligns cleanly.
  for _, cell in ipairs(cells) do cell.dimen.h = max_cell_height end

  local row = HorizontalGroup:new { align = "center" }
  for _, cell in ipairs(cells) do table.insert(row, cell) end

  self[1] = FrameContainer:new {
    width = self.width,
    bordersize = 0,
    padding = 0,
    margin = 0,
    background = Blitbuffer.COLOR_WHITE,
    row,
  }
end

--- @private
function ActionBar:_buildCell(action, cell_width, padding)
  local glyph = TextWidget:new {
    text = action.glyph,
    face = Font:getFace("smallinfofont", GLYPH_FONT_SIZE),
    fgcolor = Blitbuffer.COLOR_BLACK,
    padding = 0,
  }

  local label = TextWidget:new {
    text = action.label,
    face = Font:getFace("cfont", LABEL_FONT_SIZE),
    fgcolor = Blitbuffer.COLOR_BLACK,
    padding = 0,
  }

  local stack = VerticalGroup:new {
    align = "center",
    glyph,
    VerticalSpan:new { width = Screen:scaleBySize(2) },
    label,
  }

  local cell_height = stack:getSize().h + 2 * padding

  local cell = InputContainer:new {
    dimen = Geom:new { x = 0, y = 0, w = cell_width, h = cell_height },
    CenterContainer:new {
      dimen = Geom:new { w = cell_width, h = cell_height },
      stack,
    },
  }
  cell.ges_events = {
    Tap = {
      GestureRange:new {
        ges = "tap",
        range = function() return cell.dimen end,
      },
    },
  }
  -- WidgetContainer:paintTo doesn't update self.dimen.x/y for InputContainer
  -- subclasses laid out by HorizontalGroup, so the lazy GestureRange above
  -- would otherwise stay anchored at (0, 0) — taps would either miss or
  -- fall through to the manga rows above. Track the actual paint
  -- coordinates here so the range covers the cell's real screen rect.
  cell.paintTo = function(self_, bb, x, y)
    self_.dimen.x = x
    self_.dimen.y = y
    self_[1]:paintTo(bb, x, y)
  end
  cell.onTap = function()
    action.callback()
    -- Force a repaint so the user sees the action take effect on slow
    -- e-ink updates (the modal flows used to give that feedback for free).
    UIManager:setDirty(self.show_parent or self, "ui")
    return true
  end

  return cell
end

--- Allow the bar to participate in vertical layout calculations the same
--- way KOReader's stock page_info row does.
function ActionBar:getSize()
  return self[1]:getSize()
end

return ActionBar
