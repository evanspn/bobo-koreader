-- A horizontal tab strip rendered above the manga grid. Each tab represents
-- the default Library view or one of the user's playlists; tapping a tab
-- switches `current_playlist` and reloads.
--
-- Visual model: bold-underlined label for the selected tab, plain label
-- otherwise. Tabs are evenly distributed across the bar width, just like
-- ActionBar cells, so the row stays aligned across rotations. Like
-- ActionBarCell, each cell overrides paintTo so its lazy GestureRange
-- picks up the absolute paint coordinates (WidgetContainer:paintTo does
-- not update self.dimen.x/y for InputContainer subclasses laid out by
-- HorizontalGroup).

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen

local LABEL_FONT_SIZE = 14

--- @class LibraryTab
--- @field label string         Display name (e.g. "Library", playlist name)
--- @field id string|nil        Playlist id, or nil for the default Library tab
--- @field selected boolean     Currently-active tab

--- @class LibraryTabs : InputContainer
--- @field width number
--- @field tabs LibraryTab[]
--- @field on_select fun(tab: LibraryTab)
local LibraryTabs = InputContainer:extend {
  width = nil,
  tabs = nil,
  on_select = nil,
}

function LibraryTabs:init()
  self.width = self.width or Screen:getWidth()

  local cell_padding = Screen:scaleBySize(6)
  local cell_width = math.floor(self.width / math.max(#self.tabs, 1))

  local row = HorizontalGroup:new { align = "center" }
  for _, tab in ipairs(self.tabs) do
    table.insert(row, self:_buildCell(tab, cell_width, cell_padding))
  end

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
function LibraryTabs:_buildCell(tab, cell_width, padding)
  local label = TextWidget:new {
    text = tab.label,
    face = Font:getFace("cfont", LABEL_FONT_SIZE),
    bold = tab.selected,
    fgcolor = Blitbuffer.COLOR_BLACK,
    padding = 0,
    max_width = cell_width - 2 * padding,
  }

  -- Selected tab gets a 2px underline; non-selected gets a 1px subtle
  -- divider in COLOR_GRAY_9 so the row reads as a tab strip rather than
  -- a row of disconnected labels.
  local underline = LineWidget:new {
    dimen = Geom:new {
      w = cell_width - 2 * padding,
      h = tab.selected and Screen:scaleBySize(2) or Screen:scaleBySize(1),
    },
    background = tab.selected and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY_9,
  }

  local stack = VerticalGroup:new {
    align = "center",
    label,
    VerticalSpan:new { width = Screen:scaleBySize(3) },
    underline,
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
  cell.paintTo = function(self_, bb, x, y)
    self_.dimen.x = x
    self_.dimen.y = y
    self_[1]:paintTo(bb, x, y)
  end
  cell.onTap = function()
    if self.on_select then self.on_select(tab) end
    UIManager:setDirty(self.show_parent or self, "ui")
    return true
  end

  return cell
end

--- Match the page_info/ActionBar pattern so the menu's vertical layout
--- can size the tab strip without descending into private fields.
function LibraryTabs:getSize()
  return self[1]:getSize()
end

return LibraryTabs
