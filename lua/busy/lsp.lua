-- lua/busy/lsp.lua
-- LSP signal watchers for nvim-busy.
--
-- Phase 2: LspProgress autocmd — covers background indexing / loading.
--   Every LSP $/progress message has a token that identifies a unique task.
--   We push on kind="begin" and pop on kind="end", keyed by
--   "lsp:progress:<client_id>:<token>" so concurrent tasks from the same
--   server don't cancel each other.
--
-- Phase 3 (request keymaps): handled in init.lua via M.wrap(); the
--   LspRequest autocmd is registered here for precise response detection.

local M = {}
local state = require("busy.state")

local _augroup = nil

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Build the state key for a progress token.
local function progress_key(client_id, token)
  return "lsp:progress:" .. tostring(client_id) .. ":" .. tostring(token)
end

--- Pop all progress keys belonging to a given client.
-- Used when a server detaches without sending "end" for every token
-- (e.g. :LspStop, server crash).
local function clear_client(client_id)
  local prefix = "lsp:progress:" .. tostring(client_id) .. ":"
  for id in pairs(state.active()) do
    if id:sub(1, #prefix) == prefix then
      state.pop(id)
    end
  end
end

-- ---------------------------------------------------------------------------
-- LspRequest autocmd — precise clear for keymap wrappers (Phase 3 support)
-- ---------------------------------------------------------------------------
-- Maps LSP method names to the stable ids used by init.lua's wrap().
local _method_to_id = {
  ["textDocument/definition"] = "lsp:gd",
  ["textDocument/declaration"] = "lsp:gD",
  ["textDocument/implementation"] = "lsp:gi",
  ["textDocument/references"] = "lsp:gr",
  ["textDocument/hover"] = "lsp:K",
  ["textDocument/signatureHelp"] = "lsp:gk",
}

-- ---------------------------------------------------------------------------
-- Public setup
-- ---------------------------------------------------------------------------

function M.setup(opts)
  -- Idempotent: clear any previously registered autocmds.
  _augroup = vim.api.nvim_create_augroup("NvimBusyLsp", { clear = true })

  -- -------------------------------------------------------------------------
  -- LspProgress: background indexing / loading indicator
  -- -------------------------------------------------------------------------
  if opts.watch_progress then
    vim.api.nvim_create_autocmd("LspProgress", {
      group = _augroup,
      callback = function(event)
        -- Guard against malformed event data (defensive — servers vary).
        local ok, data = pcall(function()
          return event.data
        end)
        if not ok or not data then
          return
        end

        local client_id = data.client_id
        local params = data.params
        if not params or not params.value then
          return
        end

        local kind = params.value.kind
        local token = params.token
        if not kind or token == nil then
          return
        end

        local key = progress_key(client_id, token)

        if kind == "begin" then
          state.push(key)
        elseif kind == "end" then
          -- Small grace delay: keeps the indicator visible for one extra
          -- render cycle so the user sees it reach "done" rather than
          -- disappearing the instant the final message arrives.
          vim.defer_fn(function()
            state.pop(key)
          end, 250)
        end
        -- kind == "report": no state change needed; push already happened.
      end,
    })
  end

  -- -------------------------------------------------------------------------
  -- LspDetach: clean up any stranded progress keys for this client
  -- -------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("LspDetach", {
    group = _augroup,
    callback = function(args)
      local client_id = args.data and args.data.client_id
      if client_id then
        clear_client(client_id)
      end
    end,
  })

  -- -------------------------------------------------------------------------
  -- LspRequest: precise pop for request keymap wrappers (Phase 3)
  -- Fires when a pending LSP request receives its response or is cancelled.
  -- This removes the indicator exactly when the server replies, rather than
  -- waiting for the TTL fallback in init.lua's wrap().
  -- -------------------------------------------------------------------------
  if opts.watch_requests then
    vim.api.nvim_create_autocmd("LspRequest", {
      group = _augroup,
      callback = function(event)
        local ok, data = pcall(function()
          return event.data
        end)
        if not ok or not data or not data.request then
          return
        end
        -- type == "complete" fires when the response (success or error) arrives.
        -- type == "cancel"   fires when the request is cancelled client-side.
        if data.request.type == "complete" or data.request.type == "cancel" then
          local id = _method_to_id[data.request.method]
          if id then
            vim.schedule(function()
              state.pop(id)
            end)
          end
        end
      end,
    })
  end
end

return M
