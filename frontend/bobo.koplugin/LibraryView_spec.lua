---@diagnostic disable: undefined-global, undefined-field

-- Stubs for KOReader / bobo modules LibraryView.lua requires at load time.
-- The goal is just to load the module so we can exercise its callback wiring;
-- we never call init() on a real instance (its parent chain pulls in too much
-- of KOReader). Tests build instances by hand with setmetatable.

local function noop() end

local function stub_class(proto)
  local cls = proto or {}
  cls.__index = cls
  cls.extend = function(self, t)
    local sub = setmetatable(t or {}, { __index = self })
    sub.__index = sub
    sub.extend  = self.extend
    sub.new     = function(_, opts)
      local inst = setmetatable(opts or {}, sub)
      if inst.init then inst:init() end
      return inst
    end
    return sub
  end
  cls.new = function(_, opts)
    local inst = setmetatable(opts or {}, cls)
    if inst.init then inst:init() end
    return inst
  end
  return cls
end

-- Globals LibraryView reads at load time.
_G.G_defaults = { readSetting = function() return 24 end }
_G.G_reader_settings = {
  readSetting = function(_, _key, default) return default end,
  saveSetting = noop,
}

-- Track ButtonDialog instances and ChapterListing calls so tests can inspect
-- what LibraryView actually wired up.
local last_button_dialog = nil
local chapter_listing_calls = {}

local button_dialog_stub = {
  new = function(_, opts)
    last_button_dialog = opts
    return opts
  end,
}

local chapter_listing_stub = {
  fetchAndShow = function(_, manga, on_return, fullscreen)
    table.insert(chapter_listing_calls, {
      manga = manga,
      on_return = on_return,
      fullscreen = fullscreen,
    })
    return true
  end,
  openMarkDialog = noop,
  new = function(_, opts) return opts end,
}

local trapper_stub = {
  -- Run wrapped callbacks synchronously so tests can observe their effects.
  wrap = function(_, fn) fn() end,
}

local uimanager_stub = {
  show     = noop,
  close    = noop,
  setDirty = noop,
  nextTick = function(_, fn) fn() end,
}

local screen_stub = {
  getWidth      = function() return 800 end,
  getHeight     = function() return 600 end,
  scaleBySize   = function(_, n) return n end,
}

