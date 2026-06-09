local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local Trapper = require("ui/trapper")
local Screen = require("device").screen
local logger = require("logger")
local LoadingDialog = require("LoadingDialog")
---@diagnostic disable-next-line: different-requires
local util = require("util")
local _ = require("gettext+")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Button = require("ui/widget/button")
local ActionBar = require("widgets/ActionBar")
local md5 = require("ffi/sha2").md5
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local Backend = require("Backend")
local DownloadChapter = require("jobs/DownloadChapter")
local DownloadUnreadChapters = require("jobs/DownloadUnreadChapters")
local DownloadUnreadChaptersJobDialog = require("DownloadUnreadChaptersJobDialog")
local Icons = require("Icons")
local Menu = require("widgets/Menu")
local ErrorDialog = require("ErrorDialog")
local MangaReader = require("MangaReader")
local MangaInfoWidget = require("MangaInfoWidget")
local CheckboxDialog = require("CheckboxDialog")
local Testing = require("testing")
local calcLastReadText = require("utils/calcLastReadText")
local isBeforeChapter = require("utils/isBeforeChapter")
local filterChaptersByLang = require("utils/filterChaptersByLang")
local findLastRead = require("utils/findLastRead")
local getChapterDisplayName = require("utils/getChapterDisplayName")

local findNextChapter = require("chapters/findNextChapter")

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")
local Font = require("ui/font")
local SMALL_FONT_FACE = Font:getFace("smallffont")

--- @class ChapterListing : { [any]: any }
--- @field manga Manga
--- @field raw_chapters Chapter[]
--- @field chapters Chapter[]
--- @field langs BaseOption[]
--- @field chapter_sorting_mode ChapterSortingMode
local ChapterListing = Menu:extend {
  name = "chapter_listing",
  is_enable_shortcut = false,
  is_popout = false,
  title = _("Chapter listing"),
  align_baselines = true,

  -- the manga we're listing
  manga = nil,
  -- list of chapters
  raw_chapters = {},
  chapters = {},
  langs = {},
  langs_selected = {},
  chapter_sorting_mode = nil,
  -- callback to be called when pressing the back button
  on_return_callback = nil,
  -- scanlator filtering
  selected_scanlator = nil,
  available_scanlators = {},
  preload_count = 0,
  preload_on_progress = false,
}

function ChapterListing:init()
  self.width = Screen:getWidth()
  self.height = Screen:getHeight()

  -- FIXME `Menu` calls `updateItems()` during init, but we haven't fetched any items yet, as
  -- we do it in `updateChapterList`. Not sure if there's any downside to it, but here's a notice.
  local page = self.page
  Menu.init(self)
  self.page = page

  self.paths = { 0 }
  -- idk might make some gc shenanigans actually work
  self.on_return_callback = nil

  -- Strip the hamburger / close buttons from the title bar — those actions
  -- live on the bottom action bar now, matching LibraryView's pattern.
  self:clearTitleBarButtons()

  self:_installActionBar()

  -- we need to do this after updating
  self:updateChapterList()
end

--- @private
--- Empty out both title-bar slots so we render a title-only header.
--- patchTitleBar() may later add a small language indicator on the left
--- for multi-language manga.
function ChapterListing:clearTitleBarButtons()
  local empty_left = HorizontalSpan:new { width = 0 }
  local empty_right = HorizontalSpan:new { width = 0 }
  self.title_bar.left_button = empty_left
  self.title_bar.right_button = empty_right
  if self.title_bar[2] ~= nil then
    self.title_bar[2] = empty_left
  end
  if self.title_bar[3] ~= nil then
    self.title_bar[3] = empty_right
  end
end

