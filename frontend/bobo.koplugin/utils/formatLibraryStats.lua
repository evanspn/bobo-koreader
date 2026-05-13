--- Pure formatters for StatisticsView. Kept here so the math and the
--- string formatting can be tested under busted without pulling in the
--- KOReader widget tree.

local M = {}

--- @param epoch integer
--- @return string ISO-ish "May 6" using English month names.
function M.formatMonthDay(epoch)
  local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
  local t = os.date("!*t", epoch)
  return string.format("%s %d", months[t.month], t.day)
end

--- @param epoch integer    Unix timestamp at the start of the week.
--- @return string          "May 6" — week-start in the user's display style.
function M.formatWeekLabel(epoch)
  return M.formatMonthDay(epoch)
end

--- @param epoch integer|nil
--- @return string
function M.formatLastRead(epoch)
  if epoch == nil then return "—" end
  local now = os.time()
  local diff = now - epoch
  if diff < 0 then return M.formatMonthDay(epoch) end

  local minute = 60
  local hour = 60 * minute
  local day = 24 * hour

  if diff < minute then
    return "just now"
  elseif diff < hour then
    local m = math.floor(diff / minute)
    return string.format("%d min ago", m)
  elseif diff < day then
    local h = math.floor(diff / hour)
    return string.format("%d h ago", h)
  elseif diff < 7 * day then
    local d = math.floor(diff / day)
    if d == 1 then return "yesterday" end
    return string.format("%d days ago", d)
  end

  return M.formatMonthDay(epoch)
end

--- Compute a relative height for each bar (0..1) so the tallest bar
--- hits `max_fraction` and zero-count bars render as a small minimum
--- so the user can still see the placeholder.
---
--- @param weeks LibraryStatsWeek[]
--- @param max_fraction number   How much of the chart height the tallest bar fills.
--- @param zero_fraction number  Floor for zero-count weeks so the row reads as "off".
--- @return number[]             Per-week fractions, same length as `weeks`.
function M.barHeights(weeks, max_fraction, zero_fraction)
  max_fraction = max_fraction or 1.0
  zero_fraction = zero_fraction or 0.02

  local peak = 0
  for _, w in ipairs(weeks) do
    if w.chapters > peak then peak = w.chapters end
  end

  local out = {}
  for i, w in ipairs(weeks) do
    if peak == 0 then
      out[i] = zero_fraction
    elseif w.chapters == 0 then
      out[i] = zero_fraction
    else
      out[i] = math.max(zero_fraction, (w.chapters / peak) * max_fraction)
    end
  end
  return out
end

--- @param n integer
--- @return string  "1,234"-style grouped integer.
function M.formatInt(n)
  local s = tostring(n)
  local groups = {}
  local i = #s
  while i > 0 do
    table.insert(groups, 1, s:sub(math.max(1, i - 2), i))
    i = i - 3
  end
  return table.concat(groups, ",")
end

--- Build the headline tiles shown above the chart.
--- @param stats LibraryStats
--- @return { label: string, value: string }[]
function M.headlineTiles(stats)
  return {
    { label = "Chapters",  value = M.formatInt(stats.chapters_read or 0) },
    { label = "Mangas",    value = M.formatInt(stats.mangas_read or 0) },
    { label = "Streak",    value = string.format("%d d", stats.current_streak_days or 0) },
    { label = "Best run",  value = string.format("%d d", stats.longest_streak_days or 0) },
  }
end

return M
