--- Pure formatters for the MangaInfoWidget statistics row.
--- Kept as a separate module so the formatting logic is testable
--- without pulling in KOReader widget machinery.

local M = {}

--- @param chapters_read integer|nil
--- @param total_chapters integer|nil
--- @return string
function M.formatChapters(chapters_read, total_chapters)
  if total_chapters == nil or total_chapters <= 0 then
    return "—"
  end
  return string.format("%d / %d", chapters_read or 0, total_chapters)
end

--- @param chapter_number number|nil
--- @return string
function M.formatCurrentChapter(chapter_number)
  if chapter_number == nil then
    return "—"
  end
  -- Drop the trailing zeros for whole chapter numbers ("Ch. 6"), but keep
  -- decimals for half-chapters ("Ch. 6.5").
  if chapter_number == math.floor(chapter_number) then
    return string.format("Ch. %d", chapter_number)
  end
  -- Trim a trailing zero off "Ch. 6.50" → "Ch. 6.5".
  local formatted = string.format("%.2f", chapter_number)
  formatted = formatted:gsub("0$", ""):gsub("%.$", "")
  return "Ch. " .. formatted
end

--- @param percentage number  -- 0.0 .. 1.0
--- @return string
function M.formatPercentage(percentage)
  if percentage == nil then
    return "0\xE2\x80\xAF%"
  end
  return string.format("%d\xE2\x80\xAF%%", math.floor(percentage * 100 + 0.5))
end

return M
