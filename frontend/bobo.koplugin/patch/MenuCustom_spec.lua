---@diagnostic disable: undefined-global, undefined-field

-- Regression test for the landscape-rotation crash where
-- patch/MenuCustom.lua:_recalculateDimen called Math.floor (the optmath
-- module, which has no `floor`) instead of math.floor (Lua stdlib).
--
-- The crash only triggers in landscape with a gridded layout (columns > 1),
-- because that's the only path through _recalculateDimen that hits the
-- offending line.

local function noop() end

local screen_state = { width = 1264, height = 950 }
local screen_stub = {
  getWidth    = function() return screen_state.width end,
  getHeight   = function() return screen_state.height end,
  scaleBySize = function(_, n) return n end,
}

local function stub_class(proto)
  local cls = proto or {}
  cls.__index = cls
  cls.extend = function(self, t)
    local sub = setmetatable(t or {}, { __index = self })
    sub.__index = sub
    sub.extend  = self.extend
    sub.new     = function(_, opts)
      local inst = setmetatable(opts or {}, sub)
      if inst.init then inst:init() end
      return inst
    end
    return sub
  end
  return cls
end

-- bobo's widgets/Menu — only the bits MenuCustom touches at load time / in
-- _recalculateDimen.
local menu_stub = stub_class({
  _recalculateDimen = noop,
  getItemFontSize   = function() return 20 end,
  getMenuText       = function(item) return item and item.text or "" end,
})

package.loaded["widgets/Menu"]              = menu_stub
package.loaded["device"]                    = { screen = screen_stub }
package.loaded["ui/uimanager"]              = { setDirty = noop }
package.loaded["ui/size"]                   = { line = { thin = 1 } }
-- Mirror the real optmath: it exports round/roundPercent/roundAwayFromZero
-- but NOT floor. Tests will fail loudly if MenuCustom regresses to Math.floor.
package.loaded["optmath"]                   = {
  round              = function(n) return math.floor(n + 0.5) end,
  roundPercent       = function(p) return math.floor(p * 10000) / 10000 end,
  roundAwayFromZero  = function(n) return n > 0 and math.ceil(n) or math.floor(n) end,
}
package.loaded["ui/geometry"]               = { new = function(_, opts) return opts end }
package.loaded["ui/widget/horizontalgroup"] = stub_class({})

_G.G_reader_settings = {
  readSetting = function() return nil end,
  isTrue      = function() return false end,
}

package.loaded["patch/MenuCustom"] = nil
local MenuCustom = require("patch/MenuCustom")

local function make_instance(overrides)
  local inst = {
    grid_columns    = 3,
    inner_dimen     = { w = screen_state.width, h = screen_state.height },
    title_bar       = nil,
    page_info       = nil,
    items_font_size = 20,
    item_table      = {},
    getPageNumber   = function() return 1 end,
  }
  for k, v in pairs(overrides or {}) do inst[k] = v end
  return setmetatable(inst, { __index = MenuCustom })
end

describe("patch/MenuCustom:_recalculateDimen", function()
  it("does not crash in landscape with a gridded layout", function()
    -- Landscape: width > height.
    screen_state.width  = 1264
    screen_state.height = 950
    local instance = make_instance({
      inner_dimen = { w = 1264, h = 950 },
    })

    -- Pre-fix this raised:
    --   "attempt to call field 'floor' (a nil value)"
    -- because the landscape branch at line 197 used Math.floor (optmath has
    -- no `floor`) instead of math.floor.
    assert.has_no.errors(function()
      instance:_recalculateDimen(true)
    end)

    assert.is_not_nil(instance.perpage)
    assert.is_true(instance.perpage > 0)
    assert.is_not_nil(instance.item_dimen)
    assert.is_false(instance.portrait_mode)
  end)

  it("computes dimensions in portrait gridded layout", function()
    -- Portrait: height >= width.
    screen_state.width  = 950
    screen_state.height = 1264
    local instance = make_instance({
      inner_dimen = { w = 950, h = 1264 },
    })

    assert.has_no.errors(function()
      instance:_recalculateDimen(true)
    end)

    assert.is_true(instance.portrait_mode)
    assert.is_not_nil(instance.perpage)
    assert.is_true(instance.perpage > 0)
  end)

  -- Regression for the rotation crash that kept reappearing despite the
  -- Math.floor → math.floor fix: users reported `attempt to call field
  -- 'floor' (a nil value)` at the same MenuCustom line on stale installs
  -- and on devices where the global `math` table got tampered with at
  -- runtime. MenuCustom now binds floor/ceil to module-level locals at
  -- load time, so once the module is loaded, mutating the global `math`
  -- table can no longer break _recalculateDimen.
  it("survives runtime tamper of the global math table", function()
    screen_state.width  = 1264
    screen_state.height = 950
    local instance = make_instance({
      inner_dimen = { w = 1264, h = 950 },
    })

    local saved_floor = math.floor
    local saved_ceil  = math.ceil
    math.floor = nil
    math.ceil  = nil

    local ok, err = pcall(function()
      instance:_recalculateDimen(true)
    end)

    math.floor = saved_floor
    math.ceil  = saved_ceil

    assert.is_true(ok, "should not crash even when math.floor is wiped: " .. tostring(err))
    assert.is_not_nil(instance.perpage)
    assert.is_true(instance.perpage > 0)
  end)
end)