--- @private
--- Replace KOReader's chevron pagination text with a stacked layout:
---   [ Back · Resume · Refresh · Download · More ]
---   [   <<   <   Page X of Y   >   >>   ]
--- The skip-to-first / skip-to-last buttons (<<, >>) are KOReader's
--- own pagination chevrons — they're preserved by capturing the
--- original page_info children before wiping the row and reinserting
--- them inside the new vertical layout.
function ChapterListing:_installActionBar()
  if not self.page_info or not self.page_info_text then return end

  local actions = {
    {
      glyph = Icons.FA_ARROW_LEFT,
      label = _("Back"),
      callback = function() self:onClose() end,
    },
    {
      glyph = Icons.RESTORE,
      label = _("Resume"),
      callback = function() self:readContinue(false) end,
    },
    {
      glyph = Icons.REFRESHING,
      label = _("Refresh"),
      callback = function() self:refreshChapters() end,
    },
    {
      glyph = Icons.FA_DOWNLOAD,
      label = _("Download"),
      callback = function() self:onDownloadUnreadChapters() end,
    },
    {
      glyph = Icons.FA_ELLIPSIS_VERTICAL,
      label = _("More"),
      callback = function() self:openMenu() end,
    },
  }

  local action_bar = ActionBar:new {
    width = Screen:getWidth(),
    show_parent = self,
    actions = actions,
  }

  local page_info = self.page_info

  -- Capture current children of page_info (chevron_first, chevron_left,
  -- page_info_text, chevron_right, chevron_last). After a BaseMenu rebuild
  -- (e.g. updateOfflineSubtitle on WiFi connect) these references are
  -- fresh, so don't cache across installs.
  local chevron_row = HorizontalGroup:new { align = "center" }
  for i = 1, #page_info do
    table.insert(chevron_row, page_info[i])
  end

  -- BaseMenu's _recalculateDimen sizes the items area based ONLY on
  -- page_info_text:getSize().h, not on the parent HorizontalGroup. Wrap
  -- page_info_text in a thin size proxy that reports the combined height
  -- (action bar + gap + text + chevrons) so the items area doesn't draw
  -- under our bar. Forward setText so updatePageInfo's "Page X of Y"
  -- label keeps refreshing.
  local original_text = self.page_info_text
  if original_text._bobo_action_bar_proxy then
    original_text = original_text._inner
  end
  local action_bar_h = action_bar:getSize().h + Screen:scaleBySize(2)
  self.page_info_text = setmetatable({
    _bobo_action_bar_proxy = true,
    _inner = original_text,
    _extra_h = action_bar_h,
    setText = function(s, ...) return s._inner:setText(...) end,
    getSize = function(s)
      local sz = s._inner:getSize()
      return { w = sz.w, h = sz.h + s._extra_h }
    end,
    paintTo = function(s, bb, x, y) return s._inner:paintTo(bb, x, y) end,
  }, {
    -- Forward any other field/method BaseMenu may poke at (.dimen,
    -- :setEnabled, etc.) to the underlying Button so its internal
    -- bookkeeping isn't broken.
    __index = function(t, k) return t._inner[k] end,
  })

  for i = #page_info, 1, -1 do
    page_info[i] = nil
  end
  page_info:resetLayout()
  table.insert(page_info, VerticalGroup:new {
    align = "center",
    action_bar,
    VerticalSpan:new { width = Screen:scaleBySize(2) },
    chevron_row,
  })
end

--- Re-install the action bar after the parent class rebuilds page_info.
--- See LibraryView for the full rationale: widgets/Menu.lua's
--- updateOfflineSubtitle calls BaseMenu.init on network state changes,
--- which silently wipes our injected layout.
function ChapterListing:updateOfflineSubtitle(skip_reinit)
  Menu.updateOfflineSubtitle(self, skip_reinit)
  if not skip_reinit and self.page_info_text then
    self:_installActionBar()
  end
end

function ChapterListing:onClose(call_return)
  if self.on_return_callback and call_return ~= false then
    self.on_return_callback()
  end
  UIManager:close(self)
end

function ChapterListing:readSettings()
  if self.r_settings == nil then
    self.r_settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/bobo_lang.lua")
  end

  return self.r_settings
end