-- Modules that LibraryView pulls in. Most are no-ops; only the ones the
-- callback wiring actually exercises need real behaviour.
package.loaded["ui/widget/confirmbox"]        = stub_class()
package.loaded["ffi/util"]                    = {}
package.loaded["ui/widget/inputdialog"]       = stub_class()
package.loaded["ui/uimanager"]                = uimanager_stub
package.loaded["device"]                      = { screen = screen_stub }
package.loaded["ui/trapper"]                  = trapper_stub
package.loaded["gettext+"]                    = function(s) return s end
package.loaded["Icons"]                       = setmetatable({}, { __index = function() return "" end })
package.loaded["ui/widget/buttondialog"]      = button_dialog_stub
package.loaded["InstalledSourcesListing"]     = {}
package.loaded["ui/widget/iconbutton"]        = stub_class()
package.loaded["ui/widget/horizontalgroup"]   = stub_class()
package.loaded["ui/widget/horizontalspan"]    = stub_class()
package.loaded["ui/widget/button"]            = stub_class()
package.loaded["ui/font"]                     = { getFace = function() return {} end }
package.loaded["ui/widget/verticalgroup"]     = stub_class()
package.loaded["ui/widget/verticalspan"]      = stub_class()
package.loaded["ui/widget/infomessage"]       = stub_class()
package.loaded["handlers/addToPlaylist"]      = noop
package.loaded["Backend"]                     = {
  getMangasInLibrary = function() return { type = "SUCCESS", body = {} } end,
  getMangasInPlaylist = function() return { type = "SUCCESS", body = {} } end,
  getCountNotification = function() return { type = "SUCCESS", body = 0 } end,
  getSettings = function() return { type = "SUCCESS", body = {} } end,
  setSettings = function() return { type = "SUCCESS" } end,
  listCachedChapters = function() return { type = "SUCCESS", body = {} } end,
  refreshChapters = function() return { type = "SUCCESS" } end,
  removeMangaFromLibrary = function() return { type = "SUCCESS" } end,
  removeMangaFromPlaylist = function() return { type = "SUCCESS" } end,
  syncDatabase = function() return { type = "SUCCESS", body = "up_to_date" } end,
  findOrphanOrReadFiles = function() return { type = "SUCCESS", body = { filenames = {}, total_text = "" } } end,
  removeFile = function() return { type = "SUCCESS" } end,
  listInstalledSources = function() return { type = "SUCCESS", body = {} } end,
  cleanup = noop,
  initialize = noop,
  createCancelId = function() return 1 end,
}
package.loaded["ErrorDialog"]                 = { show = noop }
package.loaded["ChapterListing"]              = chapter_listing_stub
package.loaded["MangaSearchResults"]          = {}
package.loaded["widgets/Menu"]                = stub_class({ init = noop, updateItems = noop, onSwipe = noop, _recalculateDimen = noop, updateOfflineSubtitle = noop })
package.loaded["Settings"]                    = { setting_value_definitions = {} }
package.loaded["testing"]                     = { emitEvent = noop, init = noop }
package.loaded["UpdateChecker"]               = { checkForUpdates = noop }
package.loaded["utils/calcLastReadText"]      = function() return "" end
package.loaded["utils/findEntries"]           = function() return { title = "", options = {} } end
package.loaded["utils/findLastRead"]          = function() return nil end
package.loaded["utils/getChapterDisplayName"] = function() return "" end
package.loaded["utils/filterChaptersByLang"]  = function(c) return c end
package.loaded["ffi/sha2"]                    = { md5 = function(s) return s end }
package.loaded["datastorage"]                 = { getSettingsDir = function() return "/tmp" end }
package.loaded["luasettings"]                 = { open = function() return { readSetting = function(_, _k, d) return d end, saveSetting = noop } end }
package.loaded["NotificationView"]            = { fetchAndShow = noop }
package.loaded["ui/widget/radiobuttonwidget"] = stub_class()
package.loaded["LoadingDialog"]               = { showAndRun = function(_, _msg, fn) return fn() end }
package.loaded["MangaInfoWidget"]             = { fetchAndShow = noop }
package.loaded["CheckboxDialog"]              = stub_class()
package.loaded["jobs/RefreshLibraryChapters"] = stub_class()
package.loaded["jobs/RefreshLibraryDetails"]  = stub_class()
package.loaded["BasicJobDialog"]              = stub_class()
-- patch/MenuCustom is the parent class. extend() must work so LibraryView's
-- top-level `MenuCustom:extend{}` produces a usable class.
package.loaded["patch/MenuCustom"]            = stub_class({ init = noop, updateItems = noop, _recalculateDimen = noop })
package.loaded["patch/MenuItemCover"]         = stub_class()
package.loaded["patch/MenuItemGrid"]          = stub_class()
package.loaded["PlaylistDialog"]              = { fetchAndShow = noop }
package.loaded["widgets/ActionBar"]           = stub_class()

package.loaded["LibraryView"] = nil
local LibraryView = require("LibraryView")

-- Build a LibraryView instance without running init() — we only want to
-- exercise the dispatch wiring, not the heavy widget construction.
local function make_view()
  local view = setmetatable({
    current_playlist = nil,
    onClose = noop,
    fetchAndShow = noop,
  }, { __index = LibraryView })
  return view
end

local function find_button(button_dialog, label)
  for _, row in ipairs(button_dialog.buttons) do
    for _, btn in ipairs(row) do
      if btn.text == label then return btn end
    end
  end
  return nil
end

