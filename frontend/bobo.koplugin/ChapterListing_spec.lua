---@diagnostic disable: undefined-global, undefined-field

-- Stubs for KOReader / bobo modules ChapterListing.lua requires at load time.
-- We never call init() on a real instance (its parent chain pulls in too much
-- of KOReader). Tests build instances by hand with setmetatable and exercise
-- the methods directly.

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

_G.G_defaults = { readSetting = function() return 24 end }
_G.G_reader_settings = {
  readSetting = function(_, _key, default) return default end,
  saveSetting = noop,
}

-- ButtonDialog stub: stash the most recent opts so tests can inspect them.
local last_button_dialog = nil
local button_dialog_stub = {
  new = function(_, opts)
    last_button_dialog = opts
    return opts
  end,
}

-- ActionBar stub: capture the action list passed in so we can check what
-- _installActionBar wired up.
local last_action_bar_actions = nil
local action_bar_stub = {
  new = function(_, opts)
    last_action_bar_actions = opts.actions
    return {
      getSize = function() return { w = 100, h = 40 } end,
    }
  end,
}

local trapper_stub = { wrap = function(_, fn) fn() end }

local uimanager_stub = {
  show     = noop,
  close    = noop,
  setDirty = noop,
  nextTick = function(_, fn) fn() end,
}

local screen_stub = {
  getWidth    = function() return 800 end,
  getHeight   = function() return 600 end,
  scaleBySize = function(_, n) return n end,
}

-- Track HorizontalSpan instances so we can assert clearTitleBarButtons
-- swapped both slots out.
local horizontal_span_stub = {
  new = function(_, opts) return setmetatable(opts or {}, { __index = { _is_horizontal_span = true } }) end,
}

package.loaded["ui/bidi"]                          = { flipDirectionIfMirroredUILayout = function(_, d) return d end }
package.loaded["ui/widget/buttondialog"]           = button_dialog_stub
package.loaded["ui/widget/infomessage"]            = stub_class()
package.loaded["ui/widget/inputdialog"]            = stub_class()
package.loaded["ui/uimanager"]                     = uimanager_stub
package.loaded["ui/widget/confirmbox"]             = stub_class()
package.loaded["ui/trapper"]                       = trapper_stub
package.loaded["device"]                           = { screen = screen_stub }
package.loaded["logger"]                           = { info = noop, err = noop, warn = noop, dbg = noop }
package.loaded["LoadingDialog"]                    = { showAndRun = function(_, _msg, fn) return fn() end }
package.loaded["util"]                             = { tableDeepCopy = function(t) return t end }
package.loaded["gettext+"]                         = function(s) return s end
package.loaded["ui/widget/horizontalgroup"]        = stub_class()
package.loaded["ui/widget/horizontalspan"]         = horizontal_span_stub
package.loaded["ui/widget/verticalgroup"]          = stub_class()
package.loaded["ui/widget/verticalspan"]           = stub_class()
package.loaded["ui/widget/button"]                 = {
  new = function(_, opts) return setmetatable(opts or {}, { __index = { _is_button = true, setText = noop } }) end,
}
package.loaded["widgets/ActionBar"]                = action_bar_stub
package.loaded["ffi/sha2"]                         = { md5 = function(s) return s end }
package.loaded["datastorage"]                      = { getSettingsDir = function() return "/tmp" end }
package.loaded["luasettings"]                      = { open = function() return { readSetting = function(_, _k, d) return d end, saveSetting = noop, flush = noop } end }
package.loaded["Backend"]                          = {
  listCachedChapters     = function() return { type = "SUCCESS", body = {} } end,
  getPreferredScanlator  = function() return { type = "SUCCESS", body = nil } end,
  refreshChapters        = function() return { type = "SUCCESS" } end,
  setPreferredScanlator  = noop,
  getSettings            = function() return { type = "SUCCESS", body = {} } end,
  setSettings            = function() return { type = "SUCCESS" } end,
  addMangaToLibrary      = function() return { type = "SUCCESS" } end,
  getStoredChapter       = function() return { type = "ERROR" } end,
  revokeChapter          = function() return { type = "SUCCESS" } end,
  markChapterAsRead      = function() return { type = "SUCCESS" } end,
  markChaptersAsRead     = function() return { type = "SUCCESS" } end,
  updateLastReadChapter  = noop,
  downloadAllChapters    = function() return { type = "SUCCESS" } end,
  cancelDownloadAllChapters = function() return { type = "SUCCESS" } end,
  getDownloadAllChaptersProgress = function() return { type = "SUCCESS", body = { type = "FINISHED" } } end,
  createCancelId         = function() return 1 end,
  cancel                 = noop,
}
package.loaded["jobs/DownloadChapter"]             = stub_class()
package.loaded["jobs/DownloadUnreadChapters"]      = stub_class()
package.loaded["DownloadUnreadChaptersJobDialog"]  = stub_class()
package.loaded["Icons"]                            = setmetatable({}, { __index = function(_, k) return "<" .. k .. ">" end })
package.loaded["widgets/Menu"]                     = stub_class({
  init = noop,
  updateItems = noop,
  onSwipe = noop,
  _recalculateDimen = noop,
  updateOfflineSubtitle = noop,
})
package.loaded["ErrorDialog"]                      = { show = noop }
package.loaded["MangaReader"]                      = { show = noop, preload_jobs = {}, closeReaderUi = function(_, cb) if cb then cb() end end }
package.loaded["MangaInfoWidget"]                  = { fetchAndShow = noop }
package.loaded["CheckboxDialog"]                   = stub_class()
package.loaded["testing"]                          = { emitEvent = noop, init = noop }
package.loaded["utils/calcLastReadText"]           = function() return "" end
package.loaded["utils/isBeforeChapter"]            = function() return true end
package.loaded["utils/filterChaptersByLang"]       = function(c) return c end
package.loaded["utils/findLastRead"]               = function() return nil end
package.loaded["utils/getChapterDisplayName"]      = function() return "" end
package.loaded["chapters/findNextChapter"]         = function() return nil end
package.loaded["ui/font"]                          = { getFace = function() return {} end }

