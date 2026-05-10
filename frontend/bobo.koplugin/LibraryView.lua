-- FIXME make class names have _some_ kind of logic
local ConfirmBox = require("ui/widget/confirmbox")
local ffiutil = require("ffi/util")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Trapper = require("ui/trapper")
local _ = require("gettext+")
local Icons = require("Icons")
local ButtonDialog = require("ui/widget/buttondialog")
local InstalledSourcesListing = require("InstalledSourcesListing")
local IconButton = require("ui/widget/iconbutton")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Button = require("ui/widget/button")
local Font = require("ui/font")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local InfoMessage = require("ui/widget/infomessage")
local addToPlaylist = require("handlers/addToPlaylist")

local Backend = require("Backend")
local ErrorDialog = require("ErrorDialog")
local ChapterListing = require("ChapterListing")
local MangaSearchResults = require("MangaSearchResults")
local Menu = require("widgets/Menu")
local Settings = require("Settings")
local Testing = require("testing")
local UpdateChecker = require("UpdateChecker")
local calcLastReadText = require("utils/calcLastReadText")
local findEntries = require("utils/findEntries")
local findLastRead = require("utils/findLastRead")
local getChapterDisplayName = require("utils/getChapterDisplayName")
local filterChaptersByLang = require("utils/filterChaptersByLang")
local md5 = require("ffi/sha2").md5
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local NotificationView = require("NotificationView")
local RadioButtonWidget = require("ui/widget/radiobuttonwidget")

local LoadingDialog = require("LoadingDialog")
local MangaInfoWidget = require("MangaInfoWidget")
local CheckboxDialog = require("CheckboxDialog")

local RefreshLibraryChapters = require("jobs/RefreshLibraryChapters")
local RefreshLibraryDetails = require("jobs/RefreshLibraryDetails")
local BasicJobDialog = require("BasicJobDialog")

local MenuItemCover = require("patch/MenuItemCover")
local MenuItemGrid = require("patch/MenuItemGrid")
local MenuCustom = require("patch/MenuCustom")
local PlaylistDialog = require("PlaylistDialog")
local ActionBar = require("widgets/ActionBar")

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")
local SMALL_FONT_FACE = Font:getFace("smallffont")
local LibraryView = MenuCustom:extend {
  name = "library_view",
  is_enable_shortcut = false,
  is_popout = false,
  title = _("Library"),
  with_context_menu = true,

  -- list of mangas in your library
  mangas = nil,
}

function LibraryView:init()
  self.mangas = self.mangas or {}
  self.title_bar_left_icon = "appbar.menu"
  self.onLeftButtonTap = function()
    self:openMenu()
  end
  self.width = Screen:getWidth()
  self.height = Screen:getHeight()

  if self.current_playlist then
    self.title = self.current_playlist.name
  end
  local page = self.page
  Menu.init(self)
  MenuCustom.init(self)
  self.page = page

  self.mangas_raw = self.mangas
  self.favorite_search_keyword = nil
  -- self.current_playlist = nil

  self:patchTitleBar(0)
  self:fetchCountNotification()
  self:_installActionBar()

  -- fix bottom bar size
  self:updateItems()
end

