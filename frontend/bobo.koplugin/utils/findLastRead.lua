local isBeforeChapter = require("utils/isBeforeChapter")

---@param chapters Chapter[]
---@return Chapter?
local function findLastRead(chapters)
  if #chapters == 0 then
    return nil
  end

  -- Pick the chapter the user most recently touched. We compare by `last_read`
  -- timestamp so that an accidentally opened (newer) chapter doesn't beat the
  -- chapter the user is actually progressing through after they unmark it.
  -- A chapter with `read=true` but no timestamp (legacy data) still counts as
  -- a candidate, ordered behind anything with a real timestamp.
  local best = nil
  for _, chapter in ipairs(chapters) do
    if chapter.last_read ~= nil or chapter.read then
      if best == nil or (chapter.last_read or 0) > (best.last_read or 0) then
        best = chapter
      end
    end
  end

  if best ~= nil then
    return best
  end

  local smallest = chapters[1]
  for i = 2, #chapters do
    if isBeforeChapter(chapters[i], smallest) then
      smallest = chapters[i]
    end
  end

  return smallest
end

return findLastRead