package.loaded["ChapterListing"] = nil
local ChapterListing = require("ChapterListing")

-- Build a ChapterListing instance without running init() — we only want to
-- exercise the dispatch wiring, not the heavy widget construction.
local function make_view(overrides)
  local view = setmetatable({
    manga = { id = "m1", source = { id = "src" } },
    chapters = {},
    raw_chapters = {},
    langs = {},
    langs_selected = {},
    available_scanlators = {},
    -- Intentionally do NOT stub openMenu / refreshChapters / readContinue
    -- / onDownloadUnreadChapters here: the openMenu tests want the real
    -- method to run, and the action-bar callback tests stub via overrides.
  }, { __index = ChapterListing })
  for k, v in pairs(overrides or {}) do view[k] = v end
  return view
end

local function find_button(button_dialog, label)
  for _, row in ipairs(button_dialog.buttons) do
    for _, btn in ipairs(row) do
      if type(btn.text) == "string" and btn.text:find(label, 1, true) then
        return btn
      end
    end
  end
  return nil
end

describe("ChapterListing redesign — bottom action bar + slim title bar", function()
  before_each(function()
    last_button_dialog = nil
    last_action_bar_actions = nil
  end)

  it("clearTitleBarButtons empties both left and right title-bar slots", function()
    -- Simulate the title bar shape KOReader produces: [title, left_btn, right_btn].
    local title_bar = { left_button = { _was = "hamburger" }, right_button = { _was = "close" } }
    title_bar[1] = { _is = "title" }
    title_bar[2] = title_bar.left_button
    title_bar[3] = title_bar.right_button

    local view = make_view({ title_bar = title_bar })
    view:clearTitleBarButtons()

    assert.is_true(view.title_bar.left_button._is_horizontal_span,
      "left button must be replaced with an empty HorizontalSpan")
    assert.is_true(view.title_bar.right_button._is_horizontal_span,
      "right button must be replaced with an empty HorizontalSpan")
    assert.equal(view.title_bar.left_button, view.title_bar[2],
      "title_bar[2] must mirror left_button")
    assert.equal(view.title_bar.right_button, view.title_bar[3],
      "title_bar[3] must mirror right_button")
  end)

  it("patchTitleBar replaces the hamburger with a lone language indicator (no HorizontalGroup)", function()
    local title_bar = { left_icon_size_ratio = 1, left_button = {} }
    title_bar[1] = {}
    title_bar[2] = title_bar.left_button
    local view = make_view({ title_bar = title_bar, showSelectLanguage = noop })

    view:patchTitleBar(3)

    -- Should be a Button, not a HorizontalGroup wrapping a hamburger + button.
    assert.is_true(view.title_bar.left_button._is_button,
      "left_button must be a plain Button (no hamburger HorizontalGroup wrapper)")
    assert.is_truthy(view.title_bar.left_button.text:find("3", 1, true),
      "lang count must appear in the button text")
    assert.equal(view.title_bar.left_button, view.title_bar[2],
      "title_bar[2] must mirror the new left_button")
  end)

  it("_installActionBar wires up Back, Resume, Refresh, Download, More", function()
    local page_info_text = {
      setText = noop,
      getSize = function() return { w = 100, h = 20 } end,
      paintTo = noop,
    }
    local page_info = setmetatable({ resetLayout = function() end }, { __index = {} })
    -- Standard 5 chevron children for an inhabited page_info row.
    page_info[1] = { _name = "chevron_first" }
    page_info[2] = { _name = "chevron_left" }
    page_info[3] = page_info_text
    page_info[4] = { _name = "chevron_right" }
    page_info[5] = { _name = "chevron_last" }

    local view = make_view({ page_info = page_info, page_info_text = page_info_text })
    view:_installActionBar()

    assert.is_not_nil(last_action_bar_actions, "_installActionBar must build an ActionBar")
    local labels = {}
    for _, action in ipairs(last_action_bar_actions) do labels[action.label] = action end
    assert.is_not_nil(labels["Back"],     "Back belongs on the bottom action bar (replaces title-bar X)")
    assert.is_not_nil(labels["Resume"],   "Resume continues reading from the last-read chapter")
    assert.is_not_nil(labels["Refresh"],  "Refresh promoted from the More overflow")
    assert.is_not_nil(labels["Download"], "Download unread promoted from the More overflow")
    assert.is_not_nil(labels["More"],     "More opens the overflow")
  end)

  it("the Back action on the bar calls onClose (so the user returns to the previous screen)", function()
    local page_info_text = {
      setText = noop,
      getSize = function() return { w = 100, h = 20 } end,
      paintTo = noop,
    }
    local page_info = setmetatable({ resetLayout = function() end }, { __index = {} })
    page_info[1] = page_info_text

    local close_calls = 0
    local view = make_view({
      page_info = page_info,
      page_info_text = page_info_text,
      onClose = function() close_calls = close_calls + 1 end,
    })
    view:_installActionBar()

    local back
    for _, action in ipairs(last_action_bar_actions) do
      if action.label == "Back" then back = action end
    end
    assert.is_not_nil(back)
    back.callback()
    assert.equal(1, close_calls)
  end)

  it("_installActionBar preserves the existing pagination chevrons below the bar", function()
    -- The user explicitly relies on the chevrons to scroll between pages
    -- and wants skip-to-first / skip-to-last available. KOReader's default
    -- page_info row already provides both, so capturing the original
    -- children and reinserting them under the action bar keeps the
    -- behaviour the user is used to.
    local page_info_text = {
      setText = noop,
      getSize = function() return { w = 100, h = 20 } end,
      paintTo = noop,
    }
    local chevron_first = { _name = "chevron_first" }
    local chevron_left  = { _name = "chevron_left" }
    local chevron_right = { _name = "chevron_right" }
    local chevron_last  = { _name = "chevron_last" }

    local captured_horizontal_groups = {}
    package.loaded["ui/widget/horizontalgroup"].new = function(_, opts)
      local hg = setmetatable(opts or {}, { __index = { _is_hgroup = true } })
      table.insert(captured_horizontal_groups, hg)
      return hg
    end

    local page_info = setmetatable({ resetLayout = function() end }, { __index = {} })
    page_info[1] = chevron_first
    page_info[2] = chevron_left
    page_info[3] = page_info_text
    page_info[4] = chevron_right
    page_info[5] = chevron_last

    local view = make_view({ page_info = page_info, page_info_text = page_info_text })
    view:_installActionBar()

    -- One HorizontalGroup was built; it must contain all five originals.
    assert.equal(1, #captured_horizontal_groups,
      "_installActionBar must build a single HorizontalGroup for the chevron row")
    local chevron_row = captured_horizontal_groups[1]
    local present = {}
    for _, c in ipairs(chevron_row) do
      if type(c) == "table" and c._name then present[c._name] = true end
    end
    assert.is_true(present.chevron_first, "skip-to-first chevron must be preserved")
    assert.is_true(present.chevron_left,  "prev-page chevron must be preserved")
    assert.is_true(present.chevron_right, "next-page chevron must be preserved")
    assert.is_true(present.chevron_last,  "skip-to-last chevron must be preserved")
  end)

  it("updateOfflineSubtitle re-installs the action bar after BaseMenu rebuilds page_info", function()
    local view = make_view()
    view.page_info_text = { setText = noop }
    local install_calls = 0
    view._installActionBar = function() install_calls = install_calls + 1 end

    -- skip_reinit=true: BaseMenu.init wasn't rerun, so no re-install needed.
    view:updateOfflineSubtitle(true)
    assert.equal(0, install_calls)

    -- skip_reinit=false (e.g. WiFi connect after init): page_info was
    -- rebuilt, so the action bar must be re-installed.
    view:updateOfflineSubtitle(false)
    assert.equal(1, install_calls)
  end)

  it("openMenu (the More overflow) no longer carries items promoted to the bottom action bar", function()
    -- Refresh, Resume, and Download unread chapters live on the bottom
    -- action bar now — the overflow is the secondary-action menu only.
    local view = make_view()
    view:openMenu()
    assert.is_not_nil(last_button_dialog, "openMenu must open a ButtonDialog")

    assert.is_nil(find_button(last_button_dialog, "Refresh"),
      "Refresh lives on the bottom bar; not in the More overflow")
    assert.is_nil(find_button(last_button_dialog, "Resume"),
      "Resume lives on the bottom bar; not in the More overflow")
    assert.is_nil(find_button(last_button_dialog, "Download unread"),
      "Download unread lives on the bottom bar; not in the More overflow")
  end)

  it("openMenu keeps secondary actions: Back to library, Add to Library, Details, Mark read/unread, Next Chapter", function()
    local view = make_view()
    view:openMenu()
    assert.is_not_nil(last_button_dialog)

    assert.is_not_nil(find_button(last_button_dialog, "Back to library"),
      "explicit library jump stays in the overflow")
    assert.is_not_nil(find_button(last_button_dialog, "Add to Library"),
      "Add to Library stays in the overflow")
    assert.is_not_nil(find_button(last_button_dialog, "Details"),
      "Details stays in the overflow")
    assert.is_not_nil(find_button(last_button_dialog, "Mark read"),
      "Mark read stays in the overflow")
    assert.is_not_nil(find_button(last_button_dialog, "Mark unread"),
      "Mark unread stays in the overflow")
    assert.is_not_nil(find_button(last_button_dialog, "Next Chapter"),
      "Next Chapter stays in the overflow (Resume is on the bar)")
  end)

  it("openMenu still surfaces Languages and Filter by Group when applicable", function()
    local view = make_view({
      langs = { { id = "en", name = "en" }, { id = "ja", name = "ja" } },
      available_scanlators = { "Group A", "Group B" },
    })
    view:openMenu()
    assert.is_not_nil(last_button_dialog)

    assert.is_not_nil(find_button(last_button_dialog, "Languages"),
      "Languages overflow entry must appear when 2+ languages exist")
    assert.is_not_nil(find_button(last_button_dialog, "Filter by Group"),
      "Filter by Group overflow entry must appear when 2+ scanlators exist")
  end)
end)
