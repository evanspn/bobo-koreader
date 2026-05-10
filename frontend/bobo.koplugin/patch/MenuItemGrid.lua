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

-- Vertical room reserved beneath the cover for the title + timestamp.
-- Tighter than KOReader's 44px default so the cover stays the visual focus
-- but the cover art is never obscured (overlaying the title on the cover
-- art was rejected — ate the bottom of every manga cover).
local TEXT_BAND_HEIGHT = 36

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

  -- The card uses the full cell minus a small inset. The cover takes the
  -- top portion; a tight text band beneath it carries the title and
  -- timestamp. Title-on-cover overlays were tried previously but obscured
  -- the bottom of the cover art on every manga (see the design doc).
  local card_width  = self.dimen.w - 2 * CARD_INSET
  local card_height = self.dimen.h - 2 * CARD_INSET
  local text_band_h = Screen:scaleBySize(TEXT_BAND_HEIGHT)
  local cover_height = card_height - text_band_h

  self.face = Font:getFace(self.font, self.font_size)

  local cover_widget = MenuItemCover.genCover(self, card_width, cover_height)

  -- Top-right unread badge. Built as an OverlapGroup with the cover so the
  -- badge floats over the cover's top-right corner.
  local cover_with_badge = cover_widget
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

    cover_with_badge = OverlapGroup:new {
      dimen = Geom:new { w = card_width, h = cover_height },
      cover_widget,
      badge_strip,
    }
  end

  -- Tight text band beneath the cover: bold black title (single line,
  -- ellipsized) and a smaller dark-grey timestamp. The whole band is
  -- background-less so it blends with the page; the cover's own black
  -- border above provides the visual top edge of the cell.
  local title_pad_x = Screen:scaleBySize(4)
  local text_max_width = card_width - 2 * title_pad_x

  local title_widget = TextWidget:new {
    text = self.text,
    face = self.face,
    max_width = text_max_width,
    padding = 0,
    bold = true,
    fgcolor = self.dim and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK,
  }

  local text_stack = VerticalGroup:new {
    align = "left",
    title_widget,
  }

  local mandatory = self.mandatory_func and self.mandatory_func() or self.mandatory
  if mandatory and mandatory ~= "" then
    table.insert(text_stack, VerticalSpan:new { width = Screen:scaleBySize(1) })
    table.insert(text_stack, TextWidget:new {
      text = mandatory,
      face = Font:getFace(self.infont, math.max(self.infont_size - 2, 11)),
      max_width = text_max_width,
      padding = 0,
      bold = false,
      fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    })
  end

  local text_band = FrameContainer:new {
    bordersize = 0,
    margin = 0,
    width = card_width,
    height = text_band_h,
    padding_left = title_pad_x,
    padding_right = title_pad_x,
    padding_top = Screen:scaleBySize(3),
    padding_bottom = 0,
    text_stack,
  }

  local card = VerticalGroup:new {
    align = "left",
    cover_with_badge,
    text_band,
  }

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
