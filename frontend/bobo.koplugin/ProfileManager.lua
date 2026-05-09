local ButtonDialog = require("ui/widget/buttondialog")
local ButtonWidget = require("ui/widget/button")
local Blitbuffer = require("ffi/blitbuffer")
local ConfirmBox = require("ui/widget/confirmbox")
local CustomDialog = require("CustomDialog")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local MenuItem = require("MenuItem")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Screen = require("device").screen
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local _ = require("gettext+")

local Backend = require("Backend")
local ErrorDialog = require("ErrorDialog")
local Icons = require("Icons")

--- A single profile row: tap to switch, hold/ellipsis for context menu.
local ProfileItem = MenuItem:extend {
  on_tap = nil,
  on_hold = nil,
  profile = nil,
}

local BUTTON_FONT = Font:getFace("smallffont")

function ProfileItem:init()
  self.ges_events = {
    TapSelect = {
      GestureRange:new { ges = "tap", range = self.dimen },
    },
    HoldSelect = {
      GestureRange:new { ges = "hold", range = self.dimen },
    },
    Pan = {
      GestureRange:new { ges = "pan", range = self.dimen },
    },
  }

  local face = Font:getFace(self.font)
  local content_width = self.dimen.w - 2 * Size.padding.fullscreen
  local button_w = Screen:scaleBySize(30)
  local button_p = Screen:scaleBySize(4)
  local profile = self.profile

  local label = profile.name
  if profile.active then
    label = Icons.FA_CHECK .. "  " .. label
  end

  self._underline_container = UnderlineContainer:new {
    color = self.line_color,
    linesize = self.linesize,
    vertical_align = "center",
    padding = 0,
    dimen = Geom:new { x = 0, y = 0, w = content_width, h = self.dimen.h },
    HorizontalGroup:new {
      align = "center",
      OverlapGroup:new {
        dimen = Geom:new { w = content_width, h = self.dimen.h },
        LeftContainer:new {
          dimen = Geom:new { w = content_width, h = self.dimen.h },
          TextWidget:new {
            text = label,
            face = face,
            max_width = content_width - button_w - button_p * 2,
          },
        },
        RightContainer:new {
          dimen = Geom:new { w = content_width, h = self.dimen.h },
          ButtonWidget:new {
            text = Icons.FA_ELLIPSIS_VERTICAL,
            face = BUTTON_FONT,
            radius = 0,
            bordersize = 0,
            padding = button_p,
            width = button_w,
            callback = function()
              if self.on_hold then self.on_hold(profile) end
            end,
          },
        },
      },
    },
  }

  self[1] = self._underline_container
end

function ProfileItem:onTapSelect()
  if self.on_tap then self.on_tap() end
  return true
end

function ProfileItem:onHoldSelect()
  if self.on_hold then self.on_hold() end
  return true
end

--- @class ProfileManager: CustomDialog
---@diagnostic disable-next-line: redundant-parameter
local ProfileManager = CustomDialog:extend {}

--- Opens a dialog to create a new profile.
local function openCreateDialog(on_done)
  local dialog
  dialog = InputDialog:new {
    title = _("New Profile"),
    input_hint = _("Profile name"),
    buttons = {
      {
        {
          text = _("Cancel"),
          id = "close",
          callback = function()
            UIManager:close(dialog)
            on_done()
          end,
        },
        {
          text = _("Create"),
          is_enter_default = true,
          callback = function()
            local name = dialog:getInputText()
            UIManager:close(dialog)
            if not name or name:match("^%s*$") then
              on_done()
              return
            end
            local r = Backend.createProfile(name)
            if r.type == 'ERROR' then
              ErrorDialog:show(r.message)
              return
            end
            on_done()
          end,
        },
      },
    },
    close_callback = function() on_done() end,
  }
  UIManager:show(dialog)
  dialog:onShowKeyboard()
end

