---@diagnostic disable: undefined-global, undefined-field

-- Stubs for KOReader modules Backend.lua requires at load time.

local function noop() end

package.loaded["logger"]    = { info = noop, warn = noop, err = noop }
package.loaded["ffi/util"]  = { sleep = noop }
package.loaded["rapidjson"] = { null = {}, encode = function() return "" end, decode = function() return {} end }
package.loaded["Platform"]  = { startServer = function() return {} end }

-- Minimal util stub. urlEncode mirrors KOReader's behavior for the
-- characters we care about: percent-encode anything that isn't an
-- unreserved URL character, in particular '/'.
package.loaded["util"] = {
  urlEncode = function(s)
    return (s:gsub("[^%w%-%.%_%~]", function(c)
      return string.format("%%%02X", string.byte(c))
    end))
  end,
}

package.loaded["Backend"] = nil
local Backend = require("Backend")

-- Capture the real implementations before any test replaces them.
local real_requestJson = Backend.requestJson
local real_performRequest = Backend._performRequest
local real_initialize = Backend.initialize

describe("Backend.getStoredChapter", function()
  -- Regression: ids from sources like en.weebcentral contain literal '/'
  -- characters. Without URL-encoding, the resulting path has stray slashes
  -- that don't match the backend's axum route, which then returns a default
  -- 404 with no JSON body — crashing requestJson at the rapidjson.decode call.
  it("URL-encodes manga_id and chapter_id with slashes", function()
    local captured
    Backend.requestJson = function(req)
      captured = req
      return { type = "SUCCESS", body = {} }
    end

    Backend.getStoredChapter(
      "en.weebcentral",
      "/series/01J76XYAYAW5RJFBDGP21DDWJQ/Ore-To-Akuma-No-Blues/chapters/",
      "/chapters/01J76XYX3P77NSZKD306RNKAGC"
    )

    assert.is_not_nil(captured)
    assert.equal("GET", captured.method)
    assert.equal(
      "/mangas/en.weebcentral/" ..
      "%2Fseries%2F01J76XYAYAW5RJFBDGP21DDWJQ%2FOre-To-Akuma-No-Blues%2Fchapters%2F" ..
      "/chapters/" ..
      "%2Fchapters%2F01J76XYX3P77NSZKD306RNKAGC" ..
      "/stored",
      captured.path
    )
    -- And specifically: no doubled slashes leaking through.
    assert.is_nil(captured.path:match("//"))
  end)

  it("passes through ids without slashes unchanged", function()
    local captured
    Backend.requestJson = function(req)
      captured = req
      return { type = "SUCCESS", body = {} }
    end

    Backend.getStoredChapter("src", "manga1", "ch1")

    assert.equal("/mangas/src/manga1/chapters/ch1/stored", captured.path)
  end)
end)

describe("Backend.getLibraryStats", function()
  it("issues a GET to /library/stats", function()
    local captured
    Backend.requestJson = function(req)
      captured = req
      return { type = "SUCCESS", body = {} }
    end

    Backend.getLibraryStats()

    assert.is_not_nil(captured)
    assert.equal("/library/stats", captured.path)
    -- Default method is GET — we shouldn't be passing a body or method override.
    assert.is_nil(captured.method)
    assert.is_nil(captured.body)
  end)
end)

