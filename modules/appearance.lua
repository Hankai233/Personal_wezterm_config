local wezterm = require 'wezterm'

local M = {}

function M.apply(config, s)
  -- Maple Mono NF CN 自带 CJK 与 Nerd 图标，不需要回退链
  config.font = wezterm.font_with_fallback { s.font }
  config.font_size = s.font_size
  config.line_height = s.line_height
  config.harfbuzz_features = s.harfbuzz_features
  config.allow_square_glyphs_to_overflow_width = 'WhenFollowedBySpace'
end

return M
