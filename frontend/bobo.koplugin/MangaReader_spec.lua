---@diagnostic disable: undefined-global, undefined-field

-- Stubs for KOReader modules MangaReader.lua requires at load time.

local function noop() end

package.loaded["docsettings"]                            = { open = function(_, path) return { readSetting = function() end, saveSetting = noop, flush = noop } end }
package.loaded["apps/reader/readerui"]                   = { instance = nil }
package.loaded["ui/uimanager"]                           = { nextTick = function(_, fn) fn() end, show = noop, close = noop }
package.loaded["ui/widget/container/widgetcontainer"]    = { new = function(_, t) return t or {} end }
package.loaded["ui/widget/confirmbox"]                   = {}
package.loaded["logger"]                                 = { info = noop, warn = noop, err = noop, error = noop }
package.loaded["gettext+"]                               = function(s) return s end
package.loaded["testing"]                                = { emitEvent = noop, init = noop }

-- Backend stub — tests override individual functions per-test.
local backend_stub = {}
package.loaded["Backend"] = backend_stub

-- DownloadChapter stub factory. Returns a job whose start() and poll() are
-- controllable per-test.
local function make_job(opts)
  opts = opts or {}
  return {
    source_id   = opts.source_id or "src",
    manga_id    = opts.manga_id  or "manga",
    id          = opts.id        or "ch1",
    chapter_num = opts.chapter_num or 1,
    started     = opts.started or false,
    result      = opts.result,
    start = function(self)
      self.started = true
      self.start_result = opts.start_result or { type = "SUCCESS" }
      return self.start_result
    end,
    poll = function(self)
      if self.result then return self.result end
      return { type = "PENDING" }
    end,
    runUntilCompletion = function(self)
      return self.result or { type = "PENDING" }
    end,
    requestCancellation = function() end,
  }
end

local download_chapter_stub = {
  new = function(_, source_id, manga_id, chapter_id, chapter_num)
    return make_job({ source_id = source_id, manga_id = manga_id, id = chapter_id, chapter_num = chapter_num })
  end
}
package.loaded["jobs/DownloadChapter"] = download_chapter_stub

-- Use the real findNextChapter (pure Lua, no KOReader deps).
-- (No need to stub it — it has its own spec.)

-- Force fresh load so it picks up the stubs.
package.loaded["MangaReader"] = nil
local MangaReader = require("MangaReader")

-- ─── helpers ──────────────────────────────────────────────────────────────────

local function make_chapter(id, chapter_num, opts)
  opts = opts or {}
  return {
    id          = id,
    source_id   = opts.source_id or "src",
    manga_id    = opts.manga_id  or "manga",
    chapter_num = chapter_num,
    downloaded  = opts.downloaded or false,
    locked      = opts.locked or false,
  }
end

local function reset_manga_reader()
  MangaReader.preload_jobs             = {}
  MangaReader.all_chapters             = {}
  MangaReader.preload_count            = 0
  MangaReader.preload_on_progress      = false
  MangaReader._progress_preload_triggered = false
  MangaReader._last_saved_page         = nil
  MangaReader.is_showing               = false
  MangaReader.chapter                  = nil
end

-- ─── prunePreloadJobs ─────────────────────────────────────────────────────────

