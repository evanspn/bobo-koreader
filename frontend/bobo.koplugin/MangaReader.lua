local DocSettings = require("docsettings")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local logger = require("logger")
local _ = require("gettext+")

local Backend = require("Backend")
local DownloadChapter = require("jobs/DownloadChapter")
local findNextChapter = require("chapters/findNextChapter")
local Testing = require('testing')

-- Reader settings that should carry over between chapters.
-- These are the keys KOReader stores in each file's .sdr sidecar.
local CARRY_KEYS = {
  "kopt_zoom_mode_genus",   -- fit-page / fit-width / fit-height / custom / fit-content
  "kopt_zoom_factor",       -- custom zoom level
  "kopt_page_scroll",       -- 0 = page mode, 1 = scroll mode
  "kopt_reading_order",     -- 0 = LTR, 1 = RTL
  "kopt_render_mode",       -- rendering pipeline
  "kopt_zoom_mode_type",
  "kopt_zoom_mode_value",
  "kopt_contrast",
  "kopt_page_gap_height",
  -- rotation_mode intentionally omitted: chapter advance always resets to
  -- the user's preferred portrait orientation (see closeReaderUi / show).
}

--- @class MangaReader
--- This is a singleton that contains a simpler interface with ReaderUI.
local MangaReader = {
  on_return_callback = nil,
  on_end_of_book_callback = nil,
  chapter = nil,
  on_close_book_callback = nil,
  is_showing = false,
  is_switching_document = false,
  -- preload state — survives as long as MangaReader (singleton) is alive
  preload_jobs = {},
  all_chapters = {},
  preload_count = 0,
  preload_on_progress = false,
  -- last saved page to avoid redundant writes
  _last_saved_page = nil,
  _progress_preload_triggered = false,
  -- poll throttle: skip this many page turns before calling prunePreloadJobs again
  _prune_skip = 0,
}

--- @class MangaReaderOptions
--- @field path string Path to the file to be displayed.
--- @field on_return_callback fun(): nil Function to be called when the user selects "Go back to Bobo".
--- @field on_end_of_book_callback fun(): nil Function to be called when the user reaches the end of the file.
--- @field chapter? Chapter The chapter being read.
--- @field on_close_book_callback? fun(Chapter): nil Function to be called when the user closes the manga reader.
--- @field all_chapters? Chapter[] Full ordered chapter list used for preloading the next chapters.
--- @field preload_count? number How many chapters ahead to silently preload (from settings).
--- @field preload_on_progress? boolean If true, preload the next chapter when 80% of the current one is read.