--- Fetches the cached chapter list from the backend and updates the menu items.
function ChapterListing:updateChapterList()
  local response = Backend.listCachedChapters(self.manga.source.id, self.manga.id)

  if response.type == 'ERROR' then
    ErrorDialog:show(response.message)

    return
  end

  local chapter_results = response.body
  self.raw_chapters = chapter_results

  local langs_set = {}
  local langs_list = {}
  for _, chapter in ipairs(chapter_results) do
    local lang = chapter.lang or "unknown"
    if not langs_set[lang] then
      langs_set[lang] = true
      table.insert(langs_list, lang)
    end
  end

  -- Load / initialize language preferences only when it matters (2+ langs)
  if #langs_list >= 2 then
    table.sort(langs_list)
    self.langs = {}
    for _, lang in ipairs(langs_list) do
      table.insert(self.langs, { id = lang, name = lang })
    end
    local key = self:hashMangaId() .. "_lang"
    self.langs_selected = self:readSettings():readSetting(key, {})
    -- If no preferences are set, default to selecting all available languages
    if not self.langs_selected or #self.langs_selected == 0 then
      self.langs_selected = langs_list
    end
    self:patchTitleBar(#self.langs_selected)
    UIManager:setDirty(self.show_parent, "ui", self.dimen)
    self.chapters = filterChaptersByLang(self.raw_chapters, self.langs_selected)
  else
    -- Single-language manga: no language UI/filtering needed
    self.langs = {}
    self.langs_selected = {}
    self.chapters = self.raw_chapters
  end

  self:extractAvailableScanlators()

  self:loadSavedScanlatorPreference()

  self:updateItems()
end

--- @private
--- @param count_lang number
--- For multi-language manga, show a small language indicator on the left
--- of the title bar. The hamburger that used to live next to it moved
--- into the bottom action bar's More overflow.
function ChapterListing:patchTitleBar(count_lang)
  local left_icon_size_ratio = self.title_bar.left_icon_size_ratio
  local left_icon_size = Screen:scaleBySize(DGENERIC_ICON_SIZE * left_icon_size_ratio)

  local lang_button = Button:new {
    text = Icons.LANG .. " " .. count_lang,
    face = SMALL_FONT_FACE,
    bordersize = 0,
    enabled = true,
    text_font_size = left_icon_size,
    text_font_bold = false,
    callback = function()
      self:showSelectLanguage()
    end,
  }

  self.title_bar.left_button = lang_button

  --- [1] title
  --- [2] left button
  --- [3] right button
  if self.title_bar[2] ~= nil then
    self.title_bar[2] = lang_button
  end
end

--- @private
function ChapterListing:hashMangaId()
  ---@type Manga
  local manga = self.manga
  local key = md5(manga.source.id .. "/" .. manga.id)

  return key
end

--- @private
function ChapterListing:showSelectLanguage()
  local key = self:hashMangaId() .. "_lang"
  ---@diagnostic disable-next-line: redundant-parameter
  local dialog = CheckboxDialog:new {
    title = _("Languages"),
    current = self.langs_selected,
    options = self.langs,
    update_callback = function(value)
      self.langs_selected = value
      self:readSettings():saveSetting(key, value)
      self:readSettings():flush()

      self.chapters = filterChaptersByLang(self.raw_chapters, self.langs_selected)
      self:extractAvailableScanlators()
      self:loadSavedScanlatorPreference()
      self:updateItems()

      self:patchTitleBar(#self.langs_selected)
      UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
  }

  UIManager:show(dialog)
end

-- Load saved scanlator preference from backend
function ChapterListing:loadSavedScanlatorPreference()
  local response = Backend.getPreferredScanlator(self.manga.source.id, self.manga.id)

  self.selected_scanlator = nil

  if response.type == 'SUCCESS' and response.body then
    for _, available_scanlator in ipairs(self.available_scanlators) do
      if available_scanlator == response.body then
        self.selected_scanlator = response.body
        break
      end
    end
  end
end

-- Extract unique scanlators
function ChapterListing:extractAvailableScanlators()
  local scanlators = {}
  local scanlator_set = {}

  for __, chapter in ipairs(self.chapters) do
    local scanlator = chapter.scanlator or _("Unknown")
    if not scanlator_set[scanlator] then
      scanlator_set[scanlator] = true
      table.insert(scanlators, scanlator)
    end
  end

  table.sort(scanlators)

  self.available_scanlators = scanlators
end

--- Updates the menu item contents with the chapter information
--- @private
function ChapterListing:updateItems()
  if #self.chapters > 0 then
    self.item_table = self:generateItemTableFromChapters(self.chapters)
    self.multilines_show_more_text = false
    self.items_per_page = nil
  else
    self.item_table = self:generateEmptyViewItemTable()
    self.multilines_show_more_text = true
    self.items_per_page = 1
  end

  Menu.updateItems(self)
end

---@private
---@param chapter Chapter
---@return Chapter
function ChapterListing:findRootChapter(chapter)
  for _, root in ipairs(self.chapters) do
    if root.id == chapter.id then
      return root
    end
  end

  ---@diagnostic disable-next-line: missing-return
  assert(false, "not found chapter reference")
end

--- @private
function ChapterListing:generateEmptyViewItemTable()
  return {
    {
      text = _("No chapters found") .. ". " .. _("Try swiping down to refresh the chapter list."),
      dim = true,
      select_enabled = false,
    }
  }
end

--- @private
function ChapterListing:generateItemTableFromChapters(chapters)
  -- Filter chapters by selected scanlator
  local filtered_chapters = chapters
  if self.selected_scanlator then
    filtered_chapters = {}
    for __, chapter in ipairs(chapters) do
      local chapter_scanlator = chapter.scanlator or _("Unknown")
      if chapter_scanlator == self.selected_scanlator then
        table.insert(filtered_chapters, chapter)
      end
    end
  end

  --- @type Chapter[]
  --- @diagnostic disable-next-line: assign-type-mismatch
  local sorted_chapters_with_index = util.tableDeepCopy(filtered_chapters)
  for index, chapter in ipairs(sorted_chapters_with_index) do
    ---@diagnostic disable-next-line: inject-field
    chapter.index = index
  end

  if self.chapter_sorting_mode == 'chapter_ascending' then
    table.sort(sorted_chapters_with_index, isBeforeChapter)
  else
    table.sort(sorted_chapters_with_index, function(a, b) return not isBeforeChapter(a, b) end)
  end

  local item_table = {}

  for __, chapter in ipairs(sorted_chapters_with_index) do
    local text = ""
    if chapter.volume_num ~= nil then
      -- FIXME we assume there's a chapter number if there's a volume number
      -- might not be true but who knows
      text = text .. _("Volume") .. " " .. chapter.volume_num .. ", "
    end

    if chapter.chapter_num ~= nil then
      text = text .. _("Chapter") .. " " .. chapter.chapter_num .. " - "
    end

    text = text .. chapter.title

    -- Only show scanlator if not filtering by scanlator
    if chapter.scanlator ~= nil and not self.selected_scanlator then
      text = text .. " (" .. chapter.scanlator .. ")"
    end

    -- The text that shows to the right of the menu item
    local mandatory = ""
    if chapter.read then
      mandatory = mandatory .. Icons.FA_BOOK
    end

    if chapter.last_read then
      mandatory = (calcLastReadText(chapter.last_read) .. " ") .. mandatory
    end

    if chapter.downloaded then
      mandatory = mandatory .. Icons.FA_DOWNLOAD
    end

    local post_text = nil
    if chapter.locked then
      post_text = _("Locked")
    end
    if #self.langs >= 2 and chapter.lang then
      post_text = (post_text and post_text .. " " or "") .. "(" .. chapter.lang .. ")"
    end

    table.insert(item_table, {
      chapter = chapter,
      text = text,
      post_text = post_text,
      dim = chapter.locked,
      mandatory = chapter.locked and Icons.FA_LOCKED or mandatory,
    })
  end

  return item_table
end

--- @private
function ChapterListing:onReturn()
  table.remove(self.paths, 1)
  self:onClose()
end

--- Shows the chapter list for a given manga. Must be called from a function wrapped with `Trapper:wrap()`.
---
--- @param manga Manga
--- @param onReturnCallback fun(): nil
--- @param accept_cached_results? boolean If set, failing to refresh the list of chapters from the source
--- will not show an error. Defaults to false.
--- @return boolean
function ChapterListing:fetchAndShow(manga, onReturnCallback, accept_cached_results)
  accept_cached_results = accept_cached_results or false

  local cancel_id = Backend.createCancelId()
  local refresh_chapters_response, cancelled = LoadingDialog:showAndRun(
    _("Refreshing chapters..."),
    function()
      return Backend.refreshChapters(cancel_id, manga.source.id, manga.id)
    end,
    function()
      Backend.cancel(cancel_id)

      local cancelledMessage = InfoMessage:new {
        text = _("Cancelled."),
      }
      UIManager:show(cancelledMessage)
    end,
    nil
  )

  if cancelled then
    return false
  end

  if refresh_chapters_response.type == 'ERROR' then
    ErrorDialog:show(_("Refresh chapter error") .. "\n\n" .. refresh_chapters_response.message)

    if not accept_cached_results then
      return false
    end
  end

  local response = Backend.getSettings()

  if response.type == 'ERROR' then
    ErrorDialog:show(response.message)

    return false
  end

  local settings = response.body

  local ui = ChapterListing:new {
    manga = manga,
    chapter_sorting_mode = settings.chapter_sorting_mode,
    on_return_callback = onReturnCallback,
    covers_fullscreen = true, -- hint for UIManager:_repaint()
    page = self.page,
    preload_count = settings.preload_chapters,
    preload_on_progress = settings.preload_on_chapter_progress or false,
    -- KOReader's BaseMenu rotation handler is a no-op without
    -- `_recreate_func`. Provide one so the chapter list re-renders
    -- for the new orientation when the device rotates.
    _recreate_func = function()
      ChapterListing:fetchAndShow(manga, onReturnCallback, accept_cached_results)
    end,
  }
  ui.on_return_callback = onReturnCallback
  UIManager:show(ui)

  Testing:emitEvent("chapter_listing_shown")

  return true
end

--- @private
function ChapterListing:onPrimaryMenuChoice(item)
  ---@type Chapter
  local chapter = item.chapter

  if chapter.locked then
    UIManager:show(InfoMessage:new { text = _("Chapter is locked") })
  else
    self:openChapterOnReader(chapter)
  end
end

--- @private
function ChapterListing:onContextMenuChoice(item)
  ---@type Chapter
  local chapter = item.chapter


  local dialog_context_menu

  local context_menu_buttons = {
    {
      {
        text = Icons.FA_OPEN .. " " .. _("Open"),
        callback = function()
          UIManager:close(dialog_context_menu)

          self:onPrimaryMenuChoice(item)
        end
      }
    },
    {
      {
        text = Icons.REFRESHING .. " " .. _("Refresh"),
        callback = function()
          UIManager:close(dialog_context_menu)

          self:revokeChapter(chapter, false)
          self:downloadChapter(chapter, nil, function(manga_path)
            UIManager:show(InfoMessage:new { text = _("Chapter refreshed") })
          end)
        end
      },
      {
        text_func = function()
          return Icons.CHECK_ALL .. " " .. _("Mark") .. " " .. (chapter.read and "unread" or "read")
        end,
        callback = function()
          UIManager:close(dialog_context_menu)

          self:markChapterAs(chapter, chapter.read and false or true)
        end
      }
    },
    {
      {
        text_func = function()
          return Icons.FA_DOWNLOAD .. " " .. (chapter.downloaded and _("Remove") or _("Download"))
        end,
        callback = function()
          UIManager:close(dialog_context_menu)

          if chapter.downloaded then
            self:revokeChapter(chapter)
          else
            self:downloadChapter(chapter, nil, function(manga_path)
              UIManager:show(InfoMessage:new { text = _("Chapter downloaded") })
            end)
          end
        end
      }
    }
  }
  dialog_context_menu = ButtonDialog:new {
    title = item.text,
    buttons = context_menu_buttons,
  }
  UIManager:show(dialog_context_menu)
end

--- @private
--- @param chapter Chapter
function ChapterListing:revokeChapter(chapter, hide_notify)
  Trapper:wrap(function()
    local revoke_chapter_response = LoadingDialog:showAndRun(
      _("Revoke chapter..."),
      function()
        return Backend.revokeChapter(self.manga.source.id, self.manga.id, chapter.id)
      end
    )

    if revoke_chapter_response.type == 'ERROR' then
      ErrorDialog:show(revoke_chapter_response.message)

      return
    end

    if revoke_chapter_response then
      self:findRootChapter(chapter).downloaded = false
      self:updateItems()
    end

    if hide_notify ~= false then
      UIManager:show(InfoMessage:new { text = _("Removed chapter") })
    end
  end)
end

--- @private
--- @param chapter Chapter
--- @param value boolean
function ChapterListing:markChapterAs(chapter, value)
  Trapper:wrap(function()
    local toggle_mark_response = LoadingDialog:showAndRun(
      (value and _("Marking") or _("Un-marking")) .. " " .. _("chapter..."),
      function()
        return Backend.markChapterAsRead(self.manga.source.id, self.manga.id, chapter.id, value)
      end
    )

    if toggle_mark_response.type == 'ERROR' then
      ErrorDialog:show(toggle_mark_response.message)

      return
    end

    local root = self:findRootChapter(chapter)
    root.read = value
    -- The backend clears `last_read` when a chapter is unmarked. Mirror that
    -- locally so Resume doesn't pick this chapter on the next tap, before any
    -- refresh has run.
    if not value then
      root.last_read = nil
    end
    self:updateItems()
  end)
end

--- @private
function ChapterListing:onSwipe(arg, ges_ev)
  local direction = BD.flipDirectionIfMirroredUILayout(ges_ev.direction)
  if direction == "south" then
    self:refreshChapters()

    return
  end

  Menu.onSwipe(self, arg, ges_ev)
end

--- @private
function ChapterListing:refreshChapters()
  Trapper:wrap(function()
    local cancel_id = Backend.createCancelId()
    local refresh_chapters_response, cancelled = LoadingDialog:showAndRun(
      _("Refreshing chapters..."),
      function()
        return Backend.refreshChapters(cancel_id, self.manga.source.id, self.manga.id)
      end,
      function()
        Backend.cancel(cancel_id)
        local cancelledMessage = InfoMessage:new {
          text = _("Cancelled."),
        }
        UIManager:show(cancelledMessage)
      end
    )

    if cancelled then
      return
    end

    if refresh_chapters_response.type == 'ERROR' then
      ErrorDialog:show(refresh_chapters_response.message)

      return
    end

    self:updateChapterList()
  end)
end

--- @param manga Manga
--- @param read boolean mode mark read or unread
--- @param callback nil|function(number)
function ChapterListing:openMarkDialog(manga, read, callback)
  local dialog
  dialog = InputDialog:new {
    title = read and _("Mark read") or _("Mark unread"),
    input_hint = _("1 - 10.5, 20 - 100"),
    description = _("Mark chapters as read or unread") .. "\n\n" .. _("Leaving blank will select all"),
    buttons = {
      {
        {
          text = _("Cancel"),
          id = "close",
          callback = function()
            UIManager:close(dialog)
          end,
        },
        {
          text = _("Mark"),
          is_enter_default = true,
          callback = function()
            UIManager:close(dialog)

            local text = dialog:getInputText()


            Trapper:wrap(function()
              local response = LoadingDialog:showAndRun(
                _("Marking..."),
                function() return Backend.markChaptersAsRead(manga.source.id, manga.id, text, read) end
              )

              if response.type == 'ERROR' then
                ErrorDialog:show(response.message)

                return
              end

              UIManager:show(InfoMessage:new { text = _("Marked") })

              if callback ~= nil then
                callback(response.body)
              end
            end)
          end,
        },
      }
    }
  }

  UIManager:show(dialog)
  dialog:onShowKeyboard()
end

--- @param errors DownloadError[]
local function formatDownloadErrors(errors)
  if not errors or #errors == 0 then
    return _("No errors")
  end

  local max_items = 5
  local lines = {}

  for i = 1, math.min(#errors, max_items) do
    local err = errors[i]
    table.insert(lines, string.format(
      _("Page") .. " %d | %s (%d " .. _("attempts") .. ")",
      err.page_index,
      err.reason,
      err.attempts
    ))
  end

  if #errors > max_items then
    table.insert(lines, string.format(_("… and %d more errors"), #errors - max_items))
  end

  return table.concat(lines, "\n")
end

--- @private
--- @param chapter Chapter
--- @param download_job DownloadChapter|nil
--- @param callback fun(manga_path)
function ChapterListing:downloadChapter(chapter, download_job, callback)
  Trapper:wrap(function()
    -- If the download job we have is already invalid (internet problems, for example),
    -- spawn a new job before proceeding.
    if download_job == nil or (download_job.started and download_job:poll().type == 'ERROR') then
      download_job = DownloadChapter:new(chapter.source_id, chapter.manga_id, chapter.id, chapter.chapter_num)
    end

    if download_job == nil then
      ErrorDialog:show(_("Could not download chapter."))

      return
    end

    -- Fast path: preload already finished, result is cached in the job object.
    -- Ask the backend to confirm the file is still on disk — it owns file management,
    -- not us. If the file was evicted, the backend returns ERROR and we fall through
    -- to a fresh download.
    if download_job.result and download_job.result.type == 'SUCCESS' then
      local stored = Backend.getStoredChapter(chapter.source_id, chapter.manga_id, chapter.id)
      if stored.type == 'SUCCESS' then
        self:findRootChapter(chapter).downloaded = true
        callback(stored.body.path)
        return
      end
      download_job.result = nil
      download_job.started = false
      MangaReader.preload_jobs[chapter.id] = nil
    end

    local time = require("ui/time")
    local start_time = time.now()
    local response, cancelled = LoadingDialog:showAndRun(
      _(chapter.downloaded and "Loading chapter..." or "Downloading chapter...")
      .. '\nCh.' .. (chapter.chapter_num or _('unknown'))
      .. ' '
      .. (chapter.title or ''),
      function()
        local response_start = download_job:start()
        if response_start.type == 'ERROR' then
          ErrorDialog:show(_('Could not download chapter.'))

          return response_start
        end

        return download_job:runUntilCompletion()
      end,
      function()
        if download_job.started then
          download_job:requestCancellation()
        end

        local cancelledMessage = InfoMessage:new {
          text = _("Download cancelled."),
        }
        UIManager:show(cancelledMessage)
      end,
      function(cancel)
        local confirm = ConfirmBox:new {
          text = _("Are you sure you want to cancel the download?"),
          ok_callback = cancel
        }
        UIManager:show(confirm)

        return confirm
      end
    )

    if cancelled then
      return
    end

    if response.type == 'ERROR' then
      ErrorDialog:show(response.message)

      return
    end

    self:findRootChapter(chapter).downloaded = true

    if #response.body.errors > 0 then
      logger.err("Download job errors: ", response.body.path)

      UIManager:show(InfoMessage:new {
        text = formatDownloadErrors(response.body.errors)
      })
    end

    logger.info("Waited ", time.to_ms(time.since(start_time)), "ms for download job to finish.")

    callback(response.body.path)
  end)
end


--- @private
--- @param chapter Chapter
--- @param download_job DownloadChapter|nil
function ChapterListing:openChapterOnReader(chapter, download_job)
  self:downloadChapter(chapter, download_job, function(manga_path)
    local onReturnCallback = function()
      self:updateItems()
      UIManager:show(self)
    end

    local onEndOfBookCallback = function()
      Backend.markChapterAsRead(chapter.source_id, chapter.manga_id, chapter.id)

      self:updateChapterList()

      local nextChapter = findNextChapter(self.chapters, chapter)
      local nextChapterDownloadJob = nextChapter and MangaReader.preload_jobs[nextChapter.id] or nil

      if nextChapter ~= nil then
        logger.info("opening next chapter", nextChapter)
        self:openChapterOnReader(nextChapter, nextChapterDownloadJob)
      else
        MangaReader:closeReaderUi(function()
          UIManager:show(self)
        end)
      end
    end

    Trapper:wrap(function()
      Backend.updateLastReadChapter(
        chapter.source_id,
        chapter.manga_id,
        chapter.id
      )
    end)

    --- Manga is shown to user here.
    MangaReader:show({
      path = manga_path,
      on_end_of_book_callback = onEndOfBookCallback,
      chapter = chapter,
      all_chapters = self.raw_chapters,
      preload_count = self.preload_count,
      preload_on_progress = self.preload_on_progress,
      on_close_book_callback = function(chapter)
        Trapper:wrap(function()
          Backend.updateLastReadChapter(
            chapter.source_id,
            chapter.manga_id,
            chapter.id
          )
        end)
      end,
      on_return_callback = onReturnCallback,
    })

    self:onClose(false)
  end)
end

--- @private
--- The "More" overflow opened from the bottom action bar. Grouped by
--- purpose, never more than two buttons per row:
---   navigation   → Back to library
---   manga        → Add to Library · Details
---   read state   → Mark read · Mark unread
---   reading      → Next Chapter
---   filters      → Languages · Filter by Group (only when applicable)
function ChapterListing:openMenu()
  local dialog

  local buttons = {
    {
      {
        text = "← " .. _("Back to library"),
        callback = function()
          UIManager:close(dialog)
          UIManager:close(self)
          -- Bypass the callback chain: go directly to the library.
          -- Lazy require avoids the circular dependency (LibraryView requires ChapterListing).
          require("LibraryView"):fetchAndShow()
        end
      },
    },
    {
      {
        text = Icons.FA_BELL .. " " .. _("Add to Library"),
        callback = function()
          UIManager:close(dialog)

          self:addToLibrary()
        end
      },
      {
        text = Icons.INFO .. " " .. _("Details"),
        callback = function()
          UIManager:close(dialog)

          Trapper:wrap(function()
            local onReturnCallback = function()
              Trapper:wrap(function()
                self:fetchAndShow(self.manga, self.on_return_callback, self.accept_cached_results)
              end)
            end
            MangaInfoWidget:fetchAndShow(self.manga, onReturnCallback)
            UIManager:close(self)
          end)
        end
      }
    },
    {
      {
        text = Icons.CHECK_ALL .. " " .. _("Mark read"),
        callback = function()
          UIManager:close(dialog)

          ChapterListing:openMarkDialog(self.manga, true, function()
            self:refreshChapters()
          end)
        end
      },
      {
        text = Icons.CHECK_ALL .. " " .. _("Mark unread"),
        callback = function()
          UIManager:close(dialog)

          ChapterListing:openMarkDialog(self.manga, false, function()
            self:refreshChapters()
          end)
        end
      }
    },
    {
      {
        text = Icons.ANGLES_RIGHT .. " " .. _("Next Chapter"),
        callback = function()
          UIManager:close(dialog)

          self:readContinue(true)
        end
      }
    }
  }

  -- Both list filters share the bottom row.
  local filter_row = {}

  if #self.langs >= 2 then
    table.insert(filter_row, {
      text = Icons.LANG .. " " .. _("Languages"),
      callback = function()
        UIManager:close(dialog)

        self:showSelectLanguage()
      end
    })
  end

  if #self.available_scanlators > 1 then
    local scanlator_text = self.selected_scanlator and
        (Icons.FA_FILTER .. " " .. _("Group") .. ": " .. self.selected_scanlator) or
        Icons.FA_FILTER .. " " .. _("Filter by Group")

    table.insert(filter_row, {
      text = scanlator_text,
      callback = function()
        UIManager:close(dialog)
        self:showScanlatorDialog()
      end
    })
  end

  if #filter_row > 0 then
    table.insert(buttons, filter_row)
  end

  dialog = ButtonDialog:new {
    buttons = buttons,
  }

  UIManager:show(dialog)
end

function ChapterListing:addToLibrary()
  Trapper:wrap(function()
    local response = LoadingDialog:showAndRun(
      _("Adding to library..."),
      function()
        return Backend.addMangaToLibrary(self.manga.source.id, self.manga.id)
      end
    )

    if response.type == 'ERROR' then
      ErrorDialog:show(_("Failed to add to library") .. ": " .. response.message)
      return
    end

    UIManager:show(InfoMessage:new {
      text = _("Added to library."),
    })
  end)
end

function ChapterListing:readContinue(nextChapter)
  local chapter_to_open = findLastRead(self.chapters)

  if nextChapter and chapter_to_open ~= nil then
    chapter_to_open = findNextChapter(self.chapters, chapter_to_open)
  end
  if not chapter_to_open then
    UIManager:show(InfoMessage:new { text = _("Sadly, no next chapter available! :c") })
    return
  end

  local confirm_dialog
  confirm_dialog = ConfirmBox:new {
    text = _(nextChapter and "Next" or "Resume") .. " " .. _("reading with") .. ":\n" .. getChapterDisplayName(chapter_to_open) .. "?",
    ok_text = _("Read"),
    cancel_text = _("Cancel"),
    ok_callback = function()
      UIManager:close(confirm_dialog)

      self:openChapterOnReader(chapter_to_open)
    end,
    cancel_callback = function()
      UIManager:close(confirm_dialog)
    end
  }
  UIManager:show(confirm_dialog)
end

-- Scanlator selection dialog with persistence
function ChapterListing:showScanlatorDialog()
  local dialog
  local buttons = {}

  -- Show All option
  table.insert(buttons, {
    {
      text = self.selected_scanlator == nil and Icons.FA_CHECK .. " " .. _("Show All") or " " .. _("Show All"),
      callback = function()
        UIManager:close(dialog)
        self.selected_scanlator = nil

        Backend.setPreferredScanlator(self.manga.source.id, self.manga.id, nil)

        self:updateItems()
        UIManager:show(InfoMessage:new { text = _("Showing all groups"), timeout = 1 })
      end
    }
  })

  -- Individual scanlators
  for __, scanlator in ipairs(self.available_scanlators) do
    local is_selected = self.selected_scanlator == scanlator
    local text = is_selected and (Icons.FA_CHECK .. " " .. scanlator) or scanlator

    table.insert(buttons, {
      {
        text = text,
        callback = function()
          UIManager:close(dialog)
          self.selected_scanlator = scanlator

          Backend.setPreferredScanlator(self.manga.source.id, self.manga.id, scanlator)

          self:updateItems()
          UIManager:show(InfoMessage:new { text = _("Filtered to") .. ": " .. scanlator, timeout = 1 })
        end
      }
    })
  end

  dialog = ButtonDialog:new {
    title = _("Filter by Group"),
    buttons = buttons,
  }

  UIManager:show(dialog)
end

function ChapterListing:onDownloadUnreadChapters()
  local input_dialog
  input_dialog = InputDialog:new {
    title = _("Download unread chapters..."),
    input_type = "number",
    input_hint = _("Amount of unread chapters (default: all)"),
    description = self.selected_scanlator and
        (_("Will download from") .. ": " .. self.selected_scanlator .. "\n\n" .. _("Specify amount or leave empty for all.")) or
        _("Specify the amount of unread chapters to download") .. ", " .. _("or leave empty to download all of them."),
    buttons = {
      {
        {
          text = _("Cancel"),
          id = "close",
          callback = function()
            UIManager:close(input_dialog)
          end,
        },
        {
          text = _("Download"),
          is_enter_default = true,
          callback = function()
            UIManager:close(input_dialog)

            local amount = nil
            if input_dialog:getInputText() ~= '' then
              amount = tonumber(input_dialog:getInputText())

              if amount == nil then
                ErrorDialog:show(_("Invalid amount of chapters!"))

                return
              end
            end

            -- Use scanlator-aware download
            local job = self:createDownloadJob(amount)
            if job then
              ---@diagnostic disable-next-line: undefined-field
              local dialog = DownloadUnreadChaptersJobDialog:new({
                show_parent = self,
                job = job,
                dismiss_callback = function()
                  self:updateChapterList()
                end
              })

              dialog:show()
            else
              UIManager:show(InfoMessage:new {
                text = _("No unread chapters found for") .. " " .. (self.selected_scanlator or "this manga"),
                timeout = 2,
              })
            end
          end,
        },
      }
    }
  }

  UIManager:show(input_dialog)
end

function ChapterListing:createDownloadJob(amount)
  return DownloadUnreadChapters:new({
    source_id = self.manga.source.id,
    manga_id = self.manga.id,
    amount = amount,
    scanlator = self.selected_scanlator,
    langs = self.langs_selected,
  })
end

function ChapterListing:onDownloadAllChapters()
  local downloadingMessage = InfoMessage:new {
    text = _("Downloading all chapters, this will take a while…"),
  }

  UIManager:show(downloadingMessage)

  -- FIXME when the backend functions become actually async we can get rid of this probably
  UIManager:nextTick(function()
    local time = require("ui/time")
    local startTime = time.now()
    local response = Backend.downloadAllChapters(self.manga.source.id, self.manga.id)

    if response.type == 'ERROR' then
      ErrorDialog:show(response.message)

      return
    end

    local onDownloadFinished = function()
      -- FIXME I don't think mutating the chapter list here is the way to go, but it's quicker
      -- than making another call to list the chapters from the backend...
      -- this also behaves wrong when the download fails but manages to download some chapters.
      -- some possible alternatives:
      -- - return the chapter list from the backend on the `downloadAllChapters` call
      -- - biting the bullet and making the API call
      for __, chapter in ipairs(self.chapters) do
        self:findRootChapter(chapter).downloaded = true
      end

      logger.info("Downloaded all chapters in ", time.to_ms(time.since(startTime)), "ms")

      self:updateItems()
    end

    local updateProgress = function() end

    local cancellationRequested = false
    local onCancellationRequested = function()
      local response = Backend.cancelDownloadAllChapters(self.manga.source.id, self.manga.id)
      -- FIXME is it ok to assume there are no errors here?
      assert(response.type == 'SUCCESS')

      cancellationRequested = true

      updateProgress()
    end

    local onCancelled = function()
      local cancelledMessage = InfoMessage:new {
        text = _("Cancelled."),
      }

      UIManager:show(cancelledMessage)
    end

    updateProgress = function()
      -- Remove any scheduled `updateProgress` calls, because we do not want this to be
      -- called again if not scheduled by ourselves. This may happen when `updateProgress` is called
      -- from another place that's not from the scheduler (eg. the `onCancellationRequested` handler),
      -- which could result in an additional `updateProgress` call that was already scheduled previously,
      -- even if we do not schedule it at the end of the method.
      UIManager:unschedule(updateProgress)
      UIManager:close(downloadingMessage)

      local response = Backend.getDownloadAllChaptersProgress(self.manga.source.id, self.manga.id)
      if response.type == 'ERROR' then
        ErrorDialog:show(response.message)

        return
      end

      local downloadProgress = response.body

      local messageText = nil
      local isCancellable = false
      if downloadProgress.type == "INITIALIZING" then
        messageText = _("Downloading all chapters, this will take a while…")
      elseif downloadProgress.type == "FINISHED" then
        onDownloadFinished()

        return
      elseif downloadProgress.type == "CANCELLED" then
        onCancelled()

        return
      elseif cancellationRequested then
        messageText = _("Waiting for download to be cancelled…")
      elseif downloadProgress.type == "PROGRESSING" then
        messageText = _("Downloading all chapters, this will take a while… (") ..
            downloadProgress.downloaded .. "/" .. downloadProgress.total .. ")." ..
            "\n\n" ..
            _("Tap outside this message to cancel.")

        isCancellable = true
      else
        logger.err("unexpected download progress message", downloadProgress)

        error("unexpected download progress message")
      end

      downloadingMessage = InfoMessage:new {
        text = messageText,
        dismissable = isCancellable,
      }

      -- Override the default `onTapClose`/`onAnyKeyPressed` actions
      if isCancellable then
        local originalOnTapClose = downloadingMessage.onTapClose
        downloadingMessage.onTapClose = function(messageSelf)
          onCancellationRequested()

          originalOnTapClose(messageSelf)
        end

        local originalOnAnyKeyPressed = downloadingMessage.onAnyKeyPressed
        downloadingMessage.onAnyKeyPressed = function(messageSelf)
          onCancellationRequested()

          originalOnAnyKeyPressed(messageSelf)
        end
      end
      UIManager:show(downloadingMessage)

      UIManager:scheduleIn(1, updateProgress)
    end

    UIManager:scheduleIn(1, updateProgress)
  end)
end

return ChapterListing
