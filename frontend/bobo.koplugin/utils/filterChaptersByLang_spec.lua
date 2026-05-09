---@diagnostic disable: undefined-global
local filterChaptersByLang = require('utils/filterChaptersByLang')

local function chapter(lang)
  return { id = lang or 'unknown', lang = lang }
end

describe('filterChaptersByLang', function()
  it('returns all chapters when langs_selected is empty', function()
    local chapters = { chapter('en'), chapter('ja'), chapter('fr') }
    local result = filterChaptersByLang(chapters, {})
    assert.equal(3, #result)
  end)

  it('returns all chapters when langs_selected is nil', function()
    local chapters = { chapter('en'), chapter('ja') }
    local result = filterChaptersByLang(chapters, nil)
    assert.equal(2, #result)
  end)

  it('filters to only selected language', function()
    local chapters = { chapter('en'), chapter('ja'), chapter('fr') }
    local result = filterChaptersByLang(chapters, { 'en' })
    assert.equal(1, #result)
    assert.equal('en', result[1].lang)
  end)

  it('keeps chapters matching any selected language', function()
    local chapters = { chapter('en'), chapter('ja'), chapter('fr') }
    local result = filterChaptersByLang(chapters, { 'en', 'ja' })
    assert.equal(2, #result)
  end)

  it('returns empty list when no chapters match', function()
    local chapters = { chapter('fr'), chapter('de') }
    local result = filterChaptersByLang(chapters, { 'en' })
    assert.equal(0, #result)
  end)

  it('treats nil chapter.lang as unknown', function()
    local chapters = { chapter(nil), chapter('en') }
    local result = filterChaptersByLang(chapters, { 'unknown' })
    assert.equal(1, #result)
  end)
end)