--- @private
--- Replace KOReader's pagination chevron row with a persistent action bar
--- (Search · Playlists · View · Refresh · Settings · More · Close) plus a
--- small "Page X of Y" label below. Sort moved into the More overflow per
--- user feedback ("I don't need filter that quickly accessible"). The top
--- bar's hamburger / bell / close also collapsed down here so the page is
--- one consistent interaction zone.
function LibraryView:_installActionBar()
  local action_bar = ActionBar:new {
    width = Screen:getWidth(),
    show_parent = self,
    actions = {
      {
        glyph = Icons.FA_MAGNIFYING_GLASS,
        label = _("Search"),
        callback = function() self:openSearchMangasDialog() end,
      },
      {
        glyph = Icons.FA_LIST,
        label = _("Playlists"),
        callback = function() self:openPlaylistDialog() end,
      },
      {
        glyph = Icons.FA_TH_LARGE,
        label = _("View"),
        callback = function() self:_cycleViewMode() end,
      },
      {
        glyph = Icons.REFRESHING,
        label = _("Refresh"),
        callback = function() self:refreshAllChapters() end,
      },
      {
        glyph = Icons.FA_GEAR,
        label = _("Settings"),
        callback = function() self:openSettings() end,
      },
      {
        glyph = Icons.FA_ELLIPSIS_VERTICAL,
        label = _("More"),
        callback = function() self:openMenu() end,
      },
      {
        glyph = Icons.FA_REMOVE,
        label = _("Close"),
        callback = function() self:onClose() end,
      },
    },
  }

  -- Mutate self.page_info IN PLACE rather than reassigning. KOReader's
  -- BaseMenu builds its content widget tree referencing the original
  -- self.page_info widget object directly; a plain `self.page_info = X`
  -- doesn't propagate to that tree, so the chevron row keeps painting.
  -- Wipe the HorizontalGroup's existing children, then push a single
  -- VerticalGroup that stacks [action_bar, gap, page_info_text].
  --
  -- KOReader's BaseMenu:_recalculateDimen reserves bottom space using
  -- ONLY page_info_text:getSize().h — it does NOT consult the parent
  -- HorizontalGroup. Without intervention the items area extends behind
  -- the action bar and the bottom row of mangas catches taps meant for
  -- the bar. Wrap page_info_text in a thin proxy that reports the
  -- combined height (action bar + gap + original text) so BaseMenu
  -- carves out the correct amount of room. setText still goes to the
  -- real Button so updatePageInfo's text update keeps working.
  local page_info = self.page_info
  if not page_info or not self.page_info_text then return end
  local original_text = self._action_bar_original_text or self.page_info_text
  self._action_bar_original_text = original_text

  local action_bar_h = action_bar:getSize().h + Screen:scaleBySize(2)
  self.page_info_text = setmetatable({
    _inner = original_text,
    _extra_h = action_bar_h,
    setText = function(self_, ...) return self_._inner:setText(...) end,
    getSize = function(self_)
      local s = self_._inner:getSize()
      return { w = s.w, h = s.h + self_._extra_h }
    end,
    paintTo = function(self_, bb, x, y) return self_._inner:paintTo(bb, x, y) end,
  }, {
    -- Forward unrecognised methods/fields (BaseMenu may poke at .dimen,
    -- :setEnabled, etc.) to the underlying Button so we don't break any
    -- of its internal bookkeeping.
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
    original_text,
  })
end

--- Re-install the action bar after the parent class rebuilds page_info.
---
--- Why this exists:
---   widgets/Menu.lua's updateOfflineSubtitle calls BaseMenu.init(self)
---   whenever the network state changes (it's called from
---   onNetworkConnected / onNetworkDisconnected, plus once during the
---   initial Menu:init with skip_reinit=true). BaseMenu.init constructs
---   self.page_info from scratch as the original
---   [<<, <, Page X of Y, >, >>] chevron HorizontalGroup. That silently
---   wipes the VerticalGroup [ActionBar, gap, page_info_text] that
---   _installActionBar swapped in during LibraryView:init.
---
---   Concretely: if WiFi finishes connecting AFTER the Library view is
---   shown (very common — the connect event lands a few hundred ms
---   later), onNetworkConnected fires, which calls
---   updateOfflineSubtitle(false), which calls BaseMenu.init, which
---   replaces self.page_info — and the user sees the chevron pagination
---   row instead of the action bar.
---
--- The fix:
---   Override updateOfflineSubtitle so that any time the parent
---   re-runs BaseMenu.init we immediately re-run _installActionBar to
---   put our row back. Two guards:
---     - skip_reinit=true: the parent skipped BaseMenu.init, so
---       page_info wasn't rebuilt and there's nothing to re-do. The
---       initial Menu:init() call always uses skip_reinit=true; the
---       later network-event calls always use skip_reinit=false.
---     - page_info_text == nil: BaseMenu.init hasn't completed even
---       once yet, so there's no page_info_text to wrap. Bail out
---       and let the explicit _installActionBar in init() handle it.
function LibraryView:updateOfflineSubtitle(skip_reinit)
  Menu.updateOfflineSubtitle(self, skip_reinit)
  if not skip_reinit and self.page_info_text then
    self:_installActionBar()
  end
end

--- @private
--- Cycle library_view_mode through grid → cover → base → grid.
function LibraryView:_cycleViewMode()
  Trapper:wrap(function()
    local response = Backend.getSettings()
    if response.type == 'ERROR' then
      ErrorDialog:show(response.message)
      return
    end
    local settings = response.body
    local current = settings.library_view_mode or "cover"
    local next_mode = ({ grid = "cover", cover = "base", base = "grid" })[current] or "grid"
    settings.library_view_mode = next_mode

    local set_response = Backend.setSettings(settings)
    if set_response.type == 'ERROR' then
      ErrorDialog:show(set_response.message)
      return
    end

    self.library_view_mode = next_mode
    self:updateItems()
  end)