--- Shows the profile management dialog.
--- @param on_return_callback fun()|nil
function ProfileManager:fetchAndShow(on_return_callback)
  Trapper:wrap(function()
    local response = Backend.listProfiles()
    if response.type == 'ERROR' then
      ErrorDialog:show(response.message)
      return
    end
    ProfileManager:_buildAndShow(response.body, on_return_callback)
  end)
end

--- @private
function ProfileManager:_buildAndShow(profiles, on_return_callback)
  local current_dialog

  local function refresh()
    if current_dialog then UIManager:close(current_dialog) end
    Trapper:wrap(function()
      local r = Backend.listProfiles()
      if r.type == 'ERROR' then
        ErrorDialog:show(r.message)
        return
      end
      ProfileManager:_buildAndShow(r.body, on_return_callback)
    end)
  end

  local function on_switch(profile)
    if profile.active then return end
    if current_dialog then UIManager:close(current_dialog) end
    local r = Backend.switchProfile(profile.id)
    if r.type == 'ERROR' then
      ErrorDialog:show(r.message)
      return
    end
    UIManager:show(require("ui/widget/infomessage"):new {
      text = _("Switched to profile") .. ": " .. profile.name,
    })
    if on_return_callback then on_return_callback() end
  end

  local function on_context(profile)
    if current_dialog then UIManager:close(current_dialog) end
    local ctx
    ctx = ButtonDialog:new {
      title = profile.name,
      buttons = {
        {
          {
            text = Icons.FA_CHECK .. "  " .. _("Switch to this profile"),
            enabled = not profile.active,
            callback = function()
              UIManager:close(ctx)
              on_switch(profile)
            end,
          },
        },
        {
          {
            text = Icons.FA_TRASH .. "  " .. _("Delete"),
            enabled = not profile.active,
            callback = function()
              UIManager:close(ctx)
              UIManager:show(ConfirmBox:new {
                text = _("Delete profile") .. " \"" .. profile.name .. "\"?",
                ok_text = _("Delete"),
                ok_callback = function()
                  local r = Backend.deleteProfile(profile.id)
                  if r.type == 'ERROR' then
                    ErrorDialog:show(r.message)
                    return
                  end
                  refresh()
                end,
              })
            end,
          },
        },
      },
      tap_close_callback = refresh,
    }
    UIManager:show(ctx)
  end

  local options = {}
  table.insert(options, { _type = "new_profile" })
  if #profiles == 0 then
    table.insert(options, { _type = "empty" })
  else
    for _, p in ipairs(profiles) do
      table.insert(options, { _type = "profile", profile = p })
    end
  end

  local item_height = Screen:scaleBySize(50)

  ---@diagnostic disable-next-line: undefined-field
  current_dialog = ProfileManager:new {
    title = _("Profiles"),
    options = options,
    generate = function(option, max_width, _index)
      if option._type == "new_profile" then
        local btn = ButtonWidget:new {
          text = Icons.FA_PLUS .. "  " .. _("New Profile"),
          face = Font:getFace("smallffont"),
          radius = Size.radius.button,
          bordersize = Size.border.button,
          padding = Size.padding.button,
          width = max_width - Size.padding.button * 2,
          callback = function()
            if current_dialog then UIManager:close(current_dialog) end
            openCreateDialog(refresh)
          end,
        }
        btn.dimen = btn:getSize()
        return btn
      elseif option._type == "empty" then
        local tw = TextWidget:new {
          text = _("No profiles configured."),
          face = Font:getFace("smallffont"),
          fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }
        tw.dimen = tw:getSize()
        return tw
      else
        local p = option.profile
        local item = ProfileItem:new {
          profile = p,
          width = max_width,
          dimen = Geom:new { x = 0, y = 0, w = max_width, h = item_height },
          on_tap = function() on_switch(p) end,
          on_hold = function() on_context(p) end,
        }
        return item
      end
    end,
  }

  UIManager:show(current_dialog)
end

return ProfileManager
