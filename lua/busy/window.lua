-- lua/busy/window.lua
-- Floating window lifecycle for nvim-busy.
--
-- Design decisions:
--   - One persistent scratch buffer; never recreated.
--   - Window is hidden (nvim_win_hide) when idle and re-opened when busy.
--     Re-opening is cheap: buffer already exists, config is cached.
--   - All vim.api calls are wrapped in pcall to survive edge cases
--     (window closed externally, textlock, cmdline window, etc.).
--   - Content is plain nvim_buf_set_lines — no extmarks needed for a
--     single-line text bar.
--   - winblend=0 by default so the bar has a solid background and is
--     always readable against any colorscheme.

local M = {}

-- Module-level handles — nil until first show().
local _buf = nil -- scratch buffer (never wiped)
local _win = nil -- floating window id (nil when hidden)
local _cfg = {} -- copy of user config set by M.setup()

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Compute the row for the SW/SE anchor.
-- Accounts for: statusline presence (laststatus), cmdheight, and the fact
-- that anchor="SW" means the *bottom-left corner* of the float is at (row,col).
-- So row = total lines - statusline rows - cmdheight rows puts the float
-- just above the cmdline/statusline.
local function bottom_row()
  local sl = 0
  local ls = vim.opt.laststatus:get()
  -- laststatus=2 or 3 always shows statusline; =1 shows when >1 window.
  if ls == 2 or ls == 3 or (ls == 1 and #vim.api.nvim_tabpage_list_wins(0) > 1) then
    sl = 1
  end
  return vim.opt.lines:get() - sl - vim.opt.cmdheight:get()
end

--- Build the nvim_open_win / nvim_win_set_config options table.
local function win_config(width)
  local anchor = (_cfg.position == "bottom-right") and "SE" or "SW"
  local col = 0
  if _cfg.position == "bottom-right" then
    col = vim.opt.columns:get()
  end
  return {
    relative = "editor",
    anchor = anchor,
    row = bottom_row(),
    col = col,
    width = math.max(width, 1),
    height = 1,
    style = "minimal",
    focusable = false,
    zindex = _cfg.zindex or 45,
  }
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Called once from init.lua with the merged user config.
function M.setup(cfg)
  _cfg = cfg or {}
end

--- Ensure the scratch buffer exists. Creates it on first call.
-- Returns the buffer number, or nil on failure.
local function ensure_buf()
  if _buf and vim.api.nvim_buf_is_valid(_buf) then
    return _buf
  end
  local ok, buf = pcall(vim.api.nvim_create_buf, false, true) -- unlisted, scratch
  if not ok or not buf then
    return nil
  end
  -- bufhidden=hide: don't wipe when the window is closed/hidden.
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
  -- Tag the buffer so other plugins can identify and ignore it.
  vim.api.nvim_set_option_value("filetype", "busy_indicator", { buf = buf })
  _buf = buf
  return _buf
end

--- Show or update the floating bar with `text`.
-- Creates the window on first call; repositions on subsequent calls.
-- Safe to call from a vim.schedule_wrap timer callback.
function M.show(text)
  pcall(function()
    local buf = ensure_buf()
    if not buf then
      return
    end

    -- Pad the text with one space on each side for readability.
    local padded = " " .. text .. " "
    local width = vim.api.nvim_strwidth(padded)

    -- Update buffer content (no undo history on scratch buffers).
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { padded })

    local cfg = win_config(width)

    if _win and vim.api.nvim_win_is_valid(_win) then
      -- Window already open: just reposition + resize (no flicker).
      vim.api.nvim_win_set_config(_win, cfg)
    else
      -- First show (or after a hide): open a new window.
      cfg.noautocmd = true -- suppress BufEnter / WinEnter side-effects
      local ok, win = pcall(vim.api.nvim_open_win, buf, false, cfg)
      if not ok or not win or win == 0 then
        return
      end
      _win = win

      -- Apply window-local options via nvim_win_call to avoid the
      -- option-leak bug (nvim issue #18283).
      vim.api.nvim_win_call(_win, function()
        vim.opt_local.winblend = _cfg.blend or 0
        vim.opt_local.wrap = false
        vim.opt_local.cursorline = false
        -- Use the BusyIndicator highlight group for the window background.
        -- Falls back to Normal if the group is not defined.
        vim.opt_local.winhighlight = "Normal:BusyIndicator"
      end)
    end
  end)
end

--- Hide the floating bar without destroying the buffer.
-- The buffer is reused on the next show() call.
function M.hide()
  pcall(function()
    if _win and vim.api.nvim_win_is_valid(_win) then
      vim.api.nvim_win_hide(_win)
    end
    _win = nil
  end)
end

--- Reposition the window after a VimResized event.
-- No-op when the window is currently hidden.
function M.reposition()
  pcall(function()
    if not _win or not vim.api.nvim_win_is_valid(_win) then
      return
    end
    if not _buf or not vim.api.nvim_buf_is_valid(_buf) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(_buf, 0, 1, false)
    local text = (lines and lines[1]) or " "
    local width = vim.api.nvim_strwidth(text)
    vim.api.nvim_win_set_config(_win, win_config(width))
  end)
end

--- Returns true when the floating window is currently visible.
function M.is_visible()
  return _win ~= nil and vim.api.nvim_win_is_valid(_win)
end

return M