end

--- @private
--- @param cleanup boolean|nil
function LibraryView:fetchMangas(cleanup)
  local response
  if self.current_playlist then
    response = Backend.getMangasInPlaylist(self.current_playlist.id)
  else
    response = Backend.getMangasInLibrary()
  end

  if response.type == 'ERROR' then
    ErrorDialog:show(response.message, cleanup and function()
      Backend.cleanup()
      Backend.initialize()
    end or nil)
    return nil
  end

  return response.body
end

--- @private
--- @return LibraryViewMode
function LibraryView:getLibraryViewMode()
  return self.library_view_mode
end

--- @private
function LibraryView:fetchCountNotification()
  local response = Backend.getCountNotification()
  if response.type == 'ERROR' then
    ErrorDialog:show(response.message)

    return
  end

  local count_notify = response.body
  self:patchTitleBar(count_notify)

  UIManager:setDirty(self.show_parent, "ui", self.dimen)
end

--- @private
--- @param count_notify number
--- The title bar is now title-only — every action that lived here (menu
--- overflow, notification bell, close) moved into the bottom action bar
--- so the user has one consistent interaction zone. Notification count is
--- stashed for the Notifications entry inside the More menu.
function LibraryView:patchTitleBar(count_notify)
  self._notify_count = count_notify or 0

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
function LibraryView:updateItems()
  if #self.mangas > 0 then
    self.item_table = self:generateItemTableFromMangas(self.mangas)
    self.multilines_show_more_text = false
    self.items_per_page = nil
  else
    self.item_table = self:generateEmptyViewItemTable()
    self.multilines_show_more_text = true
    self.items_per_page = 1
  end

  local mode = self:getLibraryViewMode()
  local MenuItemChoice = MenuItemCover
  if mode == "grid" then
    MenuItemChoice = MenuItemGrid
    self.grid_columns = G_reader_settings:readSetting("bobo_grid_columns") or 3
  else
    self.grid_columns = nil
  end

  if mode ~= "base" then
    MenuCustom.updateItems(self, MenuItemChoice)
  else
    Menu.updateItems(self)
  end
end

--- @private
function LibraryView:_recalculateDimen(flag)
  if self:getLibraryViewMode() ~= "base" then
    MenuCustom._recalculateDimen(self, flag)
  else
    Menu._recalculateDimen(self, flag)
  end
end

--- @private
--- @param mangas Manga[]
function LibraryView:generateItemTableFromMangas(mangas)
  local item_table = {}
  local is_cover = self:getLibraryViewMode() == "cover"

  local mode = self:getLibraryViewMode()
  local is_grid = mode == "grid"

  for _, manga in ipairs(mangas) do
    local mandatory = ""

    if is_cover then
      mandatory = manga.source.name
    end

    local space = is_cover and "  " .. Icons.DOT .. "  " or ""

    mandatory = mandatory .. (manga.last_read and space
      .. calcLastReadText(manga.last_read, mode ~= "base") .. (is_cover and "" or " ") or "")

    -- In grid mode the unread count is rendered as a corner badge over the
    -- cover, so don't duplicate it in the metadata line.
    if not is_grid and manga.unread_chapters_count ~= nil and manga.unread_chapters_count > 0 then
      if is_cover then
        mandatory = mandatory .. space .. Icons.FA_BELL .. " " .. manga.unread_chapters_count
      else
        mandatory = mandatory .. Icons.FA_BELL .. manga.unread_chapters_count
      end
    end

    table.insert(item_table, {
      manga = manga,
      text = manga.title,
      post_text = mode == "cover" and mandatory or manga.source.name,
      manga_cover = manga.manga_cover,
      mandatory = mode ~= "cover" and mandatory or nil,
    })
  end

  return item_table
end

--- @private
function LibraryView:generateEmptyViewItemTable()
  return {
    {
      text = _("No mangas found in library") .. ". " .. _("Try adding some by holding their name on the search results!"),
      dim = true,
      select_enabled = false,
    }
  }
end

