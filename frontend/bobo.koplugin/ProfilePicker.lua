-- Full-screen "who's reading?" launch picker. Shown by main.lua before the
-- library opens when 2+ profiles exist. Each profile is a tappable column:
-- circular Avatar above, name below. A "Manage profiles" link at the bottom
-- opens ProfileManager.

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = require("device").screen
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext+")

local Avatar = require("Avatar")

local AVATAR_SIZE_DP = 132
local CELL_GAP_DP = 36
local LABEL_GAP_DP = 10
local TITLE_GAP_DP = 28

--- A single profile cell (avatar + name). Layout-only; tap handling lives on
--- the parent picker so we can dispatch by hit-test once the layout has been
--- painted and absolute coords are known.
--- @class ProfilePickerCell : WidgetContainer
local ProfilePickerCell = WidgetContainer:extend {}

function ProfilePickerCell:init()
  local label_width = Screen:scaleBySize(AVATAR_SIZE_DP + 28)
  self[1] = VerticalGroup:new {
    align = "center",
    Avatar:new {
      size = Screen:scaleBySize(AVATAR_SIZE_DP),
      name = self.profile.name,
      color = self.profile.color,
    },
    VerticalSpan:new { width = Screen:scaleBySize(LABEL_GAP_DP) },
    TextWidget:new {
      text = self.profile.name,
      face = Font:getFace("infofont"),
      max_width = label_width,
    },
  }
end

--- @class ProfilePicker : InputContainer
--- @field profiles UserProfile[]
--- @field on_select fun(profile: UserProfile)|nil tap on a profile cell
--- @field on_manage fun()|nil tap on the "Manage profiles" link
local ProfilePicker = InputContainer:extend {
  profiles = nil,
  on_select = nil,
  on_manage = nil,
  cells = nil,
}

function ProfilePicker:init()
  assert(self.profiles and #self.profiles > 0, "ProfilePicker requires at least one profile")
  self.dimen = Geom:new {
    x = 0,
    y = 0,
    w = Screen:getWidth(),
    h = Screen:getHeight(),
  }

  -- Build the row of cells. We track the underlying ProfilePickerCell widgets
  -- so onTap can hit-test against them post-paint.
  self.cells = {}
  local row = HorizontalGroup:new { align = "top" }
  for i, profile in ipairs(self.profiles) do
    local cell = ProfilePickerCell:new { profile = profile }
    self.cells[i] = cell
    table.insert(row, cell)
    if i < #self.profiles then
      table.insert(row, HorizontalSpan:new { width = Screen:scaleBySize(CELL_GAP_DP) })
    end
  end

  local title = TextWidget:new {
    text = _("Who's reading?"),
    face = Font:getFace("tfont", 28),
  }

  local manage_btn = Button:new {
    text = _("Manage profiles"),
    face = Font:getFace("smallffont"),
    bordersize = 0,
    padding = Size.padding.button,
    callback = function()
      if self.on_manage then self.on_manage() end
    end,
  }

  local body = VerticalGroup:new {
    align = "center",
    title,
    VerticalSpan:new { width = Screen:scaleBySize(TITLE_GAP_DP) },
    row,
    VerticalSpan:new { width = Screen:scaleBySize(40) },
    manage_btn,
  }

  self[1] = FrameContainer:new {
    bordersize = 0,
    padding = 0,
    background = Blitbuffer.COLOR_WHITE,
    dimen = self.dimen:copy(),
    CenterContainer:new {
      dimen = self.dimen:copy(),
      body,
    },
  }

  if Device:isTouchDevice() then
    self.ges_events.Tap = {
      GestureRange:new { ges = "tap", range = self.dimen },
    }
  end
end

function ProfilePicker:onTap(_arg, ges)
  for _i, cell in ipairs(self.cells) do
    -- After the first paint, cell.dimen carries absolute screen coords from
    -- the HorizontalGroup parent. Until then it's nil and we early-out.
    if cell.dimen and cell.dimen:contains(ges.pos) then
      if self.on_select then self.on_select(cell.profile) end
      return true
    end
  end
  -- Don't swallow taps that hit nothing — let the manage button (a Button
  -- widget with its own gesture handling) get them.
  return false
end

--- Convenience constructor + show. Returns the widget so callers can close it
--- explicitly via UIManager:close.
--- @param opts { profiles: UserProfile[], on_select: fun(p: UserProfile), on_manage: fun()|nil }
--- @return ProfilePicker
function ProfilePicker.show(opts)
  local picker = ProfilePicker:new {
    profiles = opts.profiles,
    on_select = opts.on_select,
    on_manage = opts.on_manage,
  }
  UIManager:show(picker)
  return picker
end

return ProfilePicker
