-- lua/busy/cmdline.lua
-- Command mode dim overlay for nvim-busy.
--
-- When the user enters `:`, `/`, or `?` command mode a single full-screen
-- floating window appears:
--
--   - A semi-transparent dim overlay covering the editor content area
--     (not the statusline or cmdline row).
--   - An animated spinner character written directly into the overlay buffer
--     via an extmark at the centre line, so it shares the same window and
--     avoids any float-on-float compositing artefacts.
--
-- The window is hidden the moment CmdlineLeave fires.
-- A dedicated vim.uv timer drives the spinner; it runs only while command
-- mode is active, keeping CPU overhead at zero when idle.

local M = {}

local animation = require("busy.animation")

-- ---------------------------------------------------------------------------
-- Module state
-- ---------------------------------------------------------------------------

local _opts = {}          -- config slice passed from init.lua

local _overlay_buf = nil  -- persistent scratch buffer for the dim overlay
local _overlay_win = nil  -- floating window id (nil when hidden)
local _spinner_ns  = nil  -- extmark namespace for the spinner character

local _timer       = nil  -- vim.uv timer; only runs during command mode
local _active      = false -- guard against duplicate enter/leave events

-- ---------------------------------------------------------------------------
-- Layout helpers
-- ---------------------------------------------------------------------------

-- Returns the first content row (0-based), accounting for tabline.
local function content_top()
  local stal = vim.o.showtabline
  if stal == 2 or (stal == 1 and #vim.api.nvim_list_tabpages() > 1) then
    return 1
  end
  return 0
end

-- Returns the number of rows in the editor content area.
local function content_height()
  local sl = 0
  local ls = vim.o.laststatus
  if ls == 2 or ls == 3 or (ls == 1 and #vim.api.nvim_tabpage_list_wins(0) > 1) then
    sl = 1
  end
  return vim.o.lines - content_top() - sl - vim.o.cmdheight
end

-- nvim_open_win / nvim_win_set_config table for the full-screen overlay.
local function overlay_win_config()
  local ct = content_top()
  local ch = content_height()
  return {
    relative  = "editor",
    anchor    = "NW",
    row       = ct,
    col       = 0,
    width     = math.max(vim.o.columns, 1),
    height    = math.max(ch, 1),
    style     = "minimal",
    focusable = false,
    zindex    = 10,  -- below busy bar (45) and completion menus (100)
  }
end

-- Returns the (0-based) line and byte-col for the spinner inside the overlay.
local function spinner_pos()
  local ch = math.max(content_height(), 1)
  local w  = math.max(vim.o.columns, 1)
  local line = math.floor((ch - 1) / 2)
  local col  = math.floor((w - 1) / 2)
  return line, col
end

-- ---------------------------------------------------------------------------
-- Buffer helpers
-- ---------------------------------------------------------------------------

local function ensure_overlay_buf()
  if _overlay_buf and vim.api.nvim_buf_is_valid(_overlay_buf) then
    return _overlay_buf
  end
  local ok, buf = pcall(vim.api.nvim_create_buf, false, true)
  if not ok or not buf then return nil end
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "busy_cmdline_overlay", { buf = buf })
  _overlay_buf = buf
  return buf
end

-- Fill the overlay buffer with blank lines so the highlight group covers
-- every cell (not just lines with text).
local function fill_overlay_buf(buf)
  local ch = math.max(content_height(), 1)
  local w  = math.max(vim.o.columns, 1)
  local lines = {}
  for i = 1, ch do
    lines[i] = string.rep(" ", w)
  end
  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, lines)
end

-- Place (or update) the spinner extmark in the overlay buffer.
local function update_spinner_extmark(buf, frame)
  if not _spinner_ns then
    _spinner_ns = vim.api.nvim_create_namespace("NvimBusyCmdlineSpinner")
  end
  local line, col = spinner_pos()
  -- Clear previous mark then place the new frame.
  vim.api.nvim_buf_clear_namespace(buf, _spinner_ns, 0, -1)
  pcall(vim.api.nvim_buf_set_extmark, buf, _spinner_ns, line, col, {
    virt_text       = { { frame, "BusyCmdlineSpinner" } },
    virt_text_pos   = "overlay",
    hl_mode         = "combine",
  })
end

-- ---------------------------------------------------------------------------
-- Show / hide
-- ---------------------------------------------------------------------------

