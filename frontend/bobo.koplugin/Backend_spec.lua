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
