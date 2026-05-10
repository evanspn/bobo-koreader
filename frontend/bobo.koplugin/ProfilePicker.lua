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
local _ = require("gettext+")

local Avatar = require("Avatar")

local AVATAR_SIZE_DP = 132
local CELL_GAP_DP = 36
local LABEL_GAP_DP = 10
local TITLE_GAP_DP = 28

--- A single tappable profile cell (avatar + name). Each cell is its own
--- InputContainer, which is the only reliable way to give widgets laid out
--- by HorizontalGroup their own tap targets — relying on the parent
--- hit-testing against `cell.dimen` after paint doesn't work consistently
--- because WidgetContainer subclasses don't always update self.dimen with
--- absolute coords during the paint chain.
---
--- The trick that makes this work: the gesture range is a function
--- (`function() return self.dimen end`) so KOReader's gesture dispatcher
--- pulls the current dimen at tap time, after the cell has been painted at
--- its final absolute screen position.
--- @class ProfilePickerCell : InputContainer
local ProfilePickerCell = InputContainer:extend {
  profile = nil,
  on_tap = nil, -- fun(): nil
}

function ProfilePickerCell:init()
  local label_max_w = Screen:scaleBySize(AVATAR_SIZE_DP + 28)
  local body = VerticalGroup:new {
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
      max_width = label_max_w,
    },
  }
  self[1] = body

  -- Seed self.dimen with the cell's intrinsic size. paintTo updates the
  -- x/y to the cell's actual painted position so the lazy gesture range
  -- below covers the right rectangle.
  local size = body:getSize()
  self.dimen = Geom:new { x = 0, y = 0, w = size.w, h = size.h }

  if Device:isTouchDevice() then
    self.ges_events = {
      Tap = {
        GestureRange:new {
          ges = "tap",
          range = function() return self.dimen end,
        },
      },
    }
  end
end

function ProfilePickerCell:paintTo(bb, x, y)
  -- HorizontalGroup calls us with absolute screen coords. Track them on
  -- self.dimen so the lazy `range` function picks them up at tap time.
  self.dimen.x = x
  self.dimen.y = y
  self[1]:paintTo(bb, x, y)
end

function ProfilePickerCell:onTap()
  if self.on_tap then self.on_tap() end
  return true
end

--- @class ProfilePicker : InputContainer
--- @field profiles UserProfile[]
--- @field on_select fun(profile: UserProfile)|nil tap on a profile cell
--- @field on_manage fun()|nil tap on the "Manage profiles" link
local ProfilePicker = InputContainer:extend {
  profiles = nil,
  on_select = nil,
  on_manage = nil,
}

function ProfilePicker:init()
  assert(self.profiles and #self.profiles > 0, "ProfilePicker requires at least one profile")
  self.dimen = Geom:new {
    x = 0,
    y = 0,
    w = Screen:getWidth(),
    h = Screen:getHeight(),
  }
  self.covers_fullscreen = true

  local row = HorizontalGroup:new { align = "top" }
  for i, profile in ipairs(self.profiles) do
    local cell = ProfilePickerCell:new {
      profile = profile,
      on_tap = function()
        if self.on_select then self.on_select(profile) end
      end,
    }
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
end

--- Re-layout the picker for the current screen dimensions. KOReader fires
--- `onSetRotationMode` and `onScreenResize` on rotation; without these
--- handlers we'd remain at the dimensions captured by `init` and look
--- clipped or mis-aligned in the new orientation.
function ProfilePicker:_reshow()
  if self._reshow_in_progress then return end
  self._reshow_in_progress = true
  UIManager:close(self)
  if self._recreate then self._recreate() end
end

function ProfilePicker:onSetRotationMode(new_rotation)
  if new_rotation == nil or new_rotation == Screen:getRotationMode() then
    return false
  end
  Screen:setRotationMode(new_rotation)
  self:_reshow()
  return true
end

function ProfilePicker:onScreenResize(_dimen)
  self:_reshow()
  return false
end

--- Convenience constructor + show. Returns the widget so callers can close
--- it explicitly via `UIManager:close`.
--- @param opts { profiles: UserProfile[], on_select: fun(p: UserProfile), on_manage: fun()|nil }
--- @return ProfilePicker
function ProfilePicker.show(opts)
  local picker = ProfilePicker:new {
    profiles = opts.profiles,
    on_select = opts.on_select,
    on_manage = opts.on_manage,
    -- Stash a recreate closure so rotation/resize handlers can rebuild the
    -- widget with the same callbacks against the new screen dimensions.
    _recreate = function() return ProfilePicker.show(opts) end,
  }
  UIManager:show(picker)
  return picker
end

return ProfilePicker
