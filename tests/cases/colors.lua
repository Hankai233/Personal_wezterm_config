local colors = require 'modules.colors'
local s = require 'modules.settings'

local function has_name(list, name)
  for _, x in ipairs(list) do if x.name == name then return x end end
  return nil
end

return {
  run = function(check)
    local builtin = { ['Catppuccin Mocha'] = {}, ['Tokyo Night'] = {}, ['Nord'] = {} }
    local custom = { 'my-theme', 'Nord' }
    local merged = colors.merge(builtin, custom, { 'Tokyo Night' })

    check('merge puts recent first', merged[1].name == 'Tokyo Night' and merged[1].group == 'recent')
    local tokyo_count = 0
    for _, x in ipairs(merged) do if x.name == 'Tokyo Night' then tokyo_count = tokyo_count + 1 end end
    check('merge dedupes recent', tokyo_count == 1)

    local mt = has_name(merged, 'my-theme')
    check('merge includes custom', mt ~= nil and mt.group == 'custom')

    local nord = has_name(merged, 'Nord')
    check('custom shadows builtin of same name', nord ~= nil and nord.group == 'custom')

    local names = colors.builtin_names()
    check('builtin_names non-empty', type(names) == 'table' and #names > 100)
    local found = false
    for _, n in ipairs(names) do if n == 'Catppuccin Mocha' then found = true end end
    check('builtin contains Catppuccin Mocha', found)

    local default_ok = false
    for _, n in ipairs(names) do if n == s.default_scheme then default_ok = true end end
    check('settings.default_scheme resolvable', default_ok)

    local custom_dir = os.getenv('WEZTERM_CONFIG_HOME') .. '/colors'
    local listed = colors.list_custom(custom_dir)
    check('list_custom finds example', (function() for _, n in ipairs(listed) do if n == 'example' then return true end end return false end)())

    -- apply_initial 是 init.lua 里唯一与运行时配置交互的入口，必须真的写进 config
    local cfg = {}
    colors.apply_initial(cfg, { default_scheme = 'Catppuccin Mocha' })
    check('apply_initial sets a valid builtin scheme', cfg.color_scheme == 'Catppuccin Mocha')

    local applied = {}
    colors.apply_initial(applied, s)
    check('apply_initial applies settings.default_scheme', applied.color_scheme == s.default_scheme)

    local unknown = {}
    colors.apply_initial(unknown, { default_scheme = 'No Such Scheme xyz' })
    check('apply_initial leaves config untouched for unknown scheme', unknown.color_scheme == nil)
  end,
}
