local QRMessage = require("ui/widget/qrmessage")
local UIManager = require("ui/uimanager")

local CrashReporter = {}

-- GitHub's new-issue endpoint for the project. Hardcoded so that the QR
-- always points at the canonical repo, even if the user is running a fork.
CrashReporter.ISSUE_URL_BASE = "https://github.com/evanspn/bobo-koreader/issues/new"

-- Cap the encoded URL length so the resulting QR code fits comfortably on
-- a Kobo screen and is reliably scannable by a phone camera. Higher-density
-- QRs (closer to v40) are physically too small once they have to share
-- the screen with anything else.
CrashReporter.DEFAULT_MAX_URL_CHARS = 1500

CrashReporter.TRUNCATION_MARKER = "...(earlier output truncated)...\n"

-- RFC 3986 percent-encoding for query-string values.
function CrashReporter._urlencode(s)
  s = tostring(s or "")
  s = s:gsub("\r?\n", "\r\n")
  return (s:gsub("([^%w%-._~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- Keep the tail of `text` because crash output is most informative at the
-- end (the panic line, the last log entry). Returns the original text when
-- it already fits.
function CrashReporter._truncate(text, max_chars)
  text = tostring(text or "")
  if #text <= max_chars then
    return text
  end
  local marker = CrashReporter.TRUNCATION_MARKER
  local keep = max_chars - #marker
  if keep <= 0 then
    return text:sub(-max_chars)
  end
  return marker .. text:sub(-keep)
end

-- Build a github.com/.../issues/new URL with title + body in the query string.
-- If the encoded URL would exceed `max_url_chars`, the body is truncated
-- (preserving its tail) until it fits. The title is never truncated.
---@param opts { title: string, body: string, max_url_chars: number|nil }
---@return string url
function CrashReporter.buildIssueUrl(opts)
  local title = opts.title or ""
  local body = opts.body or ""
  local max_url_chars = opts.max_url_chars or CrashReporter.DEFAULT_MAX_URL_CHARS

  local prefix = CrashReporter.ISSUE_URL_BASE
                 .. "?title=" .. CrashReporter._urlencode(title)
                 .. "&body="

  local encoded_body = CrashReporter._urlencode(body)
  if #prefix + #encoded_body <= max_url_chars then
    return prefix .. encoded_body
  end

  -- Binary search for the largest body suffix whose encoded form still fits.
  local budget = max_url_chars - #prefix
  local lo, hi = 0, #body
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    local candidate = CrashReporter._truncate(body, mid)
    if #CrashReporter._urlencode(candidate) <= budget then
      lo = mid
    else
      hi = mid - 1
    end
  end

  return prefix .. CrashReporter._urlencode(CrashReporter._truncate(body, lo))
end

-- Show a QR-code modal whose payload is a pre-filled GitHub new-issue URL.
-- The user scans it with their phone, GitHub opens the issue form, and they
-- tap Submit. No data leaves the device until they do.
---@param opts { title: string, body: string }
function CrashReporter.showQrFor(opts)
  local url = CrashReporter.buildIssueUrl(opts)
  UIManager:show(QRMessage:new {
    text = url,
  })
end

-- Candidate locations for KOReader's uncaught-error trace ("Don't Panic"
-- screen contents). The exact path varies by platform: KOReader's reader.lua
-- writes a relative `./crash.log`, but cwd can be anywhere depending on the
-- launcher. Try a few common spots in order. Tests inject their own list.
function CrashReporter._defaultCrashLogPaths()
  local paths = { "./crash.log", "crash.log" }
  local ok, DataStorage = pcall(require, "datastorage")
  if ok and DataStorage and DataStorage.getDataDir then
    table.insert(paths, 1, DataStorage:getDataDir() .. "/crash.log")
  end
  return paths
end

-- Read the tail of KOReader's crash log, if one exists. Returns nil when no
-- readable log was found at any candidate path. The log is most informative
-- at the end (the panic line, the final traceback), so we keep the tail when
-- it exceeds max_chars.
---@param opts { paths: string[]|nil, max_chars: number|nil }|nil
---@return string|nil
function CrashReporter.readCrashLogTail(opts)
  opts = opts or {}
  local paths = opts.paths or CrashReporter._defaultCrashLogPaths()
  local max_chars = opts.max_chars or 4000

  for _, path in ipairs(paths) do
    local f = io.open(path, "r")
    if f then
      local content = f:read("*a") or ""
      f:close()
      if #content > 0 then
        return CrashReporter._truncate(content, max_chars)
      end
    end
  end
  return nil
end

-- Build a body for a user-initiated bug report. If a KOReader crash log is
-- available, its tail is appended in a fenced code block so the report
-- carries the most recent traceback the device has on disk.
---@param opts { paths: string[]|nil }|nil
---@return string
function CrashReporter.buildBugReportBody(opts)
  local lines = {
    "## What happened?",
    "",
    "<!-- Describe what you were doing when the bug occurred. -->",
    "",
    "## Expected behavior",
    "",
    "<!-- What should have happened instead? -->",
    "",
  }
  local log = CrashReporter.readCrashLogTail(opts)
  if log then
    table.insert(lines, "## Last KOReader crash log")
    table.insert(lines, "")
    table.insert(lines, "```")
    table.insert(lines, log)
    table.insert(lines, "```")
  end
  return table.concat(lines, "\n")
end

-- Show the QR code modal for a generic user-initiated bug report. Pulls in
-- the tail of KOReader's crash log when one exists so a recent panic gets
-- attached automatically.
---@param opts { title: string|nil, paths: string[]|nil }|nil
function CrashReporter.showBugReportQr(opts)
  opts = opts or {}
  CrashReporter.showQrFor {
    title = opts.title or "Bug report",
    body  = CrashReporter.buildBugReportBody { paths = opts.paths },
  }
end

return CrashReporter
