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

  local text_height = Screen:scaleBySize(44)
  local img_width = self.dimen.w - 6
  local img_height = self.dimen.h - text_height - 12 - 6 -- padding y = 3

  -- Main text (Title)
  self.face = Font:getFace(self.font, self.font_size)

  -- Constrain to the same horizontal slot as the cover so the title doesn't
  -- bleed past the cell edge. TextWidget truncates with ellipsis at max_width.
  local title_widget = TextWidget:new {
    text = self.text,
    face = self.face,
    max_width = img_width,
    padding = 0,
    bold = true,
    fgcolor = self.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
  }

  -- Mandatory line (timestamp / source). The unread count moved to a corner
  -- badge over the cover so it's not duplicated here.
  local mandatory = self.mandatory_func and self.mandatory_func() or self.mandatory
  local mandatory_widget
  if mandatory and mandatory ~= "" then
    mandatory_widget = TextWidget:new {
      text = mandatory,
      face = Font:getFace(self.infont, self.infont_size),
      bold = false,
      fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }
  end

  local cover_widget = MenuItemCover.genCover(self, img_width, img_height)

  -- If the entry has unread chapters, overlay a small accent-filled badge in
  -- the cover's top-right corner.
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

    -- Right-align the badge in a strip the height of the badge plus the
    -- desired top inset, so the badge floats in the cover's top-right.
    local badge_h = badge:getSize().h
    local badge_strip = FrameContainer:new {
      bordersize = 0,
      margin = 0,
      padding = 0,
      padding_top = badge_inset,
      padding_right = badge_inset,
      RightContainer:new {
        dimen = Geom:new { w = img_width - badge_inset, h = badge_h },
        badge,
      },
    }

    cover_widget = OverlapGroup:new {
      dimen = Geom:new { w = img_width, h = img_height },
      cover_widget,
      badge_strip,
    }
  end

  -- Cover and title share one centered VerticalGroup. A small VerticalSpan
  -- keeps the title from butting against the cover border.
  local main_content = FrameContainer:new {
    padding = 0,
    bordersize = 0,
    VerticalGroup:new {
      align = "center",
      cover_widget,
      VerticalSpan:new { width = Size.span.vertical_default },
      title_widget,
    }
  }

  local final_content
  if mandatory_widget then
    final_content = VerticalGroup:new {
      main_content,
      mandatory_widget
    }
  else
    final_content = main_content
  end

  self._underline_container = FrameContainer:new {
    padding = 0,
    bordersize = 0,
    HorizontalGroup:new {
      HorizontalSpan:new { width = 3 },
      VerticalGroup:new {
        VerticalSpan:new { width = 3 },
        final_content,
        VerticalSpan:new { width = 3 },
      },
      HorizontalSpan:new { width = 3 },
    }
  }

  self[1] = FrameContainer:new {
    width = self.dimen.w,
    height = self.dimen.h,
    padding = 0,
    margin = 0, -- remove margin to ensure full 1/3 width
    color = Blitbuffer.TRANSPARENT,
    bordersize = 0,
    self._underline_container,
  }
end

return MenuItemGrid