describe("LibraryView cover-tap / context-menu wiring", function()
  before_each(function()
    last_button_dialog = nil
    chapter_listing_calls = {}
  end)

  it("cover tap runs the continue-reading flow, not the chapter listing", function()
    local view = make_view()
    local continue_calls = {}
    -- Stub the heavy continue-reading flow on this instance only.
    view._handleContinueReading = function(_, manga)
      table.insert(continue_calls, manga)
    end

    local manga = { id = "m1", title = "Test Manga", source = { id = "src", name = "Source" } }
    view:onPrimaryMenuChoice({ manga = manga })

    assert.equal(1, #continue_calls)
    assert.equal(manga, continue_calls[1])
    assert.equal(0, #chapter_listing_calls,
      "cover tap must no longer open the chapter listing directly")
  end)

  it("cover tap is a no-op when the item has no manga (empty-library row)", function()
    local view = make_view()
    local continue_calls = 0
    view._handleContinueReading = function() continue_calls = continue_calls + 1 end

    view:onPrimaryMenuChoice({})

    assert.equal(0, continue_calls)
  end)

  it("context menu offers View All Chapters (not Continue Reading) and it opens the chapter listing", function()
    local view = make_view()

    local manga = { id = "m1", title = "Test Manga", source = { id = "src", name = "Source" } }
    view:onContextMenuChoice({ manga = manga })

    assert.is_not_nil(last_button_dialog, "context menu must open a ButtonDialog")
    assert.is_nil(find_button(last_button_dialog, "Continue Reading"),
      "old Continue Reading button must be gone")
    local view_all = find_button(last_button_dialog, "View All Chapters")
    assert.is_not_nil(view_all, "context menu must include View All Chapters")

    view_all.callback()

    assert.equal(1, #chapter_listing_calls)
    assert.equal(manga, chapter_listing_calls[1].manga)
    assert.equal(true, chapter_listing_calls[1].fullscreen)
  end)

  it("openMenu offers a Sort by... entry that opens the sort dialog", function()
    local view = make_view()
    local sort_calls = 0
    view.openSortDialog = function() sort_calls = sort_calls + 1 end

    view:openMenu()

    assert.is_not_nil(last_button_dialog, "openMenu must open a ButtonDialog")

    local sort_btn
    for _, row in ipairs(last_button_dialog.buttons) do
      for _, btn in ipairs(row) do
        if type(btn.text) == "string" and btn.text:find("Sort by...", 1, true) then
          sort_btn = btn
        end
      end
    end
    assert.is_not_nil(sort_btn, "openMenu must include a Sort by... entry")

    sort_btn.callback()
    assert.equal(1, sort_calls)
  end)

  it("updateOfflineSubtitle re-installs the action bar after BaseMenu rebuilds page_info", function()
    local view = make_view()
    view.page_info_text = { setText = noop }
    local install_calls = 0
    view._installActionBar = function() install_calls = install_calls + 1 end

    -- skip_reinit=true: BaseMenu.init isn't re-run, so the action bar
    -- doesn't need to be rebuilt either.
    view:updateOfflineSubtitle(true)
    assert.equal(0, install_calls)

    -- skip_reinit=false (e.g. WiFi connect/disconnect after init): page_info
    -- gets rebuilt by BaseMenu.init, so the action bar must be re-installed.
    view:updateOfflineSubtitle(false)
    assert.equal(1, install_calls)
  end)

  it("_cycleViewMode advances through grid -> cover -> base -> grid and persists the choice", function()
    local view = make_view()
    local persisted = {}
    -- Capture what gets sent to the backend so we can assert the cycle order.
    package.loaded["Backend"].getSettings = function()
      return { type = "SUCCESS", body = { library_view_mode = view.library_view_mode or "cover" } }
    end
    package.loaded["Backend"].setSettings = function(s)
      table.insert(persisted, s.library_view_mode)
      return { type = "SUCCESS" }
    end
    view.fetchMangas = function() return {} end
    view.updateItems = function() end

    view.library_view_mode = "grid"
    view:_cycleViewMode()
    view:_cycleViewMode()
    view:_cycleViewMode()

    assert.same({ "cover", "base", "grid" }, persisted)
    assert.equal("grid", view.library_view_mode)
  end)

  it("openMenu offers a Playlists entry (collapsed from the title bar)", function()
    local view = make_view()
    local playlist_calls = 0
    view.openPlaylistDialog = function() playlist_calls = playlist_calls + 1 end

    view:openMenu()
    assert.is_not_nil(last_button_dialog)

    local playlists_btn
    for _, row in ipairs(last_button_dialog.buttons) do
      for _, btn in ipairs(row) do
        if type(btn.text) == "string" and btn.text:find("Playlists", 1, true) then
          playlists_btn = btn
        end
      end
    end
    assert.is_not_nil(playlists_btn,
      "openMenu must include a Playlists entry now that the title bar icon is gone")

    playlists_btn.callback()
    assert.equal(1, playlist_calls)
  end)
end)
