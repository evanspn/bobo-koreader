---@diagnostic disable: undefined-global, undefined-field

-- Stubs for KOReader / bobo modules main.lua requires at load time. We only
-- exercise the Bobo plugin object's event wiring (onResume), not init().

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

-- Capture scheduled callbacks so tests can fire them deterministically.
local scheduled = {}
local uimanager_stub = {
  show           = noop,
  close          = noop,
  setDirty       = noop,
  nextTick       = function(_, fn) fn() end,
  broadcastEvent = noop,
  scheduleIn     = function(_, delay, fn)
    table.insert(scheduled, { delay = delay, fn = fn })
  end,
}

local ensure_running_calls = 0
local backend_stub = {
  initialize    = function() return true, nil end,
  ensureRunning = function()
    ensure_running_calls = ensure_running_calls + 1
    return true, nil
  end,
  cleanup       = noop,
  listProfiles  = function() return { type = "SUCCESS", body = {} } end,
}

package.loaded["document/documentregistry"]          = {}
package.loaded["ui/widget/container/inputcontainer"] = stub_class()
package.loaded["apps/filemanager/filemanager"]       = {}
package.loaded["ui/uimanager"]                       = uimanager_stub
package.loaded["dispatcher"]                         = { registerAction = noop }
package.loaded["logger"]                             = { info = noop, err = noop, warn = noop, dbg = noop }
package.loaded["gettext+"]                           = function(s) return s end
package.loaded["OfflineAlertDialog"]                 = { showIfOffline = noop }
package.loaded["Backend"]                            = backend_stub
package.loaded["extensions/CbzDocument"]             = { register = noop }
package.loaded["CrashReporter"]                      = { showQrFor = noop, showBugReportQr = noop }
package.loaded["ErrorDialog"]                        = { show = noop }
package.loaded["LibraryView"]                        = { fetchAndShow = noop }
package.loaded["MangaReader"]                        = { initializeFromReaderUI = noop }
package.loaded["ProfilePicker"]                      = { show = noop }
package.loaded["testing"]                            = { emitEvent = noop, init = noop }

-- main.lua calls Backend.initialize() at require time, so reloading it lets
-- each test pick the startup outcome via the stub.
local function load_main()
  package.loaded["main"] = nil
  return require("main")
end

describe("Bobo:onResume backend revival", function()
  before_each(function()
    scheduled = {}
    ensure_running_calls = 0
    backend_stub.initialize = function() return true, nil end
  end)

  it("schedules a delayed health check that revives a dead backend after wake-up", function()
    local Bobo = load_main()
    local bobo = setmetatable({}, { __index = Bobo })

    bobo:onResume()

    assert.equal(1, #scheduled, "onResume must schedule exactly one health check")
    assert.equal(0, ensure_running_calls,
      "the check must be deferred — the socket isn't reliable immediately after wake")

    scheduled[1].fn()

    assert.equal(1, ensure_running_calls)
  end)

  it("does nothing when the backend never initialized (the startup error dialog owns recovery)", function()
    backend_stub.initialize = function() return false, "startup logs" end
    local Bobo = load_main()
    local bobo = setmetatable({}, { __index = Bobo })

    bobo:onResume()

    assert.equal(0, #scheduled)
  end)
end)
