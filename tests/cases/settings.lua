local s = require 'modules.settings'

return {
  run = function(check)
    check('settings.font is non-empty string', type(s.font) == 'string' and #s.font > 0)
    check('settings.font_size in range', type(s.font_size) == 'number' and s.font_size >= 8 and s.font_size <= 32)
    check('settings.line_height number', type(s.line_height) == 'number')
    check('settings.harfbuzz_features table', type(s.harfbuzz_features) == 'table')
    check('settings.default_scheme string', type(s.default_scheme) == 'string' and #s.default_scheme > 0)
    check('settings.scrollback_lines number', type(s.scrollback_lines) == 'number' and s.scrollback_lines >= 1000)
    check('settings.shells_order has >= 3', type(s.shells_order) == 'table' and #s.shells_order >= 3)
    check('settings.shell_menu_order has 5', type(s.shell_menu_order) == 'table' and #s.shell_menu_order == 5)

    for _, key in ipairs(s.shells_order) do
      local sh = s.shells[key]
      check('shells.' .. key .. ' shape', type(sh) == 'table'
        and type(sh.prog) == 'string' and #sh.prog > 0
        and type(sh.args) == 'table'
        and type(sh.label) == 'string' and #sh.label > 0)
    end
    for _, key in ipairs(s.shell_menu_order) do
      check('shell_menu_order.' .. key .. ' defined', s.shells[key] ~= nil)
    end
    check('default_shell resolvable', s.shells[s.default_shell] ~= nil)
  end,
}
