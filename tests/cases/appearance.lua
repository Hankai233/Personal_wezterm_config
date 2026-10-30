local appearance = require 'modules.appearance'
local s = require 'modules.settings'

local function same_padding(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
  return a.left == b.left and a.right == b.right and a.top == b.top and a.bottom == b.bottom
end

return {
  run = function(check)
    local got = {}
    local fake_config = setmetatable({}, {
      __newindex = function(t, k, v) rawset(t, k, v); got[k] = v end,
    })

    appearance.apply(fake_config, s)

    check('appearance sets font object', got.font ~= nil)
    -- wezterm.font_with_fallback 的形状是 { font = { { family=..., ... } } }；
    -- 只断言非 nil 抓不到“字体名写错但对象存在”的情况。
    local primary = type(got.font) == 'table' and type(got.font.font) == 'table' and got.font.font[1]
    check('appearance font object carries a primary face', primary ~= nil)
    check('appearance font family comes from settings', primary ~= nil and primary.family == s.font)
    check('appearance sets font_size', got.font_size == s.font_size)
    check('appearance sets line_height', got.line_height == s.line_height)
    check('appearance sets harfbuzz_features', got.harfbuzz_features == s.harfbuzz_features)
    check('appearance sets square glyph policy', got.allow_square_glyphs_to_overflow_width == 'WhenFollowedBySpace')

    -- settings 里的 scrollback / padding 必须真的落到 config 上；
    -- 否则 settings 只是死代码，README 的“已生效”就是在说谎。
    check('appearance sets scrollback_lines from settings', got.scrollback_lines == s.scrollback_lines)
    check('appearance sets window_padding from settings', same_padding(got.window_padding, s.window_padding))
    -- 20240203 没有 copy_on_select 这个 Config 字段：写进去会让 wezterm 以
    -- "error converting Lua table to Config" 拒绝整份配置并回退默认值。留一条
    -- 反向断言，防止以后又把死字段加回来。
    check('appearance omits unsupported copy_on_select', got.copy_on_select == nil)
  end,
}
