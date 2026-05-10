local GestureRange = require("ui/gesturerange")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local MenuItemRaw = require("MenuItem")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Blitbuffer = require("ffi/blitbuffer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Geom = require("ui/geometry")

local MenuItemCover = require("patch/MenuItemCover")

local Screen = Device.screen

-- Reuses the deep-red entry from Avatar.lua's palette so the unread badge
-- shares a single accent identity across the app. Picked for Kaleido 3:
-- saturated enough to read against a warm-light page, dark enough that the
-- white badge text stays legible.
local ACCENT_UNREAD = Blitbuffer.ColorRGB24(0xC0, 0x39, 0x2B)

-- Outer card padding inside the cell. Matches the existing _underline_container
-- inset so cells line up flush across the grid.
local CARD_INSET = 3

local MenuItemGrid = MenuItemRaw:extend {}

function MenuItemGrid:init()
  self.content_width = self.dimen.w - 2 * Size.padding.fullscreen
  self.content_height = self.dimen.h - 2 * Size.padding.fullscreen

  self.ges_events = {
    TapSelect = {
      GestureRange:new {
        ges = "tap",
        range = self.dimen,
      },
    },
    HoldSelect = {
      GestureRange:new {
        ges = self.handle_hold_on_hold_release and "hold_release" or "hold",
        range = self.dimen,
      },
    },
  }

  -- The card now uses the full cell (minus a small inset). Title and
  -- timestamp overlay on a black strip at the bottom of the cover instead
  -- of taking their own row underneath, so the cover itself is bigger and
  -- each cell reads as one unified card.
  local card_width  = self.dimen.w - 2 * CARD_INSET
  local card_height = self.dimen.h - 2 * CARD_INSET

  self.face = Font:getFace(self.font, self.font_size)

  local cover_widget = MenuItemCover.genCover(self, card_width, card_height)

  local overlay_children = { cover_widget }

  -- Top-right unread badge.
  local manga = self.entry and self.entry.manga
  local unread = manga and manga.unread_chapters_count
  if unread and unread > 0 then
    local badge_text = unread > 99 and "99+" or tostring(unread)
    local badge_pad_x = Screen:scaleBySize(5)
    local badge_pad_y = Screen:scaleBySize(2)
    local badge_inset = Screen:scaleBySize(4)

    local badge = FrameContainer:new {
      background = ACCENT_UNREAD,
      bordersize = 0,
      margin = 0,
      padding_left = badge_pad_x,
      padding_right = badge_pad_x,
      padding_top = badge_pad_y,
      padding_bottom = badge_pad_y,
      radius = Screen:scaleBySize(3),
      TextWidget:new {
        text = badge_text,
        face = Font:getFace(self.infont, math.max(self.infont_size - 2, 12)),
        bold = true,
        fgcolor = Blitbuffer.COLOR_WHITE,
      },
    }

    local badge_h = badge:getSize().h
    local badge_strip = FrameContainer:new {
      bordersize = 0,
      margin = 0,
      padding = 0,
      padding_top = badge_inset,
      padding_right = badge_inset,
      RightContainer:new {
        dimen = Geom:new { w = card_width - badge_inset, h = badge_h },
        badge,
      },
    }
    table.insert(overlay_children, badge_strip)
  end

  -- Bottom title + timestamp strip. Overlays the cover so the cover stays
  -- the visual focus while metadata stays accessible. White text on a solid
  -- black strip reads cleanly on Kaleido 3.
  local title_pad_x = Screen:scaleBySize(6)
  local title_pad_y = Screen:scaleBySize(4)
  local strip_text_max_width = card_width - 2 * title_pad_x

  local title_widget = TextWidget:new {
    text = self.text,
    face = self.face,
    max_width = strip_text_max_width,
    padding = 0,
    bold = true,
    fgcolor = Blitbuffer.COLOR_WHITE,
  }

  local strip_inner = VerticalGroup:new {
    align = "left",
    title_widget,
  }

  local mandatory = self.mandatory_func and self.mandatory_func() or self.mandatory
  if mandatory and mandatory ~= "" then
    table.insert(strip_inner, VerticalSpan:new { width = Screen:scaleBySize(2) })
    table.insert(strip_inner, TextWidget:new {
      text = mandatory,
      face = Font:getFace(self.infont, self.infont_size),
      max_width = strip_text_max_width,
      padding = 0,
      bold = false,
      fgcolor = Blitbuffer.COLOR_WHITE,
    })
  end

  local title_strip = FrameContainer:new {
    background = Blitbuffer.COLOR_BLACK,
    bordersize = 0,
    margin = 0,
    width = card_width,
    padding_left = title_pad_x,
    padding_right = title_pad_x,
    padding_top = title_pad_y,
    padding_bottom = title_pad_y,
    strip_inner,
  }

  table.insert(overlay_children, BottomContainer:new {
    dimen = Geom:new { w = card_width, h = card_height },
    title_strip,
  })

  local card_opts = { dimen = Geom:new { w = card_width, h = card_height } }
  for _, child in ipairs(overlay_children) do
    table.insert(card_opts, child)
  end
  local card = OverlapGroup:new(card_opts)

  self._underline_container = FrameContainer:new {
    padding = 0,
    bordersize = 0,
    HorizontalGroup:new {
      HorizontalSpan:new { width = CARD_INSET },
      VerticalGroup:new {
        VerticalSpan:new { width = CARD_INSET },
        card,
        VerticalSpan:new { width = CARD_INSET },
      },
      HorizontalSpan:new { width = CARD_INSET },
    }
  }

  self[1] = FrameContainer:new {
    width = self.dimen.w,
    height = self.dimen.h,
    padding = 0,
    margin = 0,
    color = Blitbuffer.TRANSPARENT,
    bordersize = 0,
    self._underline_container,
  }
end

return MenuItemGrid