function LibraryView:fetchAndShow(playlist, on_after_open)
  local old = self.current_playlist
  self.current_playlist = playlist
  local settings = Backend.getSettings()

  if settings.type == 'ERROR' then
    ErrorDialog:show(settings.message, function()
      Backend.cleanup()
      Backend.initialize()
    end)

    return
  end

  local mangas = self:fetchMangas(true)
  if not mangas then
    return
  end

  UIManager:show(LibraryView:new {
    mangas = mangas,
    covers_fullscreen = true, -- hint for UIManager:_repaint()
    page = self.page,
    library_view_mode = settings.body.library_view_mode,
    current_playlist = self.current_playlist,
    -- KOReader's BaseMenu rotation handler is a no-op without
    -- `_recreate_func`. Provide one so the library re-fetches and
    -- re-renders for the new orientation when the device rotates.
    _recreate_func = function()
      self:fetchAndShow(playlist, on_after_open)
    end,
  })

  self.current_playlist = old
  if on_after_open then
    on_after_open()
  end

  Testing:emitEvent('library_view_shown')
end

--- Tapping a cover jumps straight into the continue-reading flow.
--- The full chapter list is reachable via the context menu's
--- "View All Chapters" entry.
--- @private
function LibraryView:onPrimaryMenuChoice(item)
  --- @type Manga
  local manga = item.manga
  if manga == nil then
    return
  end
  self:_handleContinueReading(manga)
end

--- Opens the chapter listing for `manga`. Used by the context-menu
--- "View All Chapters" button (and previously by cover taps).
--- @private
--- @param manga Manga
function LibraryView:_handleViewAllChapters(manga)
  Trapper:wrap(function()
    local onReturnCallback = function()
      self:fetchAndShow(self.current_playlist)
    end

    if ChapterListing:fetchAndShow(manga, onReturnCallback, true) then
      self:onClose()
    end
  end)
end

--- @private
function LibraryView:onContextMenuChoice(item)
  --- @type Manga
  local manga = item.manga
  if manga == nil then
    return
  end
  local dialog_context_menu

  local context_menu_buttons = {
    {
      {
        text = Icons.REFRESHING .. " " .. _("Refresh"),
        callback = function()
          UIManager:close(dialog_context_menu)
          local response = self:_refreshManga(Backend.createCancelId(), manga)

          if response.type == 'ERROR' then
            UIManager:show(InfoMessage:new {
              text = response.message
            })
          else
            UIManager:show(InfoMessage:new {
              text = _("Refreshed manga")
            })
          end

          self:fetchAndShow(self.current_playlist)
          UIManager:close(self)
        end
      },
      {
        text = Icons.INFO .. " " .. _("Details"),
        callback = function()
          UIManager:close(dialog_context_menu)

          Trapper:wrap(function()
            local onReturnCallback = function()
              self:fetchAndShow(self.current_playlist)
            end
            MangaInfoWidget:fetchAndShow(manga, onReturnCallback)
            UIManager:close(self)
          end)
        end
      }
    },
    {
      {
        text = Icons.CHECK_ALL .. " " .. _("Mark read"),
        callback = function()
          UIManager:close(dialog_context_menu)

          ChapterListing:openMarkDialog(manga, true, function(count)
            manga.unread_chapters_count = count
            self:updateItems()
          end)
        end
      },
      {
        text = Icons.CHECK_ALL .. " " .. _("Mark unread"),
        callback = function()
          UIManager:close(dialog_context_menu)

          ChapterListing:openMarkDialog(manga, false, function(count)
            manga.unread_chapters_count = count
            self:updateItems()
          end)
        end
      }
    },
    {
      {
        text = _("View All Chapters"),
        callback = function()
          UIManager:close(dialog_context_menu)
          self:_handleViewAllChapters(manga)
        end,
      },
    },
    {
      {
        text = Icons.FA_PLUS .. " " .. _("Add to Playlist"),
        callback = function()
          UIManager:close(dialog_context_menu)
          addToPlaylist(manga)
        end,
      },
    },
  }
  if self.current_playlist == nil then
    table.insert(context_menu_buttons, {
      {
        text = _("Remove from Library"),
        callback = function()
          UIManager:close(dialog_context_menu)
          self:_handleRemoveFromLibrary(manga)
        end,
      },
    })
  else
    table.insert(context_menu_buttons, {
      {
        text = _("Remove from Playlist"),
        callback = function()
          UIManager:close(dialog_context_menu)
          self:_handleRemoveFromPlaylist(manga)
        end,
      },
    })
  end
  dialog_context_menu = ButtonDialog:new {
    title = manga.title .. "\n\n" .. manga.source.name,
    buttons = context_menu_buttons,
  }
  UIManager:show(dialog_context_menu)
end

