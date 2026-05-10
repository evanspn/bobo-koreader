---@diagnostic disable: undefined-global, undefined-field

-- Stub the two KOReader UI modules CrashReporter pulls in so the require
-- succeeds in a busted environment with no KOReader on the path. The QR
-- modal itself is not exercised by the pure-logic tests below.

local last_qr_shown
local qrmessage_stub = {
  new = function(_, opts)
    last_qr_shown = opts
    return opts
  end,
}
local uimanager_stub = {
  show = function(_, w) last_qr_shown = w end,
}

package.loaded["ui/widget/qrmessage"] = qrmessage_stub
package.loaded["ui/uimanager"]        = uimanager_stub

package.loaded["CrashReporter"] = nil
local CrashReporter = require("CrashReporter")

describe("CrashReporter._urlencode", function()
  it("percent-encodes reserved characters", function()
    assert.equal("hello%20world", CrashReporter._urlencode("hello world"))
    assert.equal("a%26b%3Dc", CrashReporter._urlencode("a&b=c"))
    assert.equal("%23hash", CrashReporter._urlencode("#hash"))
  end)

  it("leaves RFC 3986 unreserved characters alone", function()
    assert.equal("AZaz09-._~", CrashReporter._urlencode("AZaz09-._~"))
  end)

  it("encodes newlines as CRLF (so GitHub renders them as line breaks)", function()
    assert.equal("a%0D%0Ab", CrashReporter._urlencode("a\nb"))
    assert.equal("a%0D%0Ab", CrashReporter._urlencode("a\r\nb"))
  end)

  it("handles empty / nil input", function()
    assert.equal("", CrashReporter._urlencode(""))
    assert.equal("", CrashReporter._urlencode(nil))
  end)
end)

describe("CrashReporter._truncate", function()
  it("returns the input unchanged when it already fits", function()
    assert.equal("short", CrashReporter._truncate("short", 100))
  end)

  it("keeps the tail because crash output is most informative at the end", function()
    local text = string.rep("x", 100) .. "PANIC_LINE"
    local truncated = CrashReporter._truncate(text, 50)
    assert.is_true(truncated:sub(-#"PANIC_LINE") == "PANIC_LINE",
      "truncated body should end with the tail of the original")
  end)

  it("prefixes a marker so the reader knows content was dropped", function()
    local text = string.rep("y", 500)
    local truncated = CrashReporter._truncate(text, 100)
    assert.is_true(truncated:sub(1, #CrashReporter.TRUNCATION_MARKER) == CrashReporter.TRUNCATION_MARKER)
  end)

  it("respects the max_chars budget", function()
    local text = string.rep("z", 500)
    local truncated = CrashReporter._truncate(text, 100)
    assert.is_true(#truncated <= 100, "expected length <=100, got " .. #truncated)
  end)
end)

describe("CrashReporter.buildIssueUrl", function()
  it("produces a URL pointing at the bobo-koreader new-issue endpoint", function()
    local url = CrashReporter.buildIssueUrl { title = "t", body = "b" }
    assert.is_true(url:find("https://github.com/evanspn/bobo-koreader/issues/new", 1, true) == 1,
      "URL should start with the canonical issues/new endpoint, got: " .. url)
  end)

  it("includes the title and body as query parameters", function()
    local url = CrashReporter.buildIssueUrl { title = "Crash on startup", body = "hello" }
    assert.is_true(url:find("title=Crash%%20on%%20startup", 1, false) ~= nil, url)
    assert.is_true(url:find("body=hello", 1, true) ~= nil, url)
  end)

  it("URL-encodes special characters in the title", function()
    local url = CrashReporter.buildIssueUrl { title = "a & b", body = "" }
    assert.is_true(url:find("title=a%%20%%26%%20b", 1, false) ~= nil, url)
  end)

  it("never produces a URL longer than max_url_chars, even for huge bodies", function()
    local huge = string.rep("error line\n", 5000)
    local url = CrashReporter.buildIssueUrl {
      title = "Crash",
      body  = huge,
      max_url_chars = 1500,
    }
    assert.is_true(#url <= 1500, "expected url length <=1500, got " .. #url)
  end)

  it("preserves the body's tail when it has to truncate", function()
    -- The most recent log line carries the panic — keep it visible.
    local body = string.rep("noise\n", 1000) .. "FINAL_PANIC_MARKER"
    local url = CrashReporter.buildIssueUrl {
      title = "Crash",
      body  = body,
      max_url_chars = 1500,
    }
    assert.is_true(url:find("FINAL_PANIC_MARKER", 1, true) ~= nil,
      "truncated URL should still contain the tail of the body")
  end)

  it("uses the default max_url_chars when none is provided", function()
    local huge = string.rep("x", 100000)
    local url = CrashReporter.buildIssueUrl { title = "t", body = huge }
    assert.is_true(#url <= CrashReporter.DEFAULT_MAX_URL_CHARS,
      "expected url length <=" .. CrashReporter.DEFAULT_MAX_URL_CHARS .. ", got " .. #url)
  end)
end)

describe("CrashReporter.showQrFor", function()
  before_each(function()
    last_qr_shown = nil
  end)

  it("hands UIManager a QRMessage whose text is the issue URL", function()
    CrashReporter.showQrFor { title = "Boom", body = "stack trace here" }
    assert.is_not_nil(last_qr_shown)
    assert.is_string(last_qr_shown.text)
    assert.is_true(last_qr_shown.text:find("evanspn/bobo-koreader", 1, true) ~= nil)
    assert.is_true(last_qr_shown.text:find("title=Boom", 1, true) ~= nil)
  end)
end)
