# nvim-busy.nvim

> A lightweight, zero-dependency Neovim plugin that shows an animated loading
> indicator whenever the editor is waiting — LSP background indexing, LSP
> navigation requests (`gd`, `gr`, `K`, …), or a Telescope search in progress.

**Status: under active development.**

---

## Requirements

- Neovim >= 0.10
- No other plugins required (Telescope and lualine integrations are optional)

## Installation

### lazy.nvim

```lua
{
  "yourusername/nvim-busy.nvim",
  lazy = false,
  priority = 900,
  opts = {},
}
```

### Configuration (all defaults shown)

```lua
require("busy").setup({
  animation = "dots",        -- "dots" | "arc" | "line" | "bounce" | string[]
  speed_ms  = 80,            -- animation tick interval in ms
  position  = "bottom-left", -- "bottom-left" | "bottom-right"
  text      = " loading",    -- label after the spinner, or false to hide
  blend     = 0,             -- winblend 0 (opaque) → 100 (transparent bg)
  lsp = {
    enabled        = true,
    watch_progress = true,   -- show indicator during LSP indexing
    watch_requests = false,  -- show indicator on gd/gr/K/etc. (requires dotfiles change)
    request_ttl_ms = 10000,
  },
  telescope = {
    enabled         = true,
    animate_counter = true,  -- animated spinner in Telescope's prompt counter
  },
})
```

## License

MIT
