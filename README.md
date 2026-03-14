# nvim-busy.nvim

> A lightweight, zero-dependency Neovim plugin that shows an animated loading
> indicator whenever the editor is waiting — LSP background indexing, LSP
> navigation requests (`gd`, `gr`, `K`, …), or a Telescope search in progress.

The indicator is a small animated braille spinner in a floating bar at the
bottom of the screen. It appears when work begins and disappears when it
finishes — no config required.

---

## Requirements

- Neovim >= 0.10
- No other plugins required
- Optional: `telescope.nvim` for the in-prompt spinner

## Installation

### lazy.nvim

```lua
{
  "davidabad98/nvim-busy.nvim",
  lazy = false,        -- must load eagerly so signals are hooked on startup
  priority = 900,      -- load before LSP / Telescope plugins
  opts = {},           -- calls setup() with all defaults
}
```

### Configuration (all defaults shown)

```lua
require("busy").setup({
  animation = "dots",        -- "dots" | "arc" | "line" | "bounce" | string[]
  speed_ms  = 80,            -- animation tick interval in ms
  position  = "bottom-left", -- "bottom-left" | "bottom-right"
  text      = " loading",    -- label after the spinner, or false for spinner only
  blend     = 0,             -- winblend: 0 (opaque) → 100 (transparent)
  zindex    = 45,            -- float z-order (below completion menus at 100)

  lsp = {
    enabled        = true,
    watch_progress = true,   -- indicator during LSP $/progress (background indexing)
    watch_requests = false,  -- indicator on gd/gr/K/etc. (requires on_attach change)
    request_ttl_ms = 10000,  -- safety timeout if server never replies (ms)
  },

  telescope = {
    enabled         = true,
    animate_counter = true,  -- animated spinner in Telescope's prompt counter
  },
})
```

## Telescope — animated prompt counter

To replace Telescope's built-in `*` in-progress marker with an animated
spinner, add `get_status_text` to your Telescope defaults:

```lua
-- in your telescope.nvim lazy spec:
opts = {
  defaults = {
    get_status_text = function(self, opts)
      local ok, busy_ts = pcall(require, "busy.telescope")
      if ok then return busy_ts.get_status_text(self, opts) end
    end,
  },
},
```

The spinner automatically switches to a plain `N / M` count when the search
finishes.

## LSP navigation indicator (`gd`, `gr`, `K`, …)

By default `watch_requests = false`. To show the indicator while waiting for
LSP responses to navigation requests, enable it and wrap your keymaps via
`busy.wrap()` in `on_attach`:

```lua
-- in lsp-config.lua on_attach:
local ok, busy = pcall(require, "busy")
if ok then
  local function map(mode, lhs, fn, desc)
    vim.keymap.set(mode, lhs, busy.wrap(fn, "lsp:" .. lhs), { buffer = bufnr, desc = desc })
  end
  map("n", "gd", vim.lsp.buf.definition,    "Goto Definition")
  map("n", "gr", vim.lsp.buf.references,    "Goto References")
  map("n", "gi", vim.lsp.buf.implementation,"Goto Implementation")
  map("n", "K",  vim.lsp.buf.hover,         "Hover")
else
  -- fallback: plain keymaps without the indicator
  vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = bufnr })
  -- …
end
```

> **Note**: `lsp.watch_requests = true` must also be set in `setup()`.

## Highlight groups

Two highlight groups are defined with sensible defaults you can override:

| Group               | Default         | What it styles                    |
|---------------------|-----------------|-----------------------------------|
| `BusyIndicator`     | links `Comment` | floating window background + text |
| `BusyIndicatorText` | links `Comment` | the ` loading` label portion only |

Override example:

```lua
vim.api.nvim_set_hl(0, "BusyIndicator",     { fg = "#cba6f7", bg = "#1e1e2e" })
vim.api.nvim_set_hl(0, "BusyIndicatorText", { fg = "#a6adc8", bg = "#1e1e2e" })
```

## Public API

```lua
require("busy").push(id)      -- mark a named task as started
require("busy").pop(id)       -- mark a named task as finished
require("busy").wrap(fn, id)  -- wrap a function with push/pop around it
```

`:BusyStatus` — debug command that prints all currently active task ids.

## How it works

- A single `vim.uv` timer fires every 80 ms and updates a 1-line scratch
  buffer displayed in a `relative="editor"` floating window (SW anchor,
  just above the cmdline/statusline).
- Signal sources are purely event-driven: `LspProgress` autocmd for
  background indexing, `LspRequest` autocmd for precise navigation-request
  tracking, and Telescope's `register_completion_callback` for search state.
- All state is reference-counted by string id — the bar disappears only when
  every concurrent operation has finished.
- Inspired by [fidget.nvim](https://github.com/j-hui/fidget.nvim), with which
  it coexists without conflict.

## License

MIT
