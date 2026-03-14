-- lua/busy/telescope.lua
-- Telescope signal integration for nvim-busy.
-- Phase 4: TelescopeFindPre + register_completion_callback + get_status_text.
-- Stub — wired up in Phase 4.

local M = {}

function M.setup(_opts)
  -- Implemented in Phase 4.
end

---Telescope get_status_text override.
---Drop this into your telescope defaults:
---  get_status_text = require("busy.telescope").get_status_text
---@param self table  The Telescope picker object.
---@param opts table|nil  { completed = bool }
---@return string
function M.get_status_text(self, opts)
  -- Phase 0-3 passthrough: replicate Telescope's default behaviour.
  local showing = (self.stats.processed or 0) - (self.stats.filtered or 0)
  local total = self.stats.processed or 0
  if opts and not opts.completed then
    return "* " .. showing .. " / " .. total
  end
  if showing == 0 and total == 0 then
    return ""
  end
  return showing .. " / " .. total
end

return M
