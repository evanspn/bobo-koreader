-- A circular profile avatar: filled colored disc with the first character of
-- the profile name centered on top. Drawing is done with `bb:paintCircle`
-- inside our own paintTo so it works regardless of FrameContainer's clipping
-- behavior on a given KOReader version.

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")

--- The palette of available profile colors. Stored by stable string id so the
--- backend can persist `color = "blue"` without coupling to RGB values, and we
--- can tweak the actual hue here later without invalidating saved data.
---
--- On grayscale e-ink devices KOReader's Blitbuffer converts these RGB values
--- to a luma-mapped gray automatically, so each colour stays visually distinct
--- even on a Kobo Clara.
local PALETTE_DEFS = {
  { id = "red",    rgb = { 0xC0, 0x39, 0x2B } },
  { id = "orange", rgb = { 0xE6, 0x82, 0x2E } },
  { id = "yellow", rgb = { 0xD4, 0xB1, 0x06 } },
  { id = "green",  rgb = { 0x27, 0x86, 0x4B } },
  { id = "teal",   rgb = { 0x17, 0x82, 0x91 } },
  { id = "blue",   rgb = { 0x1F, 0x6F, 0xB9 } },
  { id = "purple", rgb = { 0x6F, 0x42, 0xC1 } },
  { id = "pink",   rgb = { 0xC4, 0x36, 0x7B } },
}

local PALETTE = {}
for _i, entry in ipairs(PALETTE_DEFS) do
  PALETTE[entry.id] = Blitbuffer.ColorRGB24(entry.rgb[1], entry.rgb[2], entry.rgb[3])
end

local DEFAULT_COLOR = "blue"

--- @class Avatar : Widget
local Avatar = Widget:extend {
  --- diameter in scaled px. Caller provides a value already passed through
  --- Screen:scaleBySize.
  size = nil,
  --- profile display name. The first character is rendered centered.
  name = nil,
  --- color id from PALETTE (e.g. "red"). When nil, derived deterministically
  --- from `name` so two profiles with the same name always look the same and
  --- different names tend to look different.
  color = nil,
}

function Avatar:init()
  assert(self.size, "Avatar.size must be provided (in scaled px)")
  self.dimen = Geom:new { x = 0, y = 0, w = self.size, h = self.size }
end

function Avatar:getSize()
  return self.dimen
end

--- Returns a list of available color ids in display order.
--- @return string[]
function Avatar.availableColors()
  local out = {}
  for _i, entry in ipairs(PALETTE_DEFS) do
    out[#out + 1] = entry.id
  end
  return out
end

--- Returns the Blitbuffer color value for a given color id, falling back to
--- the default if the id isn't recognised.
function Avatar.colorValue(color_id)
  return PALETTE[color_id] or PALETTE[DEFAULT_COLOR]
end

--- Deterministically picks a color id from a string. Same input always yields
--- the same color so newly created profiles get a stable, distinct look without
--- requiring the caller to choose one explicitly.
--- @param name string
--- @return string color id
function Avatar.colorFromName(name)
  if not name or name == "" then return DEFAULT_COLOR end
  local hash = 0
  for i = 1, #name do
    hash = (hash * 31 + name:byte(i)) % 1000003
  end
  return PALETTE_DEFS[(hash % #PALETTE_DEFS) + 1].id
end

--- Returns the uppercase first letter of a name, or "?" if empty.
--- Uses string.sub on bytes — non-ASCII names will have their first BYTE
--- shown which is fine for the Latin scripts this plugin targets and also
--- avoids pulling in utf8 dependencies on older LuaJIT.
function Avatar.initialFor(name)
  if not name or name == "" then return "?" end
  local first = name:sub(1, 1):upper()
  if first == "" then return "?" end
  return first
end

function Avatar:paintTo(bb, x, y)
  local radius = math.floor(self.size / 2)
  local cx = x + radius
  local cy = y + radius

  local color_id = self.color or Avatar.colorFromName(self.name or "")
  local fill = Avatar.colorValue(color_id)

  bb:paintCircle(cx, cy, radius, fill)

  local letter = Avatar.initialFor(self.name or "")
  local face = Font:getFace("tfont", math.floor(self.size * 0.42))
  local text_widget = TextWidget:new {
    text = letter,
    face = face,
    fgcolor = Blitbuffer.COLOR_WHITE,
  }
  local ts = text_widget:getSize()
  local tx = x + math.floor((self.size - ts.w) / 2)
  local ty = y + math.floor((self.size - ts.h) / 2)
  text_widget:paintTo(bb, tx, ty)
  text_widget:free()
end

return Avatar
