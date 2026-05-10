local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local _ = require("gettext+")

local ErrorDialog = {}

---@param message string
---@param try_refresh fun()?
---@param report_callback fun()? When set, adds a "Report" button that the
---  caller wires to a crash-report flow (typically a QR code).
function ErrorDialog:show(message, try_refresh, report_callback)
  local dialog
  local other_buttons = nil
  if report_callback then
    other_buttons = { {
      {
        text = _("Report"),
        callback = function()
          UIManager:close(dialog)
          report_callback()
        end,
      },
    } }
  end

  if try_refresh then
    dialog = ConfirmBox:new({
      text = message,
      icon = "notice-warning",
      ok_text = _("Retry"),
      ok_callback = try_refresh,
      cancel_callback = function()
        UIManager:close(dialog)
      end,
      other_buttons = other_buttons,
    })
  elseif report_callback then
    dialog = ConfirmBox:new({
      text = message,
      icon = "notice-warning",
      ok_text = _("Dismiss"),
      ok_callback = function()
        UIManager:close(dialog)
      end,
      cancel_text = _("Report"),
      cancel_callback = function()
        UIManager:close(dialog)
        report_callback()
      end,
    })
  else
    dialog = InfoMessage:new({
      text = message,
      icon = "notice-warning",
    })
  end

  UIManager:show(dialog)
end

return ErrorDialog