--- @private
function LibraryView:onSwipe(arg, ges_ev)
  local BD = require("ui/bidi")
  local direction = BD.flipDirectionIfMirroredUILayout(ges_ev.direction)
  if direction == "south" then
    self:refreshAllChapters()

    return
  end

  Menu.onSwipe(self, arg, ges_ev)
end

--- Handles "Continue Reading" action
--- @private
--- @param manga Manga
function LibraryView:_handleContinueReading(manga)
  Trapper:wrap(function()
    local response = LoadingDialog:showAndRun(_("Finding next chapter..."), function()
      return Backend.listCachedChapters(manga.source.id, manga.id)
    end)

    if response.type == 'ERROR' then
      ErrorDialog:show(response.message)
      return
    end

    local chapter_results = response.body
    if #chapter_results == 0 then
      ErrorDialog:show(_("No chapters found for this manga."))
      return
    end

    local langs_set = {}
    local langs_list = {}
    for _, chapter in ipairs(chapter_results) do
      local lang = chapter.lang or "unknown"
      if not langs_set[lang] then
        langs_set[lang] = true
        table.insert(langs_list, lang)
      end
    end

    local chapters
    -- Load / initialize language preferences only when it matters (2+ langs)
    if #langs_list >= 2 then
      table.sort(langs_list)

      local key = md5(manga.source.id .. "/" .. manga.id) .. "_lang"
      local langs_selected = LuaSettings:open(DataStorage:getSettingsDir() .. "/bobo_lang.lua"):readSetting(key, {})
      -- If no preferences are set, default to selecting all available languages
      if not langs_selected or #langs_selected == 0 then
        langs_selected = langs_list
      end

      chapters = filterChaptersByLang(chapter_results, langs_selected)
    else
      chapters = chapter_results
    end

    local chapter_to_open = findLastRead(chapters)
    if not chapter_to_open then
      UIManager:show(InfoMessage:new { text = _("Sadly, no next chapter available! :c") })
      return
    end

    local confirm_dialog
    confirm_dialog = ConfirmBox:new {
      text = _("Resume reading with:") .. "\n" .. getChapterDisplayName(chapter_to_open) .. "?",
      ok_text = _("Read"),
      cancel_text = _("Cancel"),
      ok_callback = function()
        UIManager:close(confirm_dialog)

        local response = Backend.getSettings()
        if response.type == 'ERROR' then
          ErrorDialog:show(response.message)

          return
        end

        local settings = response.body

        local temp_listing = ChapterListing:new {
          manga = manga,
          chapter_sorting_mode = settings.chapter_sorting_mode,
          on_return_callback = function()
            self:fetchAndShow(self.current_playlist)
          end,
          covers_fullscreen = true, -- hint for UIManager:_repaint()
          page = self.page,
          preload_count = settings.preload_chapters
        }
        temp_listing.chapters = chapters
        temp_listing:openChapterOnReader(chapter_to_open)
        self:onClose()
      end,
      cancel_callback = function()
        UIManager:close(confirm_dialog)
      end
    }
    UIManager:show(confirm_dialog)
  end)
end

--- @private
function LibraryView:_handleRemoveFromLibrary(manga)
  UIManager:show(ConfirmBox:new {
    text = _("Do you want to remove") .. "\" " .. manga.title .. "\" " .. _("from your library?"),
    ok_text = _("Remove"),
    ok_callback = function()
      local response = Backend.removeMangaFromLibrary(manga.source.id, manga.id)

      if response.type == 'ERROR' then
        ErrorDialog:show(response.message)

        return
      end
      self:fetchAndShow(self.current_playlist)
      self:onClose()
    end
  })
end

---@private
---@param manga Manga
function LibraryView:_handleRemoveFromPlaylist(manga)
  UIManager:show(ConfirmBox:new {
    text = _("Do you want to remove") .. "\" " .. manga.title .. "\" " .. _("from your playlist?"),
    ok_text = _("Remove"),
    ok_callback = function()
      local response = Backend.removeMangaFromPlaylist(self.current_playlist.id, manga.source.id, manga.id)

      if response.type == 'ERROR' then
        ErrorDialog:show(response.message)

        return
      end
      self:fetchAndShow(self.current_playlist)
      self:onClose()
    end
  })
end