-- Regression: the server process can be killed while the device sleeps. The
-- back buttons all work by re-fetching from the backend inside a return
-- callback; without recovery, that fetch fails, the previous screen is never
-- re-shown, and the user is dumped out of the plugin.
describe("Backend.requestJson recovery after the server dies", function()
  local initialize_calls, stop_calls

  before_each(function()
    Backend.requestJson = real_requestJson
    initialize_calls = 0
    stop_calls = 0
    Backend.server = { stop = function() stop_calls = stop_calls + 1 end }
    Backend.initialize = function()
      initialize_calls = initialize_calls + 1
      Backend.server = { stop = function() end }
      return true, nil
    end
  end)

  after_each(function()
    Backend._performRequest = real_performRequest
    Backend.initialize = real_initialize
    Backend.server = nil
  end)

  it("returns successful responses untouched, without any health check", function()
    local perform_calls = 0
    Backend._performRequest = function(_req)
      perform_calls = perform_calls + 1
      return { type = "SUCCESS", body = { ok = true } }
    end

    local response = Backend.requestJson({ path = "/foo" })

    assert.equal("SUCCESS", response.type)
    assert.equal(1, perform_calls)
    assert.equal(0, initialize_calls)
  end)

  it("returns HTTP-level errors (with a status code) as-is — the server is alive", function()
    Backend._performRequest = function(_req)
      return { type = "ERROR", status = 500, message = "boom" }
    end

    local response = Backend.requestJson({ path = "/foo" })

    assert.equal("ERROR", response.type)
    assert.equal(500, response.status)
    assert.equal(0, initialize_calls)
    assert.equal(0, stop_calls)
  end)

  it("does not restart a slow-but-alive server: transport error + passing health check returns the original error", function()
    Backend._performRequest = function(req)
      if req.path == "/health-check" then
        return { type = "SUCCESS", body = {} }
      end
      return { type = "ERROR", message = "deadline has elapsed" }
    end

    local response = Backend.requestJson({ path = "/slow-endpoint" })

    assert.equal("ERROR", response.type)
    assert.equal("deadline has elapsed", response.message)
    assert.equal(0, initialize_calls)
    assert.equal(0, stop_calls)
  end)

  it("restarts a dead server and retries the request once", function()
    local restarted = false
    Backend.initialize = function()
      initialize_calls = initialize_calls + 1
      restarted = true
      Backend.server = { stop = function() end }
      return true, nil
    end
    Backend._performRequest = function(req)
      if req.path == "/health-check" then
        return { type = "ERROR", message = "connection refused" }
      end
      if restarted then
        return { type = "SUCCESS", body = { ok = true } }
      end
      return { type = "ERROR", message = "connection refused" }
    end

    local response = Backend.requestJson({ path = "/mangas" })

    assert.equal("SUCCESS", response.type)
    assert.equal(1, initialize_calls)
    assert.equal(1, stop_calls, "the dead server process must be stopped before starting a new one")
  end)

  it("returns the original transport error when the restart fails", function()
    Backend.initialize = function()
      initialize_calls = initialize_calls + 1
      return false, "server logs"
    end
    Backend._performRequest = function(_req)
      return { type = "ERROR", message = "connection refused" }
    end

    local response = Backend.requestJson({ path = "/mangas" })

    assert.equal("ERROR", response.type)
    assert.equal("connection refused", response.message)
    assert.equal(1, initialize_calls)
  end)
end)

describe("Backend.ensureRunning", function()
  local initialize_calls

  before_each(function()
    initialize_calls = 0
    Backend.initialize = function()
      initialize_calls = initialize_calls + 1
      Backend.server = {}
      return true, nil
    end
  end)

  after_each(function()
    Backend._performRequest = real_performRequest
    Backend.initialize = real_initialize
    Backend.server = nil
  end)

  it("is a no-op when the server answers the health check", function()
    Backend.server = {}
    Backend._performRequest = function(_req)
      return { type = "SUCCESS", body = {} }
    end

    assert.is_true(Backend.ensureRunning())
    assert.equal(0, initialize_calls)
  end)

  it("restarts the server when the health check fails", function()
    local stop_calls = 0
    Backend.server = { stop = function() stop_calls = stop_calls + 1 end }
    Backend._performRequest = function(_req)
      return { type = "ERROR", message = "connection refused" }
    end

    assert.is_true(Backend.ensureRunning())
    assert.equal(1, initialize_calls)
    assert.equal(1, stop_calls)
  end)

  it("starts the server when it was never running (server == nil)", function()
    Backend.server = nil

    assert.is_true(Backend.ensureRunning())
    assert.equal(1, initialize_calls)
  end)
end)
