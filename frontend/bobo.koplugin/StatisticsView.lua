-- StatisticsView — per-profile reading stats opened from the
-- Library "More" menu.
--
-- The active profile is implicit: the backend pool is already pointing
-- at the active profile's database, so /library/stats only ever sees
-- that profile's reads. The current profile name is shown in the title
-- bar so the user can tell whose stats they're looking at.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext+")

local Backend = require("Backend")
local ErrorDialog = require("ErrorDialog")
local LoadingDialog = require("LoadingDialog")
local format = require("utils/formatLibraryStats")

local Screen = Device.screen

local CHART_HEIGHT_FRAC = 0.18      -- fraction of screen height for the bar chart
local BAR_GAP = 4                    -- scaled pixels between bars
local TILE_GAP = 8                   -- scaled pixels between headline tiles

--- @class StatisticsView : FocusManager
--- @field stats LibraryStats
--- @field profile_name string|nil
--- @field on_return_callback fun()|nil
local StatisticsView = FocusManager:extend {
  stats = nil,
  profile_name = nil,
  on_return_callback = nil,
}

function StatisticsView:init()
  self.dimen = Geom:new {
    x = 0,
    y = 0,
    w = Screen:getWidth(),
    h = Screen:getHeight(),
  }
  self.covers_fullscreen = true

  if Device:hasKeys() then
    self.key_events.Close = { { Device.input.group.Back } }
  end
  if Device:isTouchDevice() then
    self.ges_events.Swipe = {
      GestureRange:new {
        ges = "swipe",
        range = function() return self.dimen end,
      }
    }
  end

  local border_size = Size.border.window
  local padding = Size.padding.large
  local inner_w = self.dimen.w - 2 * border_size
  local item_width = inner_w - 2 * padding
  local content_width = item_width - ScrollableContainer:getScrollbarWidth()

  local title = _("Statistics")
  if self.profile_name and self.profile_name ~= "" then
    title = title .. " — " .. self.profile_name
  end

  self.title_bar = TitleBar:new {
    title = title,
    fullscreen = true,
    width = self.dimen.w,
    with_bottom_line = true,
    bottom_line_color = Blitbuffer.COLOR_DARK_GRAY,
    bottom_line_h_padding = padding,
    left_icon = "chevron.left",
    left_icon_tap_callback = function() self:onClose() end,
    close_callback = function() self:onClose() end,
  }

  local body = VerticalGroup:new { align = "left" }
  table.insert(body, VerticalSpan:new { width = Size.span.vertical_large })
  table.insert(body, self:_buildHeadline(content_width))
  table.insert(body, VerticalSpan:new { width = Size.span.vertical_large })
  table.insert(body, self:_buildChart(content_width))
  table.insert(body, VerticalSpan:new { width = Size.span.vertical_large })
  table.insert(body, self:_buildGenres(content_width))
  table.insert(body, VerticalSpan:new { width = Size.span.vertical_large })
  table.insert(body, self:_buildTopManga(content_width))
  table.insert(body, VerticalSpan:new { width = Size.span.vertical_large })

  local title_bar_h = self.title_bar:getSize().h
  local scrollable = ScrollableContainer:new {
    dimen = Geom:new {
      w = item_width,
      h = self.dimen.h - title_bar_h - border_size * 2,
    },
    body,
  }

  local content = OverlapGroup:new {
    allow_mirroring = false,
    dimen = Geom:new { w = inner_w, h = self.dimen.h - 2 * border_size },
    VerticalGroup:new {
      align = "left",
      self.title_bar,
      HorizontalGroup:new {
        HorizontalSpan:new { width = padding },
        scrollable,
      },
    },
  }

  self[1] = FrameContainer:new {
    show_parent = self,
    width = self.dimen.w,
    height = self.dimen.h,
    padding = 0,
    margin = 0,
    bordersize = border_size,
    focusable = true,
    background = Blitbuffer.COLOR_WHITE,
    content,
  }

  scrollable.show_parent = self
  UIManager:setDirty(self, "ui")
end

--- @private
function StatisticsView:_section(width, title)
  local label = TextWidget:new {
    text = title,
    face = Font:getFace("cfont"),
    bold = true,
    fgcolor = Blitbuffer.COLOR_GRAY_5,
    max_width = width,
  }
  return VerticalGroup:new {
    align = "left",
    label,
    VerticalSpan:new { width = Size.span.vertical_default },
  }