--- @private
function LibraryView:openSortDialog()
  Trapper:wrap(function()
    local response = Backend.getSettings()
    if response.type == 'ERROR' then
      ErrorDialog:show(response.message)
      return
    end

    local settings = response.body

    local key = "library_sorting_mode"
    local tuple = findEntries(Settings.setting_value_definitions, key)

    local radio_buttons = {}
    for _, option in ipairs(tuple.options) do
      table.insert(radio_buttons, {
        {
          text = option.label,
          provider = option.value,
          checked = settings[key] == option.value,
        },
      })
    end

    local dialog
    dialog = RadioButtonWidget:new {
      title_text = tuple.title,
      radio_buttons = radio_buttons,
      callback = function(radio)
        UIManager:close(dialog)

        settings[key] = radio.provider

        local set_response = Backend.setSettings(settings)
        if set_response.type == 'ERROR' then
          ErrorDialog:show(set_response.message)
          return
        end

        local mangas = self:fetchMangas()
        if not mangas then
          return
        end

        self.mangas_raw = mangas
        self.favorite_search_keyword = nil
        self.mangas = mangas

        self:updateItems()

        UIManager:show(dialog)
      end
    }

    UIManager:show(dialog)
  end)
end

--- @private
--- The "More" overflow opened from the bottom action bar. Search for
--- mangas, Playlists, Refresh mangas, and Settings live in the bar
--- itself; this dialog only carries the secondary actions, plus
--- Notifications (with current unread count) and the items that didn't
--- earn a dedicated cell (Sort by, Search favorites, Refresh details,
--- Cleaner, Manage sources, Check for updates, Sync Database).
function LibraryView:openMenu()
  local dialog
  local notify_count = self._notify_count or 0
  local notify_label = notify_count > 0
    and (_("Notifications") .. " (" .. notify_count .. ")")
    or _("Notifications")

  local buttons = {
    {
      {
        text = Icons.FA_BELL .. " " .. notify_label,
        callback = function()
          UIManager:close(dialog)
          Trapper:wrap(function()
            local onReturnCallback = function()
              self:fetchAndShow(self.current_playlist)
            end
            NotificationView:fetchAndShow(onReturnCallback)
            self:onClose()
          end)
        end
      },
    },
    {
      {
        text = Icons.FA_FILTER .. " " .. _("Sort by..."),
        callback = function()
          UIManager:close(dialog)
          self:openSortDialog()
        end
      },
      {
        text = "\u{E644}" .. " " .. _("Search favorites"),
        callback = function()
          UIManager:close(dialog)
          self:openSearchFavoritesDialog()
        end
      },
    },
    {
      {
        text = Icons.REFRESHING .. " " .. _("Refresh details"),
        callback = function()
          UIManager:close(dialog)
          self:refreshAllDetails()
        end
      },
      {
        text = "\u{e000}" .. " " .. _("Cleaner chapters"),
        callback = function()
          UIManager:close(dialog)
          self:openCleanerDialog()
        end
      },
    },
    {
      {
        text = Icons.FA_PLUG .. " " .. _("Manage sources"),
        callback = function()
          UIManager:close(dialog)
          self:openInstalledSourcesListing()
        end
      },
      {
        text = Icons.FA_ARROW_UP .. " " .. _("Check for updates"),
        callback = function()
          UIManager:close(dialog)
          UpdateChecker:checkForUpdates()
        end
      },
    },
    { {
      text = Icons.SYNC .. " " .. _("Sync Database (Beta)"),
      callback = function()
        Trapper:wrap(function()
          local response = LoadingDialog:showAndRun(
            _("Sync to WebDAV..."),
            function() return Backend.syncDatabase(false, false) end
          )

          if response.type == 'ERROR' then
            ErrorDialog:show(response.message)

            return
          end

          if response.body == 'update_required' then
            UIManager:show(ConfirmBox:new {
              text = _("The remote database is newer than the local one.") .. "\n" .. _("Do you want to migrate your local database from the server?") .. "\n\n" .. _("This action cannot be undone."),
              ok_text = _("Migrate"),
              ok_callback = function()
                Trapper:wrap(function()
                  local response = LoadingDialog:showAndRun(
                    _("Migrating database..."),
                    function() return Backend.syncDatabase(true, false) end
                  )

                  if response.type == 'ERROR' then
                    ErrorDialog:show(response.message)

                    return
                  end

                  UIManager:show(InfoMessage:new {
                    text = _("Local database has been migrated from the server!")
                  })

                  UIManager:close(self)
                  UIManager:close(dialog)
                  self:fetchAndShow(self.current_playlist)
                end)
              end,
              other_buttons = {
                {
                  {
                    text = _("Replace Cloud"),
                    callback = function()
                      Trapper:wrap(function()
                        local response = LoadingDialog:showAndRun(
                          _("Replacing cloud..."),
                          function() return Backend.syncDatabase(false, true) end
                        )
                        if response.type == 'ERROR' then
                          ErrorDialog:show(response.message)

                          return
                        end

                        UIManager:show(InfoMessage:new {
                          text = _("Cloud database has been forcedly replaced with local one!")
                        })

                        UIManager:close(self)
                        UIManager:close(dialog)
                        self:fetchAndShow(self.current_playlist)
                      end)
                    end,
                  }
                }
              }
            })

            return
          end

          local msg = '';
          if response.body == 'up_to_date' then
            msg = _("Database is already up to date!")
          elseif response.body == 'updated_to_server' then
            msg = _("Database has been synced to the server!")
          elseif response.body == 'updated' then
            msg = _("Local database has been migrated from the server!")
          else
            msg = _("Sync completed!")
          end

          UIManager:show(InfoMessage:new {
            text = msg
          })
        end)
      end
    } }
  }

  dialog = ButtonDialog:new {
    buttons = buttons,
  }

  UIManager:show(dialog)

  Testing:emitEvent('library_view_menu_opened')
