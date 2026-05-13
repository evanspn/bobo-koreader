---@diagnostic disable: undefined-global
local F = require("utils/formatLibraryStats")

describe("formatLibraryStats.formatMonthDay", function()
  it("renders a UTC epoch as 'Mon D'", function()
    -- 2024-05-06 00:00 UTC = 1714953600
    assert.equal("May 6", F.formatMonthDay(1714953600))
    -- 2024-01-01 00:00 UTC = 1704067200
    assert.equal("Jan 1", F.formatMonthDay(1704067200))
  end)
end)

describe("formatLibraryStats.barHeights", function()
  it("scales tallest bar to max_fraction and renders zeroes as a floor", function()
    local weeks = {
      { start = 0, chapters = 0 },
      { start = 0, chapters = 5 },
      { start = 0, chapters = 10 },
    }
    local heights = F.barHeights(weeks, 1.0, 0.02)
    assert.equal(0.02, heights[1])
    assert.is_true(math.abs(heights[2] - 0.5) < 1e-9)
    assert.equal(1.0, heights[3])
  end)

  it("returns the zero floor for every week when nothing has been read", function()
    local heights = F.barHeights({
      { start = 0, chapters = 0 },
      { start = 0, chapters = 0 },
    }, 1.0, 0.05)
    assert.equal(0.05, heights[1])
    assert.equal(0.05, heights[2])
  end)
end)

describe("formatLibraryStats.formatLastRead", function()
  local original_time
  before_each(function()
    original_time = os.time
    -- Freeze "now" at 2024-05-13 12:00:00 UTC = 1715601600.
    os.time = function() return 1715601600 end
  end)
  after_each(function()
    os.time = original_time
  end)

  it("returns em-dash for nil", function()
    assert.equal("—", F.formatLastRead(nil))
  end)

  it("renders sub-minute as 'just now'", function()
    assert.equal("just now", F.formatLastRead(1715601590))
  end)

  it("renders sub-hour as N minutes ago", function()
    -- 30 minutes ago.
    assert.equal("30 min ago", F.formatLastRead(1715601600 - 30 * 60))
  end)

  it("renders the day-before as 'yesterday'", function()
    assert.equal("yesterday", F.formatLastRead(1715601600 - 24 * 3600))
  end)

  it("falls back to a date for older reads", function()
    -- 10 days ago.
    local ago = 1715601600 - 10 * 24 * 3600
    assert.equal(F.formatMonthDay(ago), F.formatLastRead(ago))
  end)
end)

describe("formatLibraryStats.formatInt", function()
  it("inserts thousands separators", function()
    assert.equal("0", F.formatInt(0))
    assert.equal("1", F.formatInt(1))
    assert.equal("999", F.formatInt(999))
    assert.equal("1,000", F.formatInt(1000))
    assert.equal("12,345", F.formatInt(12345))
    assert.equal("1,234,567", F.formatInt(1234567))
  end)
end)

describe("formatLibraryStats.headlineTiles", function()
  it("produces four formatted tiles", function()
    local tiles = F.headlineTiles({
      chapters_read = 1234,
      mangas_read = 7,
      current_streak_days = 4,
      longest_streak_days = 9,
    })
    assert.equal(4, #tiles)
    assert.equal("Chapters", tiles[1].label)
    assert.equal("1,234",    tiles[1].value)
    assert.equal("Mangas",   tiles[2].label)
    assert.equal("7",        tiles[2].value)
    assert.equal("Streak",   tiles[3].label)
    assert.equal("4 d",      tiles[3].value)
    assert.equal("Best run", tiles[4].label)
    assert.equal("9 d",      tiles[4].value)
  end)

  it("treats missing fields as zero", function()
    local tiles = F.headlineTiles({})
    assert.equal("0",   tiles[1].value)
    assert.equal("0",   tiles[2].value)
    assert.equal("0 d", tiles[3].value)
    assert.equal("0 d", tiles[4].value)
  end)
end)
