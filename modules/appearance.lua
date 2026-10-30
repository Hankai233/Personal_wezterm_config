local wezterm = require 'wezterm'

local M = {}

function M.apply(config, s)
  -- Maple Mono NF CN 自带 CJK 与 Nerd 图标，不需要回退链
  config.font = wezterm.font_with_fallback { s.font }
  config.font_size = s.font_size
  config.line_height = s.line_height
  config.harfbuzz_features = s.harfbuzz_features

  -- 这两项只在 settings 里定义过；不在这里落到 config 上就不会生效。
  config.scrollback_lines = s.scrollback_lines
  config.window_padding = s.window_padding

  config.allow_square_glyphs_to_overflow_width = 'WhenFollowedBySpace'
end

return M