--- Displays the file located in `path` in the KOReader's reader.
--- If a file is already being displayed, it will be replaced.
---
--- @param options MangaReaderOptions
function MangaReader:show(options)
  self.on_return_callback = options.on_return_callback
  self.on_end_of_book_callback = options.on_end_of_book_callback
  self.on_close_book_callback = options.on_close_book_callback
  self.all_chapters = options.all_chapters or {}
  self.preload_count = options.preload_count or 0
  self.preload_on_progress = options.preload_on_progress or false
  self._last_saved_page = nil
  self._progress_preload_triggered = false
  self._prune_skip = 0

  -- Discard preload jobs from a previous manga so they don't collide with
  -- this manga's chapter IDs.
  local prev = self.chapter
  local new_chapter = options.chapter
  if prev and new_chapter and
     (prev.manga_id ~= new_chapter.manga_id or prev.source_id ~= new_chapter.source_id) then
    self.preload_jobs = {}
  end

  self.chapter = options.chapter
  local c_showing = self.is_showing

  -- move set self.is_showing function Bobo:init call initializeFromReaderUI maybe random call sort
  self.is_showing = true
  if c_showing and ReaderUI.instance ~= nil then
    -- Copy zoom/render settings from the current chapter into the new chapter's
    -- sidecar before switching, so KOReader loads them automatically.
    self:carryOverReaderSettings(options.path)

    local Device = require("device")

    self.is_switching_document = true
    ReaderUI.instance:switchDocument(options.path)

    -- `switchDocument` closes/reopens the document internally, which triggers
    -- `onCloseWidget`. Keep Bobo in "showing" state while that happens.
    UIManager:nextTick(function()
      self.is_switching_document = false
      -- Double nextTick lets KOReader's document open handler run first.
      -- Reset to preferred portrait rather than carrying the previous chapter's
      -- rotation — the user can re-rotate within the new chapter if needed.
      UIManager:nextTick(function()
        local orientation = G_reader_settings:readSetting("bobo_app_orientation") or "right_hand"
        Device.screen:setRotationMode(orientation == "left_hand" and 2 or 0)
      end)
    end)
  else
    -- Write preferred orientation into the sidecar before KOReader opens the
    -- document for the first time, same as we do in carryOverReaderSettings.
    -- Guard the whole open/save/flush sequence: show() may run inside a
    -- Trapper coroutine where uncaught errors are swallowed silently.
    local orientation = G_reader_settings:readSetting("bobo_app_orientation") or "right_hand"
    local rotation_mode = orientation == "left_hand" and 2 or 0
    local ok, err = pcall(function()
      local init_settings = DocSettings:open(options.path)
      init_settings:saveSetting("rotation_mode", rotation_mode)
      init_settings:flush()
    end)
    if not ok then
      logger.warn("bobo: failed to write orientation to sidecar at", options.path, "-", err)
    end

    -- took this from opds reader
    local Event = require("ui/event")
    UIManager:broadcastEvent(Event:new("SetupShowReader"))

    ReaderUI:showReader(options.path)
  end

  -- re set because hook end book
  self.is_showing = true

  -- Resume to saved page silently — only if past page 1 and not switching docs
  local chapter = options.chapter
  if chapter and chapter.current_page and chapter.current_page > 1 and not c_showing then
    UIManager:nextTick(function()
      if ReaderUI.instance ~= nil then
        local Event = require("ui/event")
        ReaderUI.instance:handleEvent(Event:new("GotoPage", chapter.current_page))
      end
    end)
  end

  -- Kick off background preloading immediately — no UI, no prompts
  if self.preload_count > 0 and chapter then
    self:startPreloading(chapter)
  end

  Testing:emitEvent('manga_reader_shown')
end

--- @param ui unknown The `ReaderUI` instance we're being called from.
function MangaReader:initializeFromReaderUI(ui)
  if self.is_showing then
    ui.menu:registerToMainMenu(MangaReader)
    self:overrideBtnFileManager(ui.menu)

    ui:registerPostInitCallback(function()
      self:hookWithPriorityOntoReaderUiEvents(ui)
    end)
  end
end

--- @private
--- @param ui unknown The currently active `ReaderUI` instance.
function MangaReader:hookWithPriorityOntoReaderUiEvents(ui)
  -- We need to reorder the `ReaderUI` children such that we are the first children,
  -- in order to receive events before all other widgets
  assert(ui.name == "ReaderUI", "expected to be inside ReaderUI")

  local eventListener = WidgetContainer:new({})
  eventListener.onEndOfBook = function()
    -- FIXME this makes `self:onEndOfBook()` get called twice if it does not
    -- return true in the first invocation...
    return self:onEndOfBook()
  end
  eventListener.onCloseWidget = function()
    self:onReaderUiCloseWidget()
  end
  eventListener.onPageUpdate = function(_, new_page)
    self:onPageUpdate(new_page)
  end

  table.insert(ui, 2, eventListener)
end

