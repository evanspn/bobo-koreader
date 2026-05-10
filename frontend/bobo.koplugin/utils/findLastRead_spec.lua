---@diagnostic disable: undefined-global, undefined-field
local findLastRead = require('utils/findLastRead')

--- @return Chapter
local function makeChapter(fields)
  local chapter = {
    source_id = 'test',
    manga_id = 'test',
    downloaded = false,
    read = false,
    id = 'id-' .. (fields.chapter_num or 'unknown'),
    scanlator = 'test',
  }

  for key, value in pairs(fields) do
    chapter[key] = value
  end

  return chapter
end

describe('findLastRead', function()
  it('returns nil for an empty chapter list', function()
    assert.is_nil(findLastRead({}))
  end)

  it('returns the smallest chapter when nothing has been read', function()
    -- Source order is newest -> oldest, so chapter 1 is last in the array.
    local chapters = {
      makeChapter({ chapter_num = 3 }),
      makeChapter({ chapter_num = 2 }),
      makeChapter({ chapter_num = 1 }),
    }

    local last = findLastRead(chapters)

    assert.is_not_nil(last)
    ---@diagnostic disable-next-line: need-check-nil
    assert.equal(1, last.chapter_num)
  end)

  it('returns the chapter with the most recent last_read timestamp', function()
    -- Chapter 5 is the user's real progress; chapter 50 was opened later
    -- (e.g. accidentally) and has a more recent timestamp. The newer-first
    -- source ordering used to make findLastRead pick whichever appeared
    -- earlier in the array regardless of timestamp.
    local chapters = {
      makeChapter({ chapter_num = 50, last_read = 200, read = false }),
      makeChapter({ chapter_num = 5,  last_read = 100, read = true  }),
    }

    local last = findLastRead(chapters)

    assert.is_not_nil(last)
    ---@diagnostic disable-next-line: need-check-nil
    assert.equal(50, last.chapter_num)
  end)

  it('ignores chapters whose last_read was cleared by an unmark', function()
    -- After unmarking the accidentally opened chapter (50), its last_read is
    -- nil and `read` is false. Resume must fall back to the chapter the user
    -- actually finished (5).
    local chapters = {
      makeChapter({ chapter_num = 50, last_read = nil, read = false }),
      makeChapter({ chapter_num = 5,  last_read = 100, read = true  }),
    }

    local last = findLastRead(chapters)

    assert.is_not_nil(last)
    ---@diagnostic disable-next-line: need-check-nil
    assert.equal(5, last.chapter_num)
  end)

  it('still returns a chapter marked read even with no timestamp', function()
    local chapters = {
      makeChapter({ chapter_num = 3 }),
      makeChapter({ chapter_num = 2, read = true, last_read = nil }),
      makeChapter({ chapter_num = 1 }),
    }

    local last = findLastRead(chapters)

    assert.is_not_nil(last)
    ---@diagnostic disable-next-line: need-check-nil
    assert.equal(2, last.chapter_num)
  end)

  it('prefers a chapter with a real timestamp over one only marked read', function()
    local chapters = {
      makeChapter({ chapter_num = 2, read = true, last_read = nil }),
      makeChapter({ chapter_num = 1, read = true, last_read = 500 }),
    }

    local last = findLastRead(chapters)

    assert.is_not_nil(last)
    ---@diagnostic disable-next-line: need-check-nil
    assert.equal(1, last.chapter_num)
  end)
end)
