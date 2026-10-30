local appearance = require 'modules.appearance'
local s = require 'modules.settings'

return {
  run = function(check)
    local got = {}
    local fake_config = setmetatable({}, {
      __newindex = function(t, k, v) rawset(t, k, v); got[k] = v end,
    })

    appearance.apply(fake_config, s)

    check('appearance sets font object', got.font ~= nil)
    check('appearance sets font_size', got.font_size == s.font_size)
    check('appearance sets line_height', got.line_height == s.line_height)
    check('appearance sets harfbuzz_features', got.harfbuzz_features == s.harfbuzz_features)
    check('appearance sets square glyph policy', got.allow_square_glyphs_to_overflow_width == 'WhenFollowedBySpace')
  end,
}
