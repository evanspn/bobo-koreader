---@diagnostic disable: undefined-global, undefined-field

-- LibraryView pulls in a large chunk of KOReader. We only need the two methods
-- that the cover-tap / long-press swap rewires (`onPrimaryMenuChoice` and
-- `onContextMenuChoice`), so we stub everything the module touches at load
-- time and exercise the rewired methods directly.

local function noop() end

local stub_widget = {
  extend = function(self, defaults)
    local cls = setmetatable({}, { __index = self })
    if defaults then
      for k, v in pairs(defaults) do cls[k] = v end
    end
    cls.extend = self.extend
    cls.new = function(c, opts)
      local instance = setmetatable(opts or {}, { __index = c })
      if instance.init then instance:init() end
      return instance
    end
    return cls
  end,
  new = function(self, opts) return opts or {} end,
  init = noop,
}

package.loaded["ui/widget/confirmbox"]                = { new = function(_, t) return t end }
package.loaded["ffi/util"]                            = {}
package.loaded["ui/widget/inputdialog"]               = { new = function(_, t) return t end }
package.loaded["ui/uimanager"]                        = {
  show = noop, close = noop, nextTick = function(_, fn) fn() end, setDirty = noop,
}
package.loaded["device"]                              = {
  screen = { getWidth = function() return 600 end, getHeight = function() return 800 end, scaleBySize = function(_, n) return n end },
  isTouchDevice = function() return true end,
}
package.loaded["ui/trapper"]                          = {
  -- Run the wrapped function inline so we can observe its side effects.
  wrap = function(_, fn) fn() end,
}
package.loaded["gettext+"]                            = function(s) return s end
package.loaded["Icons"]                               = setmetatable({}, { __index = function() return "" end })
package.loaded["ui/widget/buttondialog"]              = { new = function(_, t) return t end }
package.loaded["InstalledSourcesListing"]             = stub_widget
package.loaded["ui/widget/iconbutton"]                = stub_widget
package.loaded["ui/widget/horizontalgroup"]           = stub_widget
package.loaded["ui/widget/horizontalspan"]            = stub_widget
package.loaded["ui/widget/button"]                    = stub_widget
package.loaded["ui/font"]                             = { getFace = function() return {} end }
package.loaded["ui/widget/verticalgroup"]             = stub_widget
package.loaded["ui/widget/verticalspan"]              = stub_widget
package.loaded["ui/widget/infomessage"]               = stub_widget
package.loaded["handlers/addToPlaylist"]              = noop
package.loaded["Backend"]                             = {}
package.loaded["ErrorDialog"]                         = { show = noop }
package.loaded["ChapterListing"]                      = {
  fetchAndShow = function() return true end,
  openMarkDialog = noop,
  new = function(_, t) return t end,
}
package.loaded["MangaSearchResults"]                  = stub_widget
package.loaded["widgets/Menu"]                        = stub_widget
package.loaded["Settings"]                            = stub_widget
package.loaded["testing"]                             = { emitEvent = noop, init = noop }
package.loaded["UpdateChecker"]                      = { check = noop }
package.loaded["utils/calcLastReadText"]              = function() return "" end
package.loaded["utils/findEntries"]                   = function() return {} end
package.loaded["utils/findLastRead"]                  = function() return nil end
package.loaded["utils/getChapterDisplayName"]         = function() return "" end
package.loaded["utils/filterChaptersByLang"]          = function(c) return c end
package.loaded["ffi/sha2"]                            = { md5 = function() return "" end }
package.loaded["datastorage"]                         = { getSettingsDir = function() return "/tmp" end }
package.loaded["luasettings"]                         = {
  open = function() return { readSetting = function() return {} end, saveSetting = noop, flush = noop } end,
}
package.loaded["NotificationView"]                    = stub_widget
package.loaded["ui/widget/radiobuttonwidget"]         = stub_widget
package.loaded["LoadingDialog"]                       = { showAndRun = function(_, _, fn) return fn() end }
package.loaded["MangaInfoWidget"]                     = { fetchAndShow = noop }
package.loaded["CheckboxDialog"]                      = stub_widget
package.loaded["jobs/RefreshLibraryChapters"]         = stub_widget
package.loaded["jobs/RefreshLibraryDetails"]          = stub_widget
package.loaded["BasicJobDialog"]                      = stub_widget
package.loaded["patch/MenuItemCover"]                 = stub_widget
package.loaded["patch/MenuItemGrid"]                  = stub_widget
package.loaded["patch/MenuCustom"]                    = stub_widget
package.loaded["PlaylistDialog"]                      = stub_widget

_G.G_defaults = { readSetting = function() return 24 end }
_G.G_reader_settings = { readSetting = function() return nil end, saveSetting = noop }

package.loaded["LibraryView"] = nil
local LibraryView = require("LibraryView")

describe("LibraryView cover-tap swap", function()
  it("onPrimaryMenuChoice triggers the Continue Reading flow", function()
    local called_with
    local instance = setmetatable({
      _handleContinueReading = function(_, manga) called_with = manga end,
    }, { __index = LibraryView })

    local manga = { id = "m1", source = { id = "src" }, title = "Test" }
    instance:onPrimaryMenuChoice({ manga = manga })

    assert.equal(manga, called_with)
  end)

  it("onPrimaryMenuChoice is a no-op when the item has no manga", function()
    local called = false
    local instance = setmetatable({
      _handleContinueReading = function() called = true end,
    }, { __index = LibraryView })

    instance:onPrimaryMenuChoice({})

    assert.is_false(called)
  end)

  it("long-press menu exposes View All Chapters that opens the chapter listing", function()
    local opened_with
    local instance = setmetatable({
      _openChapterListing = function(_, manga) opened_with = manga end,
      -- Stubs for unrelated buttons so building the menu doesn't blow up.
      _refreshManga = function() return { type = "SUCCESS" } end,
      _handleContinueReading = noop,
      _handleRemoveFromLibrary = noop,
      fetchAndShow = noop,
      onClose = noop,
      updateItems = noop,
      current_playlist = nil,
    }, { __index = LibraryView })

    -- ButtonDialog stub captures the buttons table for inspection.
    local captured_buttons
    package.loaded["ui/widget/buttondialog"].new = function(_, t)
      captured_buttons = t.buttons
      return t
    end

    local manga = { id = "m1", source = { id = "src", name = "Source" }, title = "Test" }
    instance:onContextMenuChoice({ manga = manga })

    assert.is_not_nil(captured_buttons)

    local view_all_button
    for _, row in ipairs(captured_buttons) do
      for _, button in ipairs(row) do
        if button.text and button.text:find("View All Chapters") then
          view_all_button = button
        end
        assert.is_falsy(button.text and button.text:find("Continue Reading"),
          "long-press menu should no longer offer Continue Reading")
      end
    end

    assert.is_not_nil(view_all_button, "long-press menu should offer View All Chapters")
    view_all_button.callback()
    assert.equal(manga, opened_with)
  end)
end)
