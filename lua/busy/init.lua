-- lua/busy/init.lua
-- nvim-busy.nvim — lightweight loading indicator for LSP and Telescope.
-- https://github.com/davidabad98/nvim-busy.nvim

-- Neovim version guard — requires LspProgress autocmd and vim.uv.
if vim.fn.has("nvim-0.10") == 0 then
  vim.notify("[nvim-busy] requires Neovim >= 0.10", vim.log.levels.ERROR)
  return {}
end

local M = {}

-- ---------------------------------------------------------------------------
-- Default configuration
-- ---------------------------------------------------------------------------

local _defaults = {
  animation = "dots",       -- "dots"|"arc"|"line"|"bounce"|string[] (custom)
  speed_ms = 80,            -- animation tick interval in milliseconds
  position = "bottom-left", -- "bottom-left" | "bottom-right"
  text = " loading",        -- suffix after the spinner frame, or false for none
  blend = 0,                -- winblend: 0 (opaque) to 100 (transparent bg)
  zindex = 45,              -- float z-order (below completion menus at 100)
  lsp = {
    enabled = true,
    watch_progress = true,  -- LspProgress autocmd (background indexing)
    watch_requests = false, -- wrap gd/gr/K/etc. — requires dotfiles change
    request_ttl_ms = 10000, -- fallback TTL for request wrapping (ms)
  },
  telescope = {
    enabled = true,
    animate_counter = true, -- replace Telescope's "*" with animated spinner
  },
  cmdline = {
    enabled   = true,
    patterns  = { ":", "/", "?" }, -- cmdline types that trigger the overlay
    blend     = 30,                -- winblend of the dim overlay (0–100)
    animation = "dots",            -- spinner pattern (same options as main animation)
    speed_ms  = 80,                -- spinner tick interval in ms
  },
}

M._config = vim.deepcopy(_defaults)

-- ---------------------------------------------------------------------------
-- Internal handles
-- ---------------------------------------------------------------------------

local _timer = nil   -- vim.uv timer driving the animation loop
local _augroup = nil -- autocmd group for VimResized + CmdlineEnter/Leave

-- ---------------------------------------------------------------------------
-- Highlight groups
-- ---------------------------------------------------------------------------

local function define_highlights()
  -- BusyIndicator: window background colour (applied via winhighlight).
  -- Default: link to Comment so it is visually subtle.
  -- Users can override after setup():
  --   vim.api.nvim_set_hl(0, "BusyIndicator", { fg = "#cba6f7", bg = "#1e1e2e" })
  vim.api.nvim_set_hl(0, "BusyIndicator", { link = "Comment", default = true })
  -- BusyIndicatorText: the " loading" label portion (after the spinner frame).
  -- Default: also links to Comment; separate so users can give the text a
  -- different colour from the spinner character.
  vim.api.nvim_set_hl(0, "BusyIndicatorText", { link = "Comment", default = true })
  -- BusyCmdlineOverlay: background of the full-screen dim overlay.
  -- Default: solid black — made semi-transparent by winblend=30.
  -- Override to change the dim colour, e.g. a dark version of your theme bg.
  vim.api.nvim_set_hl(0, "BusyCmdlineOverlay", { bg = "#000000", default = true })
  -- BusyCmdlineSpinner: the centred animated frame shown over the overlay.
  -- Default: links to Statement (typically bright/highlighted) so it stands
  -- out against the dimmed background.
  vim.api.nvim_set_hl(0, "BusyCmdlineSpinner", { link = "Statement", default = true })
end

-- ---------------------------------------------------------------------------
-- Animation tick (called by the uv timer every speed_ms ms)
-- ---------------------------------------------------------------------------

local function tick()
  local state = require("busy.state")
  local window = require("busy.window")
  local animation = require("busy.animation")

  if state.is_busy() then
    local frame = animation.current_frame(M._config.animation, M._config.speed_ms)
    local label
    if M._config.text then
      label = frame .. M._config.text
    else
      label = frame
    end
    window.show(label)
  else
    window.hide()
  end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---Entry point. Call once from your lazy.nvim spec config or init.lua.
