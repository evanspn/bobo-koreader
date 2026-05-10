local BaseMenu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext+")

local Icons = require("Icons")

local Menu = BaseMenu:extend {
  with_context_menu = false,
}

-- KOReader's BaseMenu:onSetRotationMode reaches through `self._manager.ui.view`
-- to re-layout the surrounding ReaderUI / FileManager. Bobo's Menu-derived
-- views are shown standalone via `UIManager:show`, so `_manager` is nil and
-- that access crashes. Handle rotation ourselves: flip the screen rotation
-- and let `_recreate_func` rebuild the view at the new dimensions.
function Menu:onSetRotationMode(new_rotation)
  if new_rotation == nil or new_rotation == Screen:getRotationMode() then
    return false
  end
  Screen:setRotationMode(new_rotation)
  if self._recreate_func then
    UIManager:close(self)
    self._recreate_func()
    return true
  end
  return false
end

function Menu:init()
  if self.with_context_menu then
    self.align_baselines = true
  end

  self:updateOfflineSubtitle(true)

  BaseMenu.init(self)
end

function Menu:updateItems(select_number)
  for _, item in ipairs(self.item_table) do
    if self.with_context_menu and item.select_enabled ~= false then
      item.mandatory = (item.mandatory and (item.mandatory .. " ") or "") .. Icons.FA_ELLIPSIS_VERTICAL
    end
  end

  BaseMenu.updateItems(self, select_number)
end

function Menu:onMenuSelect(entry, pos)
  if entry.select_enabled == false then
    return true
  end

  local selected_context_menu = pos ~= nil and pos.x > 0.8

  if selected_context_menu then
    self:onContextMenuChoice(entry, pos)
  else
    self:onPrimaryMenuChoice(entry, pos)
  end
end

function Menu:onMenuHold(entry, pos)
  self:onContextMenuChoice(entry, pos)
end

--- Defaults to calling the entry's callback.
--- Override this function to change the behavior.
function Menu:onPrimaryMenuChoice(entry, pos)
  if entry.callback then
    entry.callback()
  end

  return true
end

function Menu:onContextMenuChoice(entry, pos)
end

---@private
function Menu:onNetworkConnected()
  logger.info("Menu:onNetworkConnected()")

  self:updateOfflineSubtitle()
end

---@private
function Menu:onNetworkDisconnected()
  logger.info("Menu:onNetworkDisconnected()")

  self:updateOfflineSubtitle()
end

---@private
function Menu:updateOfflineSubtitle(skip_reinit)
  if NetworkMgr:isConnected() then
    self.subtitle = nil
  else
    self.subtitle = Icons.WIFI_OFF .. " " .. _("Offline mode")
  end

  if not skip_reinit then
    BaseMenu.init(self)
  end
end

return Menu
