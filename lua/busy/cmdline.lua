-- lua/busy/cmdline.lua
-- Command mode dim overlay for nvim-busy.
--
-- When the user enters `:`, `/`, or `?` command mode two floating windows
-- appear simultaneously:
--
--   1. A full-screen dim overlay (zindex=10) that covers the editor content
--      area without touching the statusline or cmdline.  The overlay is
--      semi-transparent (winblend=30 by default) so the underlying text is
--      still legible.
--
--   2. A 3-cell-wide animated spinner centred in the content area (zindex=11),
--      using the same braille animation frames as the main busy bar.  No
--      "loading" label — just the frame character.
--
-- Both windows are hidden the moment CmdlineLeave fires.
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

local _spinner_buf = nil  -- persistent scratch buffer for the centred spinner
local _spinner_win = nil  -- floating window id (nil when hidden)

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
  local ct  = content_top()
  local ch  = content_height()
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

-- nvim_open_win / nvim_win_set_config table for the centred spinner.
local function spinner_win_config()
  local ct  = content_top()
  local ch  = content_height()
  local w   = 3
  local h   = 1
  local row = ct + math.floor((ch - h) / 2)
  local col = math.floor((vim.o.columns - w) / 2)
  return {
    relative  = "editor",
    anchor    = "NW",
    row       = math.max(row, ct),
    col       = math.max(col, 0),
    width     = w,
    height    = h,
    style     = "minimal",
    focusable = false,
    zindex    = 11,  -- just above the overlay, still below busy bar
  }
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

local function ensure_spinner_buf()
  if _spinner_buf and vim.api.nvim_buf_is_valid(_spinner_buf) then
    return _spinner_buf
  end
  local ok, buf = pcall(vim.api.nvim_create_buf, false, true)
  if not ok or not buf then return nil end
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "busy_cmdline_spinner", { buf = buf })
  _spinner_buf = buf
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

-- ---------------------------------------------------------------------------
-- Show / hide
-- ---------------------------------------------------------------------------

local function show_overlay()
  pcall(function()
    local buf = ensure_overlay_buf()
    if not buf then return end

    fill_overlay_buf(buf)
    local cfg = overlay_win_config()

    if _overlay_win and vim.api.nvim_win_is_valid(_overlay_win) then
      vim.api.nvim_win_set_config(_overlay_win, cfg)
    else
      cfg.noautocmd = true
      local ok, win = pcall(vim.api.nvim_open_win, buf, false, cfg)
      if not ok or not win or win == 0 then return end
      _overlay_win = win

      vim.api.nvim_win_call(_overlay_win, function()
        vim.opt_local.winblend   = _opts.blend or 30
        vim.opt_local.wrap       = false
        vim.opt_local.cursorline = false
        vim.opt_local.winhighlight =
          "Normal:BusyCmdlineOverlay,EndOfBuffer:BusyCmdlineOverlay"
      end)
    end
  end)
end

local function show_spinner(frame)
  pcall(function()
    local buf = ensure_spinner_buf()
    if not buf then return end

    local text = " " .. frame .. " "
    pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, { text })

    local cfg = spinner_win_config()

    if _spinner_win and vim.api.nvim_win_is_valid(_spinner_win) then
      vim.api.nvim_win_set_config(_spinner_win, cfg)
    else
      cfg.noautocmd = true
      local ok, win = pcall(vim.api.nvim_open_win, buf, false, cfg)
      if not ok or not win or win == 0 then return end
      _spinner_win = win

      vim.api.nvim_win_call(_spinner_win, function()
        vim.opt_local.winblend   = 0
        vim.opt_local.wrap       = false
        vim.opt_local.cursorline = false
        vim.opt_local.winhighlight = "Normal:BusyCmdlineSpinner"
      end)
    end
  end)
end

local function hide_all()
  pcall(function()
    if _overlay_win and vim.api.nvim_win_is_valid(_overlay_win) then
      vim.api.nvim_win_hide(_overlay_win)
    end
    _overlay_win = nil
  end)
  pcall(function()
    if _spinner_win and vim.api.nvim_win_is_valid(_spinner_win) then
      vim.api.nvim_win_hide(_spinner_win)
    end
    _spinner_win = nil
  end)
end

-- ---------------------------------------------------------------------------
-- Timer tick
-- ---------------------------------------------------------------------------

local function tick()
  if not _active then return end
  local frame = animation.current_frame(
    _opts.animation or "dots",
    _opts.speed_ms  or 80
  )
  -- Overlay only needs updating when terminal is resized; spinner updates
  -- every tick to advance the animation frame.
  show_overlay()
  show_spinner(frame)
end

-- ---------------------------------------------------------------------------
-- Enter / leave handlers
-- ---------------------------------------------------------------------------

function M._on_enter()
  if _active then return end
  _active = true

  -- Show immediately (first frame) before the timer fires.
  local frame = animation.current_frame(_opts.animation or "dots", _opts.speed_ms or 80)
  show_overlay()
  show_spinner(frame)

  -- Start dedicated timer.
  if _timer then
    pcall(function() _timer:stop() ; _timer:close() end)
    _timer = nil
  end
  _timer = vim.uv.new_timer()
  _timer:start(
    _opts.speed_ms or 80,
    _opts.speed_ms or 80,
    vim.schedule_wrap(tick)
  )
end

function M._on_leave()
  if not _active then return end
  _active = false

  -- Stop the timer first so no further ticks race with hide_all().
  if _timer then
    pcall(function() _timer:stop() ; _timer:close() end)
    _timer = nil
  end

  hide_all()
end

-- ---------------------------------------------------------------------------
-- Reposition (called from init.lua on VimResized)
-- ---------------------------------------------------------------------------

function M.reposition()
  pcall(function()
    if not _active then return end

    -- Re-fill overlay buffer for the new terminal dimensions.
    if _overlay_buf and vim.api.nvim_buf_is_valid(_overlay_buf) then
      fill_overlay_buf(_overlay_buf)
    end

    if _overlay_win and vim.api.nvim_win_is_valid(_overlay_win) then
      vim.api.nvim_win_set_config(_overlay_win, overlay_win_config())
    end
    if _spinner_win and vim.api.nvim_win_is_valid(_spinner_win) then
      vim.api.nvim_win_set_config(_spinner_win, spinner_win_config())
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
    callback = vim.schedule_wrap(M._on_enter),
  })

  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group    = augroup,
    pattern  = patterns,
    callback = vim.schedule_wrap(M._on_leave),
  })
end

return M
