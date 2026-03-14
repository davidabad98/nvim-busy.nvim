-- lua/busy/state.lua
-- Reference-counted busy state.
--
-- Multiple concurrent sources (LSP indexing, LSP request, Telescope) can each
-- push their own ID. The indicator stays visible until ALL of them have popped.
-- This prevents one completing operation from hiding the indicator while
-- another is still in progress.

local M = {}

-- Map of id -> positive integer count.
-- An id is "active" as long as its count > 0.
-- The table entry is removed when count reaches 0 to keep it clean.
local _counts = {}

--- Start a busy reason. Safe to call multiple times with the same id.
-- @param id string  Unique string identifying this busy source.
function M.push(id)
  _counts[id] = (_counts[id] or 0) + 1
end

--- Finish a busy reason.
-- If the id was never pushed this is a no-op (safe).
-- @param id string  Must match the string passed to push().
function M.pop(id)
  if not _counts[id] then
    return
  end
  _counts[id] = _counts[id] - 1
  if _counts[id] <= 0 then
    _counts[id] = nil
  end
end

--- Returns true when at least one busy reason is active.
-- @return boolean
function M.is_busy()
  return next(_counts) ~= nil
end

--- Returns a shallow copy of the active reasons table.
-- Useful for :BusyStatus debug command.
-- @return table  { [id] = count, ... }
function M.active()
  local out = {}
  for k, v in pairs(_counts) do
    out[k] = v
  end
  return out
end

--- Wipe all active reasons. Used on plugin reload / setup() re-call.
function M.reset()
  _counts = {}
end

return M