local function show_overlay(frame)
  local ok, err = pcall(function()
    local buf = ensure_overlay_buf()
    if not buf then return end

    local cfg = overlay_win_config()

    if _overlay_win and vim.api.nvim_win_is_valid(_overlay_win) then
      -- Window already open — just resize if terminal dimensions changed.
      vim.api.nvim_win_set_config(_overlay_win, cfg)
    else
      -- First show: fill buffer and open window.
      fill_overlay_buf(buf)
      cfg.noautocmd = true
      local wok, win = pcall(vim.api.nvim_open_win, buf, false, cfg)
      if not wok or not win or win == 0 then return end
      _overlay_win = win

      vim.api.nvim_set_option_value("winblend",     _opts.blend or 65,  { win = _overlay_win })
      vim.api.nvim_set_option_value("wrap",          false,              { win = _overlay_win })
      vim.api.nvim_set_option_value("cursorline",    false,              { win = _overlay_win })
      vim.api.nvim_set_option_value("winhighlight",
        "Normal:BusyCmdlineOverlay,EndOfBuffer:BusyCmdlineOverlay",      { win = _overlay_win })
    end

    -- Always update the spinner extmark so the frame advances.
    update_spinner_extmark(buf, frame)
  end)
  if not ok then
    vim.notify("[nvim-busy] show_overlay error: " .. tostring(err), vim.log.levels.DEBUG)
  end
end

local function hide_overlay()
  pcall(function()
    if _overlay_win and vim.api.nvim_win_is_valid(_overlay_win) then
      vim.api.nvim_win_hide(_overlay_win)
    end
    _overlay_win = nil
  end)
  -- Clear extmarks so they don't linger when the buffer is reused.
  pcall(function()
    if _overlay_buf and vim.api.nvim_buf_is_valid(_overlay_buf) and _spinner_ns then
      vim.api.nvim_buf_clear_namespace(_overlay_buf, _spinner_ns, 0, -1)
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Timer tick
-- ---------------------------------------------------------------------------

local function tick()
  if not _active then return end
  local frame = animation.current_frame(
    _opts.animation or "dots",
    _opts.speed_ms  or 150
  )
  show_overlay(frame)
  -- Use plain "redraw" (not "redraw!") in the tick — it only repaints dirty
  -- regions and is much cheaper than a full redraw every 150 ms.
  pcall(vim.cmd, "redraw")
end

-- ---------------------------------------------------------------------------
-- Enter / leave handlers
-- ---------------------------------------------------------------------------

function M._on_enter()
  if _active then return end
  _active = true

  local frame = animation.current_frame(_opts.animation or "dots", _opts.speed_ms or 150)
  show_overlay(frame)

  -- Full redraw! required on enter to force Neovim to paint the float
  -- while the cmdline has focus (plain "redraw" is not enough here).
  pcall(vim.cmd, "redraw!")

  if _timer then
    pcall(function() _timer:stop() ; _timer:close() end)
    _timer = nil
  end
  _timer = vim.uv.new_timer()
  _timer:start(
    _opts.speed_ms or 150,
    _opts.speed_ms or 150,
    vim.schedule_wrap(tick)
  )
end

function M._on_leave()
  if not _active then return end
  _active = false

  if _timer then
    pcall(function() _timer:stop() ; _timer:close() end)
    _timer = nil
  end

  hide_overlay()
end

-- ---------------------------------------------------------------------------
-- Reposition (called from init.lua on VimResized)
-- ---------------------------------------------------------------------------

function M.reposition()
  pcall(function()
    if not _active then return end

    local buf = _overlay_buf
    if buf and vim.api.nvim_buf_is_valid(buf) then
      fill_overlay_buf(buf)
    end

    if _overlay_win and vim.api.nvim_win_is_valid(_overlay_win) then
      vim.api.nvim_win_set_config(_overlay_win, overlay_win_config())
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

function M.setup(opts)
  _opts = opts or {}

  local augroup = vim.api.nvim_create_augroup("NvimBusyCmdline", { clear = true })
  local patterns = _opts.patterns or { ":", "/", "?" }

  vim.api.nvim_create_autocmd("CmdlineEnter", {
    group    = augroup,
    pattern  = patterns,
    callback = M._on_enter,
  })

  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group    = augroup,
    pattern  = patterns,
    callback = M._on_leave,
  })
end

return M
