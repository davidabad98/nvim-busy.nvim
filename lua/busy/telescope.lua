-- lua/busy/telescope.lua
-- Telescope signal integration for nvim-busy.
--
-- Two responsibilities:
--
-- 1. Bottom-bar integration:
--    - `User TelescopeFindPre` fires before the picker mounts.
--      We push a busy id immediately so the bottom bar activates.
--    - We then schedule a tick to hook `register_completion_callback`
--      on the newly created picker. The callback pops the busy id when
--      one full search cycle finishes.
--    - `BufUnload` on the prompt buffer is a safety-net pop for when the
--      user closes Telescope without waiting for results.
--    - Each new query typed re-pushes the id (on_lines attach) so the bar
--      stays active across multiple search cycles in the same picker session.
--
-- 2. In-prompt animated counter (get_status_text):
--    - Replaces Telescope's built-in "*" in-progress marker with an
--      animated braille frame derived from hrtime() — no separate timer.
--    - Switches to a plain "N / M" count when opts.completed == true.
--    - Users wire this in via their telescope defaults config (see below).

local M = {}
local state = require("busy.state")

local BUSY_ID = "telescope:search"
local _augroup = nil

-- ---------------------------------------------------------------------------
-- Setup: bottom-bar busy state tied to Telescope picker lifecycle
-- ---------------------------------------------------------------------------

function M.setup(_opts)
  -- Idempotent: clear any previous augroup.
  _augroup = vim.api.nvim_create_augroup("NvimBusyTelescope", { clear = true })

  vim.api.nvim_create_autocmd("User", {
    group = _augroup,
    pattern = "TelescopeFindPre",
    callback = function()
      -- Mark busy immediately — the picker windows don't exist yet.
      state.push(BUSY_ID)

      -- Defer one tick so the picker has mounted and is accessible.
      vim.schedule(function()
        -- Both requires are pcall-guarded: if Telescope is uninstalled
        -- mid-session these will fail gracefully and we just clear.
        local ok_as, action_state = pcall(require, "telescope.actions.state")
        local ok_ts, tstate = pcall(require, "telescope.state")
        if not ok_as or not ok_ts then
          state.pop(BUSY_ID)
          return
        end

        local prompt_bufnrs = tstate.get_existing_prompt_bufnrs()
        if not prompt_bufnrs or #prompt_bufnrs == 0 then
          state.pop(BUSY_ID)
          return
        end

        for _, bufnr in ipairs(prompt_bufnrs) do
          local picker = action_state.get_current_picker(bufnr)
          if not picker then
            state.pop(BUSY_ID)
          else
            -- "Search complete" signal: fires after each find-cycle ends.
            -- We pop here; re-push happens on on_lines when user types again.
            picker:register_completion_callback(function()
              vim.schedule(function()
                state.pop(BUSY_ID)
              end)
            end)

            -- Re-push every time the user types (new search cycle starts).
            -- nvim_buf_attach stacks safely with Telescope's own attachment.
            vim.api.nvim_buf_attach(bufnr, false, {
              on_lines = function()
                -- Only re-push if we're not already counted as busy
                -- (avoids count inflation on every keystroke).
                local active = state.active()
                if not active[BUSY_ID] or active[BUSY_ID] == 0 then
                  state.push(BUSY_ID)
                end
              end,
            })

            -- Safety-net: pop when the prompt buffer is destroyed
            -- (user closed Telescope, e.g. pressed <Esc>).
            vim.api.nvim_create_autocmd("BufUnload", {
              group = _augroup,
              buffer = bufnr,
              once = true,
              callback = function()
                -- Force-clear: use reset-style pop until gone.
                for _ = 1, 10 do
                  if state.active()[BUSY_ID] then
                    state.pop(BUSY_ID)
                  else
                    break
                  end
                end
              end,
            })
          end
        end
      end)
    end,
  })
end

-- ---------------------------------------------------------------------------
-- get_status_text: animated in-prompt counter
--
-- Wire into your telescope setup defaults:
--   defaults = {
--     get_status_text = require("busy.telescope").get_status_text,
--   }
-- ---------------------------------------------------------------------------

---@param self table  Telescope Picker object (has self.stats).
---@param opts table|nil  { completed = bool } passed by Telescope internally.
---@return string  Right-aligned virtual text shown in the prompt window.
function M.get_status_text(self, opts)
  local animation = require("busy.animation")

  local showing = (self.stats.processed or 0) - (self.stats.filtered or 0)
  local total = self.stats.processed or 0
  local multi = #(self:get_multi_selection())

  if opts and not opts.completed then
    -- Search in progress: animated braille frame + current counts.
    -- Frame advances automatically because hrtime() changes each call.
    local frame = animation.current_frame("bounce", 100)
    if multi > 0 then
      return frame .. "  " .. multi .. " / " .. showing .. " / " .. total
    end
    return frame .. "  " .. showing .. " / " .. total
  else
    -- Search complete: plain count, spinner gone.
    if showing == 0 and total == 0 then
      return ""
    end
    if multi > 0 then
      return "  " .. multi .. " / " .. showing .. " / " .. total
    end
    return "  " .. showing .. " / " .. total
  end
end

return M
