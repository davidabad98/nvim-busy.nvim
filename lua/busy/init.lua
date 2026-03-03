-- nvim-busy.nvim
-- A lightweight loading indicator for LSP and Telescope operations.
-- Phase 0: stub — verifies the plugin loads cleanly.

-- Neovim version guard
if vim.fn.has("nvim-0.10") == 0 then
  vim.notify("[nvim-busy] requires Neovim >= 0.10", vim.log.levels.ERROR)
  return {}
end

local M = {}

-- Default configuration — all options documented here.
M._config = {
  animation = "dots",       -- "dots"|"arc"|"line"|"bounce"|string[] (custom frames)
  speed_ms  = 80,           -- animation tick interval in milliseconds
  position  = "bottom-left", -- "bottom-left" | "bottom-right"
  text      = " loading",   -- string appended after spinner frame, or false for none
  blend     = 0,            -- winblend: 0 (opaque) to 100 (transparent background)
  zindex    = 45,           -- float z-order (below completion menus at 100)
  lsp = {
    enabled        = true,
    watch_progress = true,  -- hook LspProgress autocmd (background indexing)
    watch_requests = false, -- wrap gd/gr/K/etc. — requires dotfiles change, opt-in
    request_ttl_ms = 10000, -- fallback TTL for request wrapping
  },
  telescope = {
    enabled         = true,
    animate_counter = true, -- replace Telescope's "*" with animated spinner
  },
}

M._ready = false  -- set to true after setup() completes

---Entry point. Call once from your lazy.nvim spec or init.lua.
---@param opts table|nil Partial config merged over defaults.
function M.setup(opts)
  M._config = vim.tbl_deep_extend("force", M._config, opts or {})
  M._ready  = true
  -- Signal sources and window will be wired up in Phase 1+.
  vim.notify("[nvim-busy] loaded (stub — Phase 0)", vim.log.levels.INFO)
end

---Manually mark a named task as started. The indicator appears immediately.
---@param id string A unique string identifying this busy reason.
function M.push(id)
  -- wired up in Phase 1
end

---Manually mark a named task as finished.
---@param id string Must match the id passed to push().
function M.pop(id)
  -- wired up in Phase 1
end

---Wrap an LSP buf function so the indicator shows while it is pending.
---Use this in on_attach instead of calling vim.lsp.buf.* directly.
---@param fn function  The LSP function to wrap (e.g. vim.lsp.buf.definition).
---@param id string|nil Optional stable id; defaults to a fn-based key.
---@return function  A drop-in replacement that shows the indicator.
function M.wrap(fn, id)
  -- In Phase 0 this is a transparent pass-through so keymaps still work.
  return fn
end

return M
