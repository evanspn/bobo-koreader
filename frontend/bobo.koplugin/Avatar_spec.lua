---@diagnostic disable: undefined-global, undefined-field

-- Stub just enough of KOReader for Avatar.lua to load. Avatar's pure logic
-- (colorFromName, initialFor, availableColors, colorValue) is what we test;
-- the painting path is not exercised here.

local function stub_class()
  local cls = {}
  cls.__index = cls
  cls.extend = function(self, t)
    local sub = setmetatable(t or {}, { __index = self })
    sub.__index = sub
    sub.extend = self.extend
    sub.new = function(_, opts)
      local inst = setmetatable(opts or {}, sub)
      if inst.init then inst:init() end
      return inst
    end
    return sub
  end
  return cls
end

package.loaded["ffi/blitbuffer"] = {
  ColorRGB24 = function(r, g, b) return { r = r, g = g, b = b } end,
  COLOR_WHITE = "WHITE",
}
package.loaded["ui/font"] = { getFace = function() return {} end }
package.loaded["ui/geometry"] = {
  new = function(_, t) return t or {} end,
}
package.loaded["ui/widget/textwidget"] = stub_class()
package.loaded["ui/widget/widget"] = stub_class()

package.loaded["Avatar"] = nil
local Avatar = require("Avatar")

describe("Avatar.colorFromName", function()
  it("returns a valid palette id for any non-empty input", function()
    local available = {}
    for _i, c in ipairs(Avatar.availableColors()) do available[c] = true end

    for _i, name in ipairs({ "Bob", "Alice", "Z", "very long name with spaces", "1234" }) do
      local color = Avatar.colorFromName(name)
      assert.is_true(available[color], "expected colorFromName to return a palette id, got: " .. tostring(color))
    end
  end)

  it("is deterministic across calls", function()
    assert.equal(Avatar.colorFromName("Bob"), Avatar.colorFromName("Bob"))
    assert.equal(Avatar.colorFromName(""), Avatar.colorFromName(""))
  end)

  it("falls back to a valid color on empty input", function()
    local available = {}
    for _i, c in ipairs(Avatar.availableColors()) do available[c] = true end
    assert.is_true(available[Avatar.colorFromName("")])
    assert.is_true(available[Avatar.colorFromName(nil)])
  end)
end)

describe("Avatar.initialFor", function()
  it("returns the uppercase first letter of a name", function()
    assert.equal("B", Avatar.initialFor("bob"))
    assert.equal("A", Avatar.initialFor("Alice"))
  end)

  it("returns '?' for empty or nil input", function()
    assert.equal("?", Avatar.initialFor(""))
    assert.equal("?", Avatar.initialFor(nil))
  end)
end)

describe("Avatar.availableColors", function()
  it("returns a non-empty list of palette ids", function()
    local list = Avatar.availableColors()
    assert.is_true(#list > 0, "palette must have at least one color")
    for _i, color in ipairs(list) do
      assert.is_string(color)
      assert.is_not.equal("", color)
    end
  end)

  it("includes the documented colors", function()
    local set = {}
    for _i, c in ipairs(Avatar.availableColors()) do set[c] = true end
    -- We don't pin the full set (palette may grow) but these are the named
    -- ones we expect callers / persisted profiles to rely on.
    for _i, expected in ipairs({ "red", "blue", "green", "purple" }) do
      assert.is_true(set[expected], "palette should contain " .. expected)
    end
  end)
end)

describe("Avatar.colorValue", function()
  it("returns a Blitbuffer color for a known id", function()
    local v = Avatar.colorValue("red")
    assert.is_table(v)
    assert.is_number(v.r)
  end)

  it("falls back to the default color for an unknown id", function()
    local fallback = Avatar.colorValue("not-a-real-color")
    assert.is_table(fallback)
    assert.is_number(fallback.r)
  end)
end)