--- Called on every page turn. Saves position silently — no UI.
--- @private
--- @param new_page number
function MangaReader:onPageUpdate(new_page)
  if not self.is_showing or not self.chapter then return end
  if new_page == self._last_saved_page then return end

  self._last_saved_page = new_page

  local chapter = self.chapter
  local scroll_offset = 0
  if ReaderUI.instance and ReaderUI.instance.rolling then
    scroll_offset = ReaderUI.instance.rolling:getScrollOffset() or 0
  end

  Backend.saveReadingPosition(
    chapter.source_id,
    chapter.manga_id,
    chapter.id,
    new_page,
    scroll_offset
  )

  if self.preload_on_progress and not self._progress_preload_triggered then
    local total_pages = ReaderUI.instance
      and ReaderUI.instance.document
      and ReaderUI.instance.document:getNbPages()
    if total_pages and total_pages > 0 and new_page / total_pages >= 0.8 then
      self._progress_preload_triggered = true
      -- Preload at least 1 chapter regardless of preload_count setting.
      self:startPreloading(chapter, math.max(1, self.preload_count))
    end
  end

  -- Throttle: poll the backend at most every 5 page turns to avoid hammering
  -- the Unix socket on fast page flips.
  if self._prune_skip > 0 then
    self._prune_skip = self._prune_skip - 1
  else
    self:prunePreloadJobs()
    self._prune_skip = 4
  end
end

--- Silently downloads the next N chapters in the background.
--- No progress UI is shown — jobs run as fire-and-forget.
--- @private
--- @param current_chapter Chapter
--- @param count number? Chapters to preload; defaults to self.preload_count.
function MangaReader:startPreloading(current_chapter, count)
  count = count or self.preload_count
  local chapter = current_chapter
  for _ = 1, count do
    local next = findNextChapter(self.all_chapters, chapter)
    if next == nil then break end

    if next.downloaded or next.locked then
      chapter = next
    else
      if self.preload_jobs[next.id] == nil then
        local job = DownloadChapter:new(next.source_id, next.manga_id, next.id, next.chapter_num)
        local result = job:start()
        if result.type ~= 'ERROR' then
          self.preload_jobs[next.id] = job
        end
      end
      chapter = next
    end
  end
end

--- Copies zoom and render settings from the currently open document's sidecar
--- into the new chapter's sidecar so KOReader loads them on open.
--- Only runs when switching between chapters (not on first open).
--- @private
--- @param new_path string Path to the incoming chapter file.
function MangaReader:carryOverReaderSettings(new_path)
  if ReaderUI.instance == nil then return end
  local current_path = ReaderUI.instance.document and ReaderUI.instance.document.file
  if not current_path or current_path == new_path then return end

  -- Read from the live in-memory settings rather than reopening the sidecar from
  -- disk. KOReader flushes doc_settings lazily, so a rotation or zoom change made
  -- while reading may not be on disk yet when we call switchDocument.
  local live_settings = ReaderUI.instance.doc_settings
  if live_settings == nil then return end

  local ok2, new_settings = pcall(DocSettings.open, DocSettings, new_path)
  if not ok2 or not new_settings then return end

  local copied = 0
  for _, key in ipairs(CARRY_KEYS) do
    local value = live_settings:readSetting(key)
    if value ~= nil then
      new_settings:saveSetting(key, value)
      copied = copied + 1
    end
  end

  if copied > 0 then
    new_settings:flush()
    logger.info("bobo: carried", copied, "reader settings to new chapter")
  end

  -- Write the preferred portrait orientation directly into the new chapter's
  -- sidecar so KOReader loads it correctly when the document opens — avoids
  -- any timing race between our nextTick and KOReader's sidecar-apply pass.
  -- Guarded: this runs on chapter advance from Trapper-wrapped paths, where
  -- an uncaught error in saveSetting/flush would be swallowed silently.
  local orientation = G_reader_settings:readSetting("bobo_app_orientation") or "right_hand"
  local rotation_mode = orientation == "left_hand" and 2 or 0
  local ok3, err = pcall(function()
    new_settings:saveSetting("rotation_mode", rotation_mode)
    new_settings:flush()
  end)
  if not ok3 then
    logger.warn("bobo: failed to write orientation to new sidecar at", new_path, "-", err)
  end
end