end

---@private
function LibraryView:openPlaylistDialog()
  PlaylistDialog:fetchAndShow(function(playlist)
    local need_close = self.current_playlist ~= nil
    LibraryView:fetchAndShow(playlist, function()
      if need_close then
        self:onClose()
      end
    end)
  end)
end

--- @private
function LibraryView:openSearchMangasDialog()
  local dialog
  dialog = InputDialog:new {
    title = _("Manga search..."),
    input_hint = _("Houseki no Kuni"),
    description = _("Type the manga name to search for"),
    buttons = {
      {
        {
          text = _("Search"),
          is_enter_default = false,
          callback = function()
            UIManager:close(dialog)

            self:searchMangas(dialog:getInputText())
          end,
        },
        {
          text = _("Search") .. "*",
          is_enter_default = true,
          callback = function()
            UIManager:close(dialog)

            self:searchMangas(dialog:getInputText(), G_reader_settings:readSetting(
              "exlucde_source_ids_select_search", {}
            ))
          end,
        },
      },
      {
        {
          text = _("Settings"),
          callback = function()
            self:openSettingsSearchDialog()
          end
        },
        {
          text = _("Cancel"),
          id = "close",
          callback = function()
            UIManager:close(dialog)
          end,
        },
      }
    }
  }

  UIManager:show(dialog)
  dialog:onShowKeyboard()
end

--- @private
function LibraryView:openSettingsSearchDialog()
  local response = Backend.listInstalledSources()
  if response.type == 'ERROR' then
    ErrorDialog:show(response.message)

    return
  end

  local key = "exlucde_source_ids_select_search"
  ---@diagnostic disable-next-line: redundant-parameter
  local dialog = CheckboxDialog:new {
    title = _("Exclude source search for") .. " \"" .. _("Search") .. "*\"",
    current = G_reader_settings:readSetting(key, {}),
    options = response.body,
    update_callback = function(value)
      G_reader_settings:saveSetting(key, value)
    end
  }

  UIManager:show(dialog)
end

--- @private
function LibraryView:openSearchFavoritesDialog()
  local dialog
  dialog = InputDialog:new {
    title = _("Favorite search..."),
    input = self.favorite_search_keyword,
    input_hint = _("Tonikaku Kawaii"),
    description = _("Type the manga name to search for"),
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
          text = _("Search"),
          is_enter_default = true,
          callback = function()
            UIManager:close(dialog)

            local query = dialog:getInputText()

            query = query and query:match("^%s*(.-)%s*$"):lower()

            local mangas = {}

            if query and query ~= "" then
              for __, manga in ipairs(self.mangas_raw) do
                -- convert manga title to lowercase for comparison
                local title = (manga.title or ""):lower()
                if title:find(query, 1, true) then
                  table.insert(mangas, manga)
                end
              end
            else
              mangas = self.mangas_raw
            end

            self.mangas = mangas
            self.favorite_search_keyword = dialog:getInputText()

            self:updateItems()
          end,
        },
      }
    }
  }

  UIManager:show(dialog)
  dialog:onShowKeyboard()
end