end

--- @private
--- Four side-by-side tiles: chapters, mangas, current streak, longest streak.
function StatisticsView:_buildHeadline(width)
  local tiles = format.headlineTiles(self.stats)
  local tile_gap = Screen:scaleBySize(TILE_GAP)
  local tile_width = math.floor((width - tile_gap * (#tiles - 1)) / #tiles)
  local row = HorizontalGroup:new { align = "center" }

  for i, tile in ipairs(tiles) do
    if i > 1 then
      table.insert(row, HorizontalSpan:new { width = tile_gap })
    end

    local value = TextWidget:new {
      text = tile.value,
      face = Font:getFace("largeffont"),
      max_width = tile_width,
    }
    local label = TextWidget:new {
      text = tile.label,
      face = Font:getFace("smallffont"),
      fgcolor = Blitbuffer.COLOR_GRAY_5,
      max_width = tile_width,
    }
    local stack = VerticalGroup:new {
      align = "center",
      CenterContainer:new {
        dimen = Geom:new { w = tile_width, h = value:getSize().h },
        value,
      },
      VerticalSpan:new { width = Screen:scaleBySize(2) },
      CenterContainer:new {
        dimen = Geom:new { w = tile_width, h = label:getSize().h },
        label,
      },
    }
    local stack_h = stack:getSize().h
    local box_padding = Screen:scaleBySize(8)
    table.insert(row, FrameContainer:new {
      bordersize = Size.border.thin,
      padding = box_padding,
      margin = 0,
      background = Blitbuffer.COLOR_WHITE,
      color = Blitbuffer.COLOR_LIGHT_GRAY,
      CenterContainer:new {
        dimen = Geom:new { w = tile_width - 2 * box_padding, h = stack_h },
        stack,
      },
    })
  end

  return row
end

--- @private
--- 12-week chapters-read bar chart.
function StatisticsView:_buildChart(width)
  local section = self:_section(width, _("Chapters per week"))
  local weeks = self.stats.weeks or {}

  if #weeks == 0 then
    table.insert(section, TextWidget:new {
      text = _("No reads yet."),
      face = Font:getFace("smallffont"),
      fgcolor = Blitbuffer.COLOR_GRAY_5,
      max_width = width,
    })
    return section
  end

  local chart_height = math.floor(Screen:getHeight() * CHART_HEIGHT_FRAC)
  local gap = Screen:scaleBySize(BAR_GAP)
  local total_gap = gap * (#weeks - 1)
  local bar_width = math.max(Screen:scaleBySize(8), math.floor((width - total_gap) / #weeks))
  local heights = format.barHeights(weeks, 1.0, 0.02)

  local row = HorizontalGroup:new { align = "bottom" }
  for i, week in ipairs(weeks) do
    if i > 1 then
      table.insert(row, HorizontalSpan:new { width = gap })
    end
    local bar_h = math.max(1, math.floor(chart_height * heights[i]))
    local empty_h = chart_height - bar_h
    local is_last = (i == #weeks)
    -- The last bar (current week) gets a darker fill so the user can
    -- read "we're tracking right now" at a glance.
    local fill = is_last and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY_5
    local column = VerticalGroup:new {
      align = "left",
      VerticalSpan:new { width = empty_h },
      FrameContainer:new {
        width = bar_width,
        height = bar_h,
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = fill,
        HorizontalSpan:new { width = bar_width },
      },
    }
    table.insert(row, column)
  end

  table.insert(section, row)

  -- Axis: show oldest and most-recent week starts.
  table.insert(section, VerticalSpan:new { width = Screen:scaleBySize(4) })
  local axis = HorizontalGroup:new {
    align = "center",
    TextWidget:new {
      text = format.formatWeekLabel(weeks[1].start),
      face = Font:getFace("smallffont"),
      fgcolor = Blitbuffer.COLOR_GRAY_5,
      max_width = width,
    },
    HorizontalSpan:new { width = math.max(0, width - Screen:scaleBySize(120)) },
    TextWidget:new {
      text = format.formatWeekLabel(weeks[#weeks].start),
      face = Font:getFace("smallffont"),
      fgcolor = Blitbuffer.COLOR_GRAY_5,
      max_width = width,
    },
  }
  table.insert(section, axis)

  return section
end

--- @private
function StatisticsView:_buildGenres(width)
  local section = self:_section(width, _("Top genres"))
  local genres = self.stats.top_genres or {}
  if #genres == 0 then
    table.insert(section, TextWidget:new {
      text = _("No genre data yet."),
      face = Font:getFace("smallffont"),
      fgcolor = Blitbuffer.COLOR_GRAY_5,
      max_width = width,
    })
    return section
  end

  local max_count = 0
  for _i, g in ipairs(genres) do
    if g.manga_count > max_count then max_count = g.manga_count end
  end

  local row_height = Screen:scaleBySize(28)
  local label_w = math.floor(width * 0.45)
  local count_w = math.floor(width * 0.10)
  local bar_track_w = width - label_w - count_w - Screen:scaleBySize(16)

  for _i, g in ipairs(genres) do
    local fill = (max_count > 0) and (g.manga_count / max_count) or 0
    local fill_w = math.max(Screen:scaleBySize(4), math.floor(bar_track_w * fill))

    local name_widget = TextWidget:new {
      text = g.name,
      face = Font:getFace("cfont"),
      max_width = label_w,
    }
    local count_widget = TextWidget:new {
      text = tostring(g.manga_count),
      face = Font:getFace("smallffont"),
      fgcolor = Blitbuffer.COLOR_GRAY_5,
      max_width = count_w,
    }
    local bar = FrameContainer:new {
      width = fill_w,
      height = Screen:scaleBySize(10),
      bordersize = 0,
      padding = 0,
      margin = 0,
      background = Blitbuffer.COLOR_GRAY_5,
      HorizontalSpan:new { width = fill_w },
    }
    local row = HorizontalGroup:new {
      align = "center",
      name_widget,
      HorizontalSpan:new { width = math.max(0, label_w - name_widget:getSize().w + Screen:scaleBySize(8)) },
      bar,
      HorizontalSpan:new { width = math.max(0, bar_track_w - fill_w + Screen:scaleBySize(8)) },
      count_widget,
    }
    table.insert(section, CenterContainer:new {
      dimen = Geom:new { w = width, h = row_height },
      row,
    })
  end

  return section
end

--- @private
function StatisticsView:_buildTopManga(width)
  local section = self:_section(width, _("Top manga"))
  local rows = self.stats.top_manga or {}
  if #rows == 0 then
    table.insert(section, TextWidget:new {
      text = _("No manga read yet."),
      face = Font:getFace("smallffont"),
      fgcolor = Blitbuffer.COLOR_GRAY_5,
      max_width = width,
    })return section
  end

  for i, manga in ipairs(rows) do
    local title = string.format("%d. %s", i, manga.title or "")
    local sub = string.format("%d %s · %s",
      manga.chapters_read or 0,
      (manga.chapters_read == 1) and _("chapter") or _("chapters"),
      format.formatLastRead(manga.last_read))

    table.insert(section, TextBoxWidget:new {
      text = title,
      face = Font:getFace("cfont"),
      width = width,
    })
    table.insert(section, TextBoxWidget:new {
      text = sub,
      face = Font:getFace("smallffont"),
      fgcolor = Blitbuffer.COLOR_GRAY_5,
      width = width,
    })
    table.insert(section, VerticalSpan:new { width = Screen:scaleBySize(6) })
  end

  return section
end

function StatisticsView:onClose()
  UIManager:close(self)
  if self.on_return_callback then
    self.on_return_callback()
  end
end

function StatisticsView:onSwipe(_, ges)
  if ges.direction == "south" or ges.direction == "east" then
    self:onClose()
    return true
  end
end

--- Fetch stats from the backend and open the view. The view shows a
--- loading dialog while the request is in flight so the user gets
--- immediate feedback even on slow Kobos.
---
--- @param profile_name string|nil       Name of the active profile (just for the title).
--- @param on_return_callback fun()|nil
function StatisticsView:fetchAndShow(profile_name, on_return_callback)
  local response = LoadingDialog:showAndRun(
    _("Loading stats…"),
    function() return Backend.getLibraryStats() end
  )

  if response.type == "ERROR" then
    ErrorDialog:show(response.message)
    return
  end

  local ok, result = pcall(function()
    return StatisticsView:new {
      stats = response.body,
      profile_name = profile_name,
      on_return_callback = on_return_callback,
    }
  end)

  if not ok then
    ErrorDialog:show(_("Statistics failed to open") .. ": " .. tostring(result))
    return
  end

  UIManager:show(result)
end

return StatisticsView