describe("MangaReader:prunePreloadJobs", function()
  before_each(reset_manga_reader)

  it("keeps a successful job in preload_jobs so onEndOfBook can reuse it", function()
    local job = make_job({ id = "ch2", result = { type = "SUCCESS", body = { "/tmp/ch2.cbz", {} } } })
    MangaReader.preload_jobs["ch2"] = job

    MangaReader:prunePreloadJobs()

    assert.is_not_nil(MangaReader.preload_jobs["ch2"], "successful job must NOT be pruned")
  end)

  it("marks the chapter as downloaded when its job succeeds", function()
    local ch = make_chapter("ch2", 2)
    MangaReader.all_chapters = { make_chapter("ch1", 1), ch }
    local job = make_job({ id = "ch2", result = { type = "SUCCESS", body = { "/tmp/ch2.cbz", {} } } })
    MangaReader.preload_jobs["ch2"] = job

    MangaReader:prunePreloadJobs()

    assert.is_true(ch.downloaded)
  end)

  it("removes an errored job from preload_jobs", function()
    local job = make_job({ id = "ch2", result = { type = "ERROR", message = "network failure" } })
    MangaReader.preload_jobs["ch2"] = job

    MangaReader:prunePreloadJobs()

    assert.is_nil(MangaReader.preload_jobs["ch2"], "errored job must be pruned")
  end)

  it("leaves a pending job untouched", function()
    local job = make_job({ id = "ch2" }) -- result is nil → poll() returns PENDING
    MangaReader.preload_jobs["ch2"] = job

    MangaReader:prunePreloadJobs()

    assert.is_not_nil(MangaReader.preload_jobs["ch2"])
  end)
end)

-- ─── startPreloading ──────────────────────────────────────────────────────────

describe("MangaReader:startPreloading", function()
  before_each(function()
    reset_manga_reader()
    backend_stub.createDownloadChapterJob = function(_, source_id, manga_id, chapter_id, _)
      return { type = "SUCCESS", body = chapter_id .. "-job-id" }
    end
  end)

  it("creates a job for the next chapter and stores it in preload_jobs", function()
    local ch1 = make_chapter("ch1", 1)
    local ch2 = make_chapter("ch2", 2)
    MangaReader.all_chapters = { ch1, ch2 }
    MangaReader.preload_count = 1

    MangaReader:startPreloading(ch1)

    assert.is_not_nil(MangaReader.preload_jobs["ch2"])
  end)

  it("does not create a duplicate job when one already exists", function()
    local ch1 = make_chapter("ch1", 1)
    local ch2 = make_chapter("ch2", 2)
    MangaReader.all_chapters = { ch1, ch2 }
    MangaReader.preload_count = 1

    local existing_job = make_job({ id = "ch2" })
    MangaReader.preload_jobs["ch2"] = existing_job

    local calls = 0
    backend_stub.createDownloadChapterJob = function()
      calls = calls + 1
      return { type = "SUCCESS", body = "ch2-job-id" }
    end

    MangaReader:startPreloading(ch1)

    assert.equal(0, calls, "should not create a new job when one already exists")
    assert.equal(existing_job, MangaReader.preload_jobs["ch2"])
  end)

  it("skips already-downloaded chapters and preloads the one after", function()
    local ch1 = make_chapter("ch1", 1)
    local ch2 = make_chapter("ch2", 2, { downloaded = true })
    local ch3 = make_chapter("ch3", 3)
    MangaReader.all_chapters = { ch1, ch2, ch3 }
    MangaReader.preload_count = 2

    MangaReader:startPreloading(ch1)

    -- ch2 is downloaded → skip; should still preload ch3 within count=2
    assert.is_not_nil(MangaReader.preload_jobs["ch3"])
  end)

  it("respects an explicit count argument, ignoring preload_count", function()
    local ch1 = make_chapter("ch1", 1)
    local ch2 = make_chapter("ch2", 2)
    local ch3 = make_chapter("ch3", 3)
    MangaReader.all_chapters = { ch1, ch2, ch3 }
    MangaReader.preload_count = 0 -- disabled globally

    MangaReader:startPreloading(ch1, 1) -- explicit count overrides

    assert.is_not_nil(MangaReader.preload_jobs["ch2"])
    assert.is_nil(MangaReader.preload_jobs["ch3"]) -- count=1, stop after ch2
  end)

  it("does not preload past the last chapter", function()
    local ch1 = make_chapter("ch1", 1)
    MangaReader.all_chapters = { ch1 }
    MangaReader.preload_count = 3

    MangaReader:startPreloading(ch1)

    assert.equal(0, (function()
      local n = 0
      for _ in pairs(MangaReader.preload_jobs) do n = n + 1 end
      return n
    end)())
  end)
end)

-- ─── onPageUpdate / 80% progress trigger ──────────────────────────────────────

