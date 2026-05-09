---@diagnostic disable: undefined-global
local isBeforeChapter = require('utils/isBeforeChapter')

local function ch(fields)
  return {
    volume_num  = fields.v,
    chapter_num = fields.c,
    index       = fields.i or 1,
  }
end

describe('isBeforeChapter', function()
  it('orders by volume number when both present and different', function()
    assert.is_true(isBeforeChapter(ch({ v = 1, c = 5, i = 2 }), ch({ v = 2, c = 1, i = 1 })))
    assert.is_false(isBeforeChapter(ch({ v = 2, c = 1, i = 1 }), ch({ v = 1, c = 5, i = 2 })))
  end)

  it('orders by chapter number when volumes are equal', function()
    assert.is_true(isBeforeChapter(ch({ v = 1, c = 1, i = 2 }), ch({ v = 1, c = 2, i = 1 })))
    assert.is_false(isBeforeChapter(ch({ v = 1, c = 2, i = 1 }), ch({ v = 1, c = 1, i = 2 })))
  end)

  it('falls back to source index order when chapter numbers are equal', function()
    -- Source order is newest-first, so higher index = older = comes first
    assert.is_true(isBeforeChapter(ch({ c = 1, i = 2 }), ch({ c = 1, i = 1 })))
  end)

  it('falls back to index when chapter number is absent', function()
    assert.is_true(isBeforeChapter(ch({ i = 2 }), ch({ i = 1 })))
  end)

  it('volumes take precedence over chapter numbers', function()
    -- vol 1 ch 99 is still before vol 2 ch 1
    assert.is_true(isBeforeChapter(ch({ v = 1, c = 99, i = 2 }), ch({ v = 2, c = 1, i = 1 })))
  end)
end)