---Idempotent: safe to call multiple times (re-setup clears previous state).
---@param opts table|nil  Partial config merged over defaults.
function M.setup(opts)
  -- Merge user opts over defaults (deep merge so lsp/telescope sub-tables work).
  M._config = vim.tbl_deep_extend("force", vim.deepcopy(_defaults), opts or {})

  -- Reset any leftover busy state from a previous setup() call.
  require("busy.state").reset()

  -- Pass relevant config slices to sub-modules.
  require("busy.window").setup(M._config)

  -- Define highlight groups (before the window is ever opened).
  define_highlights()
  -- Re-apply highlights when the colorscheme changes.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("NvimBusyHL", { clear = true }),
    callback = define_highlights,
  })

  -- -------------------------------------------------------------------------
  -- Autocmds
  -- -------------------------------------------------------------------------
  _augroup = vim.api.nvim_create_augroup("NvimBusy", { clear = true })

  -- Reposition after terminal resize.
  vim.api.nvim_create_autocmd("VimResized", {
    group = _augroup,
    callback = vim.schedule_wrap(function()
      require("busy.window").reposition()
      require("busy.cmdline").reposition()
    end),
  })

  -- Quickfix / location-list windows at the bottom shift the available
  -- height. Reposition whenever any window opens or closes.
  vim.api.nvim_create_autocmd({ "WinNew", "WinClosed" }, {
    group = _augroup,
    callback = vim.schedule_wrap(function()
      require("busy.window").reposition()
    end),
  })

  -- Session restore (e.g. auto-session): re-anchor after layout is rebuilt.
  vim.api.nvim_create_autocmd("SessionLoadPost", {
    group = _augroup,
    callback = vim.schedule_wrap(function()
      require("busy.window").reposition()
    end),
  })

  -- -------------------------------------------------------------------------
  -- Animation timer
  -- -------------------------------------------------------------------------
  if _timer then
    -- Stop the old timer before creating a new one (idempotent setup).
    pcall(function()
      _timer:stop()
      _timer:close()
    end)
    _timer = nil
  end
  _timer = vim.uv.new_timer()
  -- start(initial_delay_ms, repeat_ms, callback)
  -- vim.schedule_wrap ensures the callback runs on the main loop,
  -- which is required for any vim.api.* call.
  _timer:start(0, M._config.speed_ms, vim.schedule_wrap(tick))

  -- -------------------------------------------------------------------------
  -- Optional signal sources (wired up in later phases)
  -- -------------------------------------------------------------------------
  if M._config.lsp.enabled then
    local ok, lsp = pcall(require, "busy.lsp")
    if ok then
      lsp.setup(M._config.lsp)
    end
  end

  if M._config.telescope.enabled then
    local ok, tel = pcall(require, "busy.telescope")
    if ok then
      tel.setup(M._config.telescope)
    end
  end

  if M._config.cmdline.enabled then
    local ok, cmdline = pcall(require, "busy.cmdline")
    if ok then
      cmdline.setup(M._config.cmdline)
    end
  end

  -- -------------------------------------------------------------------------
  -- :BusyStatus debug command
  -- -------------------------------------------------------------------------
  vim.api.nvim_create_user_command("BusyStatus", function()
    local active = require("busy.state").active()
    if next(active) == nil then
      vim.notify("[nvim-busy] idle — no active tasks", vim.log.levels.INFO)
    else
      vim.notify("[nvim-busy] active tasks:\n" .. vim.inspect(active), vim.log.levels.INFO)
    end
  end, { desc = "Show nvim-busy active task state" })
end

---Manually mark a named task as started. The indicator appears immediately.
---@param id string  A unique string identifying this busy reason.
function M.push(id)
  require("busy.state").push(id)
end

---Manually mark a named task as finished.
---@param id string  Must match the string passed to push().
function M.pop(id)
  require("busy.state").pop(id)
end

---Wrap an LSP buf function so the indicator shows while it is pending.
---
---Usage in on_attach (Phase 3 tight-coupling):
---  map("n", "gd", busy.wrap(vim.lsp.buf.definition, "lsp:gd"), "Goto Definition")
---
---@param fn function    The LSP function to wrap (e.g. vim.lsp.buf.definition).
---@param id string|nil  Stable id string; defaults to a fn-address-based key.
---@return function       A drop-in replacement that shows the indicator.
function M.wrap(fn, id)
  local key = id or ("lsp:request:" .. tostring(fn))
  return function(...)
    local state = require("busy.state")
    state.push(key)

    -- Safety TTL: always clear after request_ttl_ms even if the server
    -- never responds (e.g. server crash, no definition found).
    local cleared = false
    local function clear()
      if not cleared then
        cleared = true
        vim.schedule(function()
          state.pop(key)
        end)
      end
    end
    vim.defer_fn(clear, M._config.lsp.request_ttl_ms or 10000)

    -- Invoke the original LSP function. It is fire-and-forget (no return).
    fn(...)
  end
end

return M
