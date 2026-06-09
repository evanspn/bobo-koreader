local DocumentRegistry = require("document/documentregistry")
local InputContainer = require("ui/widget/container/inputcontainer")
local FileManager = require("apps/filemanager/filemanager")
local UIManager = require("ui/uimanager")
local Dispatcher = require("dispatcher")
local logger = require("logger")
local _ = require("gettext+")
local OfflineAlertDialog = require("OfflineAlertDialog")

local Backend = require("Backend")
local CbzDocument = require("extensions/CbzDocument")
local CrashReporter = require("CrashReporter")
local ErrorDialog = require("ErrorDialog")
local LibraryView = require("LibraryView")
local MangaReader = require("MangaReader")
local ProfilePicker = require("ProfilePicker")
local Testing = require("testing")

logger.info("Loading Bobo plugin...")
local backendInitialized, logs = Backend.initialize()

local Bobo = InputContainer:extend({
  name = "bobo"
})

-- We can get initialized from two contexts:
-- - when the `FileManager` is initialized, we're called
-- - when the `ReaderUI` is initialized, we're also called
-- so we should register to the menu accordingly
function Bobo:init()
  if self.ui.name == "ReaderUI" then
    MangaReader:initializeFromReaderUI(self.ui)
  else
    self.ui.menu:registerToMainMenu(self)
  end

  CbzDocument:register(DocumentRegistry)
  Dispatcher:registerAction("bobo_start_library_view", {
    category = "none",
    event = "BoboStartLibraryView",
    title = _("Bobo"),
    general = true
  })

  Testing:init()
  Testing:emitEvent('initialized')
end

--- The backend process can be killed while the device sleeps. When that
--- happens, every back button "exits the app": the return callback re-fetches
--- from a dead backend, errors out, and never re-opens the previous screen.
--- Health-check and revive the server as soon as the device wakes so
--- navigation keeps working.
function Bobo:onResume()
  if not backendInitialized then
    return
  end

  -- Give the system a moment to settle after wake-up before poking the socket.
  UIManager:scheduleIn(1, function()
    backendInitialized, logs = Backend.ensureRunning()
  end)
end

function Bobo:onBoboStartLibraryView()
  if self.ui.name == "ReaderUI" then
    MangaReader:initializeFromReaderUI(self.ui)
  else
    if not backendInitialized then
      self:showErrorDialog()

      return
    end

    self:openLibraryView()
  end
end

function Bobo:addToMainMenu(menu_items)
  menu_items.bobo = {
    text = _("Bobo"),
    sorting_hint = "search",
    callback = function()
      if not backendInitialized then
        self:showErrorDialog()

        return
      end

      self:openLibraryView()
    end
  }
end

function Bobo:showErrorDialog()
  local message = _("Oops!") .. _("Bobo encountered an issue while starting up!") .. "\n" ..
      _("Here are some messages that might help identify the problem:") .. "\n\n" ..
      logs
  ErrorDialog:show(
    message,
    function()
      Backend.cleanup()
      backendInitialized, logs = Backend.initialize()
    end,
    function()
      CrashReporter.showQrFor {
        title = "Bobo failed to start",
        body  = "Bobo's backend failed to start. Logs:\n\n```\n" .. (logs or "") .. "\n```",
      }
    end
  )
end

function Bobo:openLibraryView()
  -- Show the profile picker if there's more than one profile and the user
  -- hasn't already picked the active one in this session. Skipped on
  -- single-profile installs to keep the cold-start path identical to the
  -- pre-PR behavior.
  if not self._profile_picked_this_session then
    local r = Backend.listProfiles()
    if r.type == 'SUCCESS' and #r.body > 1 then
      self:_showProfilePicker(r.body)
      return
    end
  end
  LibraryView:fetchAndShow()
  OfflineAlertDialog:showIfOffline()
end

--- @private
function Bobo:_showProfilePicker(profiles)
  local picker
  picker = ProfilePicker.show {
    profiles = profiles,
    on_select = function(profile)
      UIManager:close(picker)
      self._profile_picked_this_session = true
      if not profile.active then
        local sw = Backend.switchProfile(profile.id)
        if sw.type == 'ERROR' then
          ErrorDialog:show(sw.message)
          return
        end
      end
      LibraryView:fetchAndShow()
      OfflineAlertDialog:showIfOffline()
    end,
    on_manage = function()
      UIManager:close(picker)
      local ProfileManager = require("ProfileManager")
      -- After managing, re-show the picker so the user still has to choose.
      ProfileManager:fetchAndShow(function() self:openLibraryView() end)
    end,
  }
end

function Bobo:openFromToolbar()
  self:openLibraryView()
end

return Bobo
