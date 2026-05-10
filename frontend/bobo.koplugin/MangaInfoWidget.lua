local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local InputText = require("ui/widget/inputtext")
local TextViewer = require("ui/widget/textviewer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local InfoMessage = require("ui/widget/infomessage")
local Trapper = require("ui/trapper")
local _ = require("gettext+")
local Screen = Device.screen
local T = require("ffi/util").template

local LoadingDialog = require("LoadingDialog")
local Backend = require("Backend")
local ErrorDialog = require("ErrorDialog")
local calcLastReadText = require("utils/calcLastReadText")
local formatStats = require("utils/formatStats")

local function parse_iso8601(str)
  local year, month, day, hour, min, sec =
      str:match("(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)Z")

  return os.time({
    year = year,
    month = month,
    day = day,
    hour = hour,
    min = min,
    sec = sec,
    isdst = false,
  })
end

--- @class FocusManager
--- @field key_events table<string, any>
--- @field ges_events table<string, any>
--- @field dimen boolean
--- @field close_callback fun() | nil
--- @field new fun(self: FocusManager): FocusManager

--- @class MangaInfoWidget : FocusManager
--- @field padding any
--- @field raw_manga Manga
--- @field manga MManga|nil
--- @field per_read number|nil
--- @field chapters_read integer|nil
--- @field total_chapters integer|nil
--- @field current_chapter_number number|nil
--- @field on_return_callback fun()|nil
local MangaInfoWidget = FocusManager:extend {
  padding = Size.padding.fullscreen,
  raw_manga = nil,
  manga = nil,
  per_read = nil,
  chapters_read = nil,
  total_chapters = nil,
  current_chapter_number = nil,
  on_return_callback = nil,
}

function MangaInfoWidget:init()
  self.updated = nil
  self.layout = {}

  self.small_font_face = Font:getFace("smallffont")
  self.medium_font_face = Font:getFace("ffont")
  self.large_font_face = Font:getFace("largeffont")

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
    self.ges_events.MultiSwipe = {
      GestureRange:new {
        ges = "multiswipe",
        range = function() return self.dimen end,
      }
    }
  end

  local screen_size = Screen:getSize()
  self.covers_fullscreen = true -- hint for UIManager:_repaint()
  self[1] = FrameContainer:new {
    width = screen_size.w,
    height = screen_size.h,
    background = Blitbuffer.COLOR_WHITE,
    bordersize = 0,
    padding = 0,
    self:getStatusContent(screen_size.w, self.manga),
  }

  self.dithered = true
end

--- @param manga MManga
function MangaInfoWidget:getStatusContent(width, manga)
  local title_bar = TitleBar:new {
    width = width,
    bottom_v_padding = 0,
    close_callback = function() self:onClose() end,
    left_icon = "appbar.menu",
    left_icon_tap_callback = function()
      local raw_manga = self.raw_manga
      local on_return_callback = self.on_return_callback

      local ChapterListing = require("ChapterListing")
      Trapper:wrap(function()
        local onReturnCallback = function()
          Trapper:wrap(function()
            self:fetchAndShow(raw_manga, on_return_callback)
          end)
        end
        if ChapterListing:fetchAndShow(raw_manga, onReturnCallback, true) then
          self:onClose(false)
        end
      end)
    end,
    show_parent = self,
  }
  local content = VerticalGroup:new {
    align = "left",
    title_bar,
    self:genBookInfoGroup(manga),
    self:genHeader(_("Statistics")),
    self:genStatisticsGroup(width, manga),
    self:genHeader(_("Description")),
    self:genSummaryGroup(width, manga),
    -- self:genHeader(_("Book")),
  }
  return content
end

function MangaInfoWidget:genHeader(title)
  local width, height = Screen:getWidth(), Size.item.height_default

  local header_title = TextWidget:new {
    text = title,
    face = self.medium_font_face,
    fgcolor = Blitbuffer.COLOR_GRAY_9,
    max_width = width - 4 * self.padding,
  }

  local padding_span = HorizontalSpan:new { width = self.padding }
  local line_width = (width - header_title:getSize().w) / 2 - self.padding * 2
  local line_container = LeftContainer:new {
    dimen = Geom:new { w = line_width, h = height },
    LineWidget:new {
      background = Blitbuffer.COLOR_LIGHT_GRAY,
      dimen = Geom:new {
        w = line_width,
        h = Size.line.thick,
      }
    }
  }
  local span_top, span_bottom
  if Screen:getScreenMode() == "landscape" then
    span_top = VerticalSpan:new { width = Size.span.horizontal_default }
    span_bottom = VerticalSpan:new { width = Size.span.horizontal_default }
  else
    span_top = VerticalSpan:new { width = Size.item.height_default }
    span_bottom = VerticalSpan:new { width = Size.span.vertical_large }
  end

  return VerticalGroup:new {
    span_top,
    HorizontalGroup:new {
      align = "center",
      padding_span,
      line_container,
      padding_span,
      header_title,
      padding_span,
      line_container,
      padding_span,
    },
    span_bottom,
  }
end

--- @param manga MManga
function MangaInfoWidget:genBookInfoGroup(manga)
  local screen_width = Screen:getWidth()
  local split_span_width = math.floor(screen_width * 0.05)

  local img_width, img_height
  if Screen:getScreenMode() == "landscape" then
    img_width = Screen:scaleBySize(132)
    img_height = Screen:scaleBySize(184)
  else
    img_width = Screen:scaleBySize(132 * 1.5)
    img_height = Screen:scaleBySize(184 * 1.5)
  end

  local height = img_height
  local width = screen_width - split_span_width - img_width

  -- Get a chance to have title and authors rendered with alternate
  -- title
  local book_meta_info_group = VerticalGroup:new {
    align = "center",
    VerticalSpan:new { width = height * 0.2 },
    TextBoxWidget:new {
      text = manga.title,
      -- lang = lang,
      width = width,
      face = self.medium_font_face,
      alignment = "center",
    },

  }
  -- author
  if manga.author ~= nil then
    local text_author = TextBoxWidget:new {
      text = manga.author,
      -- lang = lang,
      face = self.small_font_face,
      width = width,
      alignment = "center",
    }
    table.insert(book_meta_info_group,
      CenterContainer:new {
        dimen = Geom:new { w = width, h = text_author:getSize().h },
        text_author
      }
    )
  end
  -- artist
  if manga.artist ~= nil then
    local text_artist = TextBoxWidget:new {
      text = manga.artist,
      -- lang = lang,
      face = self.small_font_face,
      width = width,
      alignment = "center",
    }
    table.insert(book_meta_info_group,
      CenterContainer:new {
        dimen = Geom:new { w = width, h = text_artist:getSize().h },
        text_artist
      }
    )
  end
  -- progress bar
  local read_percentage = self.per_read or 0
  local progress_bar = ProgressWidget:new {
    width = math.floor(width * 0.7),
    height = Screen:scaleBySize(10),
    percentage = read_percentage,
    ticks = nil,
    last = nil,
  }
  table.insert(book_meta_info_group,
    CenterContainer:new {
      dimen = Geom:new { w = width, h = progress_bar:getSize().h },
      progress_bar
    }
  )
  -- progress summary: "37 % • 5 / 100 chapters"
  local chapters_summary = formatStats.formatChapters(self.chapters_read, self.total_chapters)
  local complete_text
  if chapters_summary == "—" then
    complete_text = T(_("%1 Completed"), formatStats.formatPercentage(read_percentage))
  else
    complete_text = T(_("%1 \xE2\x80\xA2 %2 chapters"),
      formatStats.formatPercentage(read_percentage), chapters_summary)
  end
  local text_complete = TextWidget:new {
    text = complete_text,
    face = self.small_font_face,
    max_width = width,
  }
  table.insert(book_meta_info_group,
    CenterContainer:new {
      dimen = Geom:new { w = width, h = text_complete:getSize().h },
      text_complete
    }
  )

  -- tags text
  if manga.tags ~= nil and #manga.tags > 0 then
    local tags_text = table.concat(manga.tags, ", ")
    local text_tags = TextBoxWidget:new {
      text = "\n" .. tags_text,
      -- lang = lang,
      face = self.small_font_face,
      width = width,
      alignment = "center",
    }
    table.insert(book_meta_info_group,
      CenterContainer:new {
        dimen = Geom:new { w = width, h = text_tags:getSize().h },
        text_tags
      }
    )
  end

  -- build the final group
  local book_info_group = HorizontalGroup:new {
    align = "top",
    HorizontalSpan:new { width = split_span_width }
  }
  -- thumbnail
  local thumbnail = manga.url
  -- local cc = ImageLoader:new {
  --   callback = function(content)
  --     thumbnail = RenderImage:fromData(content)
  --     UIManager:setDirty(nil, "ui", nil, true)
  --   end
  -- }
  -- cc.loadImage(manga.cover_url)

  if thumbnail and thumbnail:sub(1, #"file://") == "file://" then
    -- Render the cover inside a fixed-size bordered frame and let the
    -- ImageWidget preserve aspect ratio (`scale_factor = 0`). Without the
    -- frame, ImageWidget either stretches to width/height or shrinks to fit
    -- and the surrounding layout shifts depending on cover proportions.
    local cover_border = Size.border.thin
    local inner_w = img_width - 2 * cover_border
    local inner_h = img_height - 2 * cover_border
    table.insert(book_info_group, FrameContainer:new {
      width = img_width,
      height = img_height,
      margin = 0,
      padding = 0,
      bordersize = cover_border,
      color = Blitbuffer.COLOR_GRAY_9,
      CenterContainer:new {
        dimen = Geom:new { w = inner_w, h = inner_h },
        ImageWidget:new {
          file = thumbnail:gsub("^file://", ""),
          width = inner_w,
          height = inner_h,
          scale_factor = 0,
        },
      },
    })
  end

  table.insert(book_info_group, CenterContainer:new {
    dimen = Geom:new { w = width, h = height },
    book_meta_info_group,
  })

  return CenterContainer:new {
    dimen = Geom:new { w = screen_width, h = img_height },
    book_info_group,
  }
end

--- @param manga MManga
function MangaInfoWidget:genStatisticsGroup(width, manga)
  local last_read_str = manga.last_read
      and calcLastReadText(parse_iso8601(manga.last_read))
      or "—"
  local last_updated_str = manga.last_updated
      and calcLastReadText(parse_iso8601(manga.last_updated))
      or "—"

  local row_1 = {
    { title = _("Read"),     value = formatStats.formatChapters(self.chapters_read, self.total_chapters) },
    { title = _("Current"),  value = formatStats.formatCurrentChapter(self.current_chapter_number) },
    { title = _("Last read"), value = last_read_str },
  }
  local row_2 = {
    { title = _("Status"),   value = self:getStatus(manga) },
    { title = _("NSFW"),     value = self:getNSFW(manga) },
    { title = _("Updated"),  value = last_updated_str },
  }

  -- Two stacked rows of three stats each.
  local row_height = Screen:scaleBySize(60)
  local stats_height = row_height * 2
  local statistics_container = CenterContainer:new {
    dimen = Geom:new { w = width, h = stats_height },
  }

  local statistics_group = VerticalGroup:new { align = "left" }

  local tile_width = math.floor(width * (1 / 3))
  local title_tile_height = math.floor(row_height * (1 / 2))
  local data_tile_height = row_height - title_tile_height

  local function build_row(row)
    local titles_group = HorizontalGroup:new { align = "center" }
    local data_group = HorizontalGroup:new { align = "center" }
    for _i, stat in ipairs(row) do
      table.insert(titles_group, CenterContainer:new {
        dimen = Geom:new { w = tile_width, h = title_tile_height },
        TextWidget:new {
          text = stat.title,
          face = self.small_font_face,
          fgcolor = Blitbuffer.COLOR_GRAY_5,
          max_width = tile_width,
        },
      })
      table.insert(data_group, CenterContainer:new {
        dimen = Geom:new { w = tile_width, h = data_tile_height },
        TextWidget:new {
          text = stat.value,
          face = self.medium_font_face,
          max_width = tile_width,
        },
      })
    end
    table.insert(statistics_group, titles_group)
    table.insert(statistics_group, data_group)
  end

  build_row(row_1)
  table.insert(statistics_group, VerticalSpan:new { width = Size.span.vertical_default })
  build_row(row_2)

  table.insert(statistics_container, statistics_group)
  return statistics_container
end

--- @param manga MManga
function MangaInfoWidget:getStatus(manga)
  if manga.status == PublishingStatus.Ongoing then
    return _("Ongoing")
  elseif manga.status == PublishingStatus.Completed then
    return _("Completed")
  elseif manga.status == PublishingStatus.Cancelled then
    return _("Cancelled")
  elseif manga.status == PublishingStatus.Hiatus then
    return _("Hiatus")
  elseif manga.status == PublishingStatus.NotPublished then
    return _("Not published")
  end
  return _("Unknown")
end

--- @param manga MManga
function MangaInfoWidget:getNSFW(manga)
  if manga.nsfw == MangaContentRating.Safe then
    return _("Safe")
  elseif manga.nsfw == MangaContentRating.Suggestive then
    return _("Suggestive")
  elseif manga.nsfw == MangaContentRating.Nsfw then
    return _("NSFW")
  end

  return "N/A"
end

--- @param manga MManga
function MangaInfoWidget:genSummaryGroup(width, manga)
  local height
  if Screen:getScreenMode() == "landscape" then
    height = Screen:scaleBySize(80)
  else
    height = Screen:scaleBySize(160)
  end

  local text_padding = Size.padding.default
  self.input_note = ScrollTextWidget:new {
    text = manga.description or "N/A",
    face = self.medium_font_face,
    width = width - self.padding * 3,
    height = math.floor(height),
    dialog = TextViewer:new {
      title = _("Description"),
      text = manga.description
    },
    scroll = true,
    bordersize = Size.border.default,
    focused = false,
    padding = text_padding,
    parent = self,
  }
  table.insert(self.layout, { self.input_note })

  return VerticalGroup:new {
    VerticalSpan:new { width = Size.span.vertical_large },
    CenterContainer:new {
      dimen = Geom:new { w = width, h = height },
      self.input_note
    }
  }
end

function MangaInfoWidget:onSwipe(arg, ges_ev)
  if ges_ev.direction == "south" then
    -- Allow easier closing with swipe down
    self:onClose()
  elseif ges_ev.direction == "west" or ges_ev.direction == "north" then
    UIManager:show(TextViewer:new {
      title = _("Description"),
      text = self.manga.description
    })
  elseif ges_ev.direction == "east" or ges_ev.direction == "west" or ges_ev.direction == "north" then
    -- no use for now
    do end -- luacheck: ignore 541
  else     -- diagonal swipe
    -- trigger full refresh
    UIManager:setDirty(nil, "full", nil, true)
    -- a long diagonal swipe may also be used for taking a screenshot,
    -- so let it propagate
    return false
  end
end

function MangaInfoWidget:onMultiSwipe(arg, ges_ev)
  -- For consistency with other fullscreen widgets where swipe south can't be
  -- used to close and where we then allow any multiswipe to close, allow any
  -- multiswipe to close this widget too.
  self:onClose()
  return true
end

function MangaInfoWidget:onClose(run_return_callback)
  -- NOTE: Flash on close to avoid ghosting, since we show an image.
  UIManager:close(self, "flashpartial")
  if self.close_callback then
    self.close_callback()
  end
  if self.on_return_callback and run_return_callback ~= false then
    self.on_return_callback()
  end
  return true
end

--- @param source_id string
--- @param manga_id string
--- @return SuccessfulResponse<[MManga, number]>|ErrorResponse|nil
function MangaInfoWidget:refreshDetails(source_id, manga_id)
  local cancel_id_1 = Backend.createCancelId()
  local cancel_id_2 = Backend.createCancelId()

  local responses, cancelled = LoadingDialog:showAndRun(
    _("Refreshing details..."),
    function()
      local a1 = Backend.refreshMangaDetails(cancel_id_1, source_id, manga_id)
      local a2 = Backend.cachedMangaDetails(cancel_id_2, source_id, manga_id)

      return { a1, a2 }
    end,
    function()
      Backend.cancel(cancel_id_1)
      Backend.cancel(cancel_id_2)

      local cancelledMessage = InfoMessage:new {
        text = _("Refresh details cancelled."),
      }
      UIManager:show(cancelledMessage)
    end
  )

  if cancelled then
    return
  end

  if responses[1].type == 'ERROR' then
    ErrorDialog:show(responses[1].message)

    return
  end
  if responses[2].type == 'ERROR' then
    ErrorDialog:show(responses[2].message)

    return
  end

  return responses[2]
end

--- @param raw_manga Manga
--- @param on_return_callback fun()|nil
function MangaInfoWidget:fetchAndShow(raw_manga, on_return_callback)
  local response = self:refreshDetails(raw_manga.source.id, raw_manga.id)
  if response == nil then
    return
  end

  ---@diagnostic disable-next-line: redundant-parameter
  local widget = MangaInfoWidget:new {
    raw_manga = raw_manga,
    manga = response.body[1],
    per_read = response.body[2],
    chapters_read = response.body[3],
    total_chapters = response.body[4],
    current_chapter_number = response.body[5],
    on_return_callback = on_return_callback,
  }
  UIManager:show(widget)
end

return MangaInfoWidget