describe("MangaReader:onPageUpdate progress preload", function()
  before_each(function()
    reset_manga_reader()
    backend_stub.saveReadingPosition = function() end

    MangaReader.is_showing      = true
    MangaReader.preload_on_progress = true
    MangaReader.preload_count   = 0  -- on-open preload disabled; only progress matters
    MangaReader.chapter         = make_chapter("ch1", 1)

    local ch2 = make_chapter("ch2", 2)
    MangaReader.all_chapters    = { MangaReader.chapter, ch2 }

    -- Fake a ReaderUI with a known page count.
    package.loaded["apps/reader/readerui"].instance = {
      document = { getNbPages = function() return 10 end },
      rolling  = nil,
    }
  end)

  after_each(function()
    package.loaded["apps/reader/readerui"].instance = nil
  end)

  it("triggers a preload job when the reader crosses 80% (page 8 of 10)", function()
    MangaReader:onPageUpdate(8)

    assert.is_not_nil(MangaReader.preload_jobs["ch2"], "job for ch2 should be created at 80%")
  end)

  it("does not trigger below 80% (page 7 of 10)", function()
    MangaReader:onPageUpdate(7)

    assert.is_nil(MangaReader.preload_jobs["ch2"], "no job should be created below 80%")
  end)

  it("only triggers once even when called multiple times past 80%", function()
    MangaReader:onPageUpdate(8)
    local first_job = MangaReader.preload_jobs["ch2"]
    assert.is_not_nil(first_job)

    MangaReader:onPageUpdate(9)
    MangaReader:onPageUpdate(10)

    -- Same job object — startPreloading was not called again
    assert.equal(first_job, MangaReader.preload_jobs["ch2"])
  end)

  it("uses math.max(1, preload_count) so trigger fires even with preload_count=0", function()
    MangaReader.preload_count = 0
    MangaReader:onPageUpdate(8)

    -- With count=0 and the math.max fix, should still preload at least 1 chapter.
    assert.is_not_nil(MangaReader.preload_jobs["ch2"], "job should fire even when preload_count=0")
  end)
end)

-- ─── successful job stays usable after pruning ────────────────────────────────

describe("preload job lifecycle: prune then reuse", function()
  before_each(function()
    reset_manga_reader()
    backend_stub.saveReadingPosition = function() end
    backend_stub.createDownloadChapterJob = function(_, _, _, chapter_id, _)
      return { type = "SUCCESS", body = chapter_id .. "-job" }
    end
    package.loaded["apps/reader/readerui"].instance = {
      document = { getNbPages = function() return 10 end },
      rolling  = nil,
    }
  end)

  after_each(function()
    package.loaded["apps/reader/readerui"].instance = nil
  end)

  it("job result is still accessible after multiple prune cycles", function()
    local ch1 = make_chapter("ch1", 1)
    local ch2 = make_chapter("ch2", 2)
    MangaReader.all_chapters   = { ch1, ch2 }
    MangaReader.is_showing     = true
    MangaReader.preload_on_progress = true
    MangaReader.chapter        = ch1

    -- Trigger preload at 80%
    MangaReader:onPageUpdate(8)
    local job = MangaReader.preload_jobs["ch2"]
    assert.is_not_nil(job, "job should exist after 80% trigger")

    -- Simulate job completing
    job.result = { type = "SUCCESS", body = { "/tmp/ch2.cbz", {} } }

    -- Multiple page turns — each calls prunePreloadJobs internally
    MangaReader:onPageUpdate(9)
    MangaReader:onPageUpdate(10)

    -- Job must still be in the table so onEndOfBook can find it
    assert.is_not_nil(MangaReader.preload_jobs["ch2"],
      "completed job must survive prune cycles so end-of-book can reuse it")

    -- And the result must still be readable
    assert.equal("SUCCESS", MangaReader.preload_jobs["ch2"].result.type)
    assert.equal("/tmp/ch2.cbz", MangaReader.preload_jobs["ch2"].result.body[1])
  end)
end)
