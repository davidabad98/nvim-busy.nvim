-- lua/busy/animation.lua
-- Braille and other spinner frame tables.
-- current_frame() is a pure function of wall-clock time — no state, no timer.

local M = {}

-- Built-in animation patterns.
-- Each is a table of UTF-8 strings cycled at `speed_ms` per frame.
M.patterns = {
  -- Braille "breathing" — grows full then shrinks back (OpenCode-style)
  dots = { "⠁", "⠃", "⠇", "⠏", "⠟", "⠿", "⠟", "⠏", "⠇", "⠃" },

  -- Braille spinner (circular sweep)
  bounce = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },

  -- Minimal arc
  arc = { "◜", "◠", "◝", "◞", "◡", "◟" },

  -- ASCII fallback — works in any terminal / font
  line = { "|", "/", "-", "\\" },
}

--- Returns the current animation frame string.
-- Pure function: frame index derived from hrtime(), no module state needed.
-- This means it animates smoothly as long as the caller refreshes regularly
-- (driven by the window.lua timer).
--
-- @param pattern string|table  Named pattern key or a raw frame table.
-- @param speed_ms number       Milliseconds per frame (default 80).
-- @return string               The current frame character.
function M.current_frame(pattern, speed_ms)
  local frames
  if type(pattern) == "table" then
    frames = pattern
  else
    frames = M.patterns[pattern] or M.patterns.dots
  end

  local ms = speed_ms or 80
  -- hrtime() returns nanoseconds; divide to get ms buckets.
  local idx = math.floor(vim.uv.hrtime() / (ms * 1e6)) % #frames
  return frames[idx + 1]
end

return M