--- Cleans up finished preload jobs and marks chapters as downloaded in all_chapters.
--- @private
function MangaReader:prunePreloadJobs()
  for chapter_id, job in pairs(self.preload_jobs) do
    local status = job:poll()
    if status.type == 'SUCCESS' then
      -- Mark downloaded but keep the job object in the table.
      -- onEndOfBookCallback needs to reuse the cached result; if we nil it out here
      -- the job is garbage-collected before the end-of-book handler runs.
      for _, ch in ipairs(self.all_chapters) do
        if ch.id == chapter_id then
          ch.downloaded = true
          break
        end
      end
    elseif status.type == 'ERROR' then
      self.preload_jobs[chapter_id] = nil
    end
  end
end

--- Used to add the "Go back to Bobo" menu item. Is called from `ReaderUI`, via the
--- `registerToMainMenu` call done in `initializeFromReaderUI`.
--- @private
function MangaReader:addToMainMenu(menu_items)
  menu_items.go_back_to_bobo = {
    text = _("Go back to Bobo..."),
    sorting_hint = "main",
    callback = function()
      self:onReturn()
    end
  }
end

--- @private
function MangaReader:onReturn()
  self:closeReaderUi(function()
    self.on_return_callback()
  end)
end

function MangaReader:closeReaderUi(done_callback)
  -- Let all event handlers run before closing the ReaderUI, because
  -- some stuff might break if we just remove it ASAP
  UIManager:nextTick(function()
    local FileManager = require("apps/filemanager/filemanager")

    -- we **have** to reopen the `FileManager`, because
    -- apparently this is the only way to get out of the `ReaderUI` without shit
    -- completely breaking (koreader really does not like when there's no `ReaderUI`
    -- nor `FileManager`)
    if ReaderUI.instance ~= nil then
      ReaderUI.instance:onClose()
    end

    -- Reset to the user's preferred portrait orientation before handing back
    -- control. The reader may have been rotated for two-page panels.
    local Device = require("device")
    local orientation = G_reader_settings:readSetting("bobo_app_orientation") or "right_hand"
    Device.screen:setRotationMode(orientation == "left_hand" and 2 or 0)

    if FileManager.instance ~= nil then
      FileManager.instance:reinit()
    else
      FileManager:showFiles()
    end

    (done_callback or function() end)()
  end)
end

--- To be called when the last page of the manga is read.
function MangaReader:onEndOfBook()
  if self.is_showing then
    logger.info("Got end of book")

    -- Trigger another preload pass — the next chapter may now be in range
    if self.preload_count > 0 and self.chapter then
      self:startPreloading(self.chapter)
    end

    self.on_end_of_book_callback()
    return true
  end
end

--- @private
function MangaReader:onReaderUiCloseWidget()
  if self.is_switching_document then
    return
  end

  if self.on_close_book_callback ~= nil then
    self.on_close_book_callback(self.chapter)
  end

  self.is_showing = false
end

--- @private
function MangaReader:overrideBtnFileManager(menu)
  local old_callback = menu.menu_items.filemanager.callback

  if self.is_showing then
    menu.menu_items.filemanager.callback = function()
      local key = "allow_commaneer_filemanager"
      if G_reader_settings:nilOrFalse(key) then
        local confirm_dialog
        confirm_dialog = ConfirmBox:new {
          text = "どーも" .. "\n" .. _("Do you want Bobo to commandeer this button when you open it?") .. "\n\n" .. _("This setting only affects when you open it with Bobo."),
          dismissable = false,
          ok_text = _("Yes"),
          cancel_text = _("No"),
          ok_callback = function()
            UIManager:close(confirm_dialog)

            G_reader_settings:saveSetting(key, true)
            self:onReturn()
          end,
          cancel_callback = function()
            UIManager:close(confirm_dialog)

            old_callback()
          end
        }

        UIManager:show(confirm_dialog)
      else
        self:onReturn()
      end
    end
  end
end

return MangaReader