function LibraryView:startCleaner(modeInvalid)
  Trapper:wrap(function()
    local response = LoadingDialog:showAndRun(
      _("Scaning files..."),
      function() return Backend.findOrphanOrReadFiles(modeInvalid) end
    )

    if response.type == 'ERROR' then
      ErrorDialog:show(response.message)

      return
    end

    local filenames = response.body.filenames or {}
    local total_size = response.body.total_text

    local confirm = ConfirmBox:new {
      text = string.format(
        _("Found %d files.") .. "\n\n" ..
        _("Total size %s.") .. "\n\n" ..
        _("RendOnly file .cbz and .epub scan."),
        #filenames,
        total_size
      ),
      ok_text = _("Clean"),
      ok_callback = function()
        local ProgressbarDialog = require("ui/widget/progressbardialog")

        local progressbar_dialog = ProgressbarDialog:new {
          title = _("Deleting..."),
          progress_max = #filenames
        }
        UIManager:show(progressbar_dialog)

        for i, filename in ipairs(filenames) do
          local response = Backend.removeFile(filename)
          if response.type == 'ERROR' then
            ErrorDialog:show(response.message)
            return
          end
          progressbar_dialog:reportProgress(i + 1)
          progressbar_dialog:redrawProgressbarIfNeeded()
        end

        progressbar_dialog:close()

        UIManager:show(InfoMessage:new {
          text = string.format(_("Cleaned free %s storage"), total_size)
        })
      end
    }

    UIManager:show(confirm)
  end
  )
end

--- @private
--- @param cancel_id number
--- @param manga Manga
function LibraryView:_refreshManga(cancel_id, manga)
  local response = Backend.refreshChapters(cancel_id, manga.source.id, manga.id)
  return response
end

--- @private
--- @private
function LibraryView:refreshAllChapters()
  local job = RefreshLibraryChapters:new()
  if job then
    self:_runLibraryJob(
      job,
      _("Refresh mangas..."),
      _("All chapters manga updated!"),
      _("Some manga updates fail:")
    )
  end
end

--- @private
function LibraryView:refreshAllDetails()
  local job = RefreshLibraryDetails:new()
  if job then
    self:_runLibraryJob(
      job,
      _("Refresh manga details..."),
      _("All manga details refresh!"),
      _("Some manga details refresh fail:")
    )
  end
end

--- @private
function LibraryView:_runLibraryJob(job, title, success_msg, error_prefix)
  Trapper:wrap(function()
    local dialog = BasicJobDialog:new({
      show_parent = self,
      job = job,
      title = title,
      success_message = success_msg,
      error_prefix = error_prefix,
      format_progress = function(data)
        if data and data.type == 'REFRESHING' then
          return _("Progress") .. ": " .. (data.current or 0) .. " / " .. (data.total or #self.mangas_raw)
        end
        return nil
      end,
      dismiss_callback = function()
        self:fetchAndShow(self.current_playlist)
        UIManager:close(self)
      end
    })
    dialog:show()
  end)
end

--- @private
function LibraryView:openCleanerDialog()
  local dialog

  dialog = ConfirmBox:new {
    text = _("Cleaner") .. "\n\n" ..
        _("Normal") .. ": " .. _("Find and delete invalid files including files from deleted sources") .. "\n\n" ..
        _("Chapter read done") .. ": " .. _("Find and delete chapters that have been read") .. "\n\n" ..
        _("IMPORTANT: Meta files (bookmark, history) not keep!"),
    ok_text = _("Normal"),
    ok_callback = function()
      self:startCleaner(true)
    end,
    other_buttons = { {
      {
        text = _("Chapter read done"),
        callback = function()
          self:startCleaner(false)
        end
      }
    }
    } }

  UIManager:show(dialog)
end

--- @private
function LibraryView:searchMangas(search_text, exclude)
  Trapper:wrap(function()
    local onReturnCallback = function()
      self:fetchAndShow(self.current_playlist)
    end

    if MangaSearchResults:searchAndShow(search_text, exclude, onReturnCallback) then
      self:onClose()
    end
  end)
end

--- @private
function LibraryView:openInstalledSourcesListing()
  Trapper:wrap(function()
    local onReturnCallback = function()
      self:fetchAndShow(self.current_playlist)
    end

    InstalledSourcesListing:fetchAndShow(onReturnCallback)

    self:onClose()
  end)
end

--- @private
function LibraryView:openSettings()
  Trapper:wrap(function()
    local onReturnCallback = function()
      self:fetchAndShow(self.current_playlist)
    end

    Settings:fetchAndShow(onReturnCallback)

    self:onClose()
  end)
end

return LibraryView
