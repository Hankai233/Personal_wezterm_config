local wezterm = require 'wezterm'
local colors = require 'modules.colors'
local s = require 'modules.settings'
local tmp = require 'tests.tmpdir'

local function has_name(list, name)
  for _, x in ipairs(list) do if x.name == name then return x end end
  return nil
end

local function has_value(list, value)
  for _, x in ipairs(list) do if x == value then return true end end
  return false
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

    -- merge 必须同时接受数组和映射两种输入，且顺序固定为 recent > custom(排序) > builtin(排序)
    local arr_builtin = colors.merge({ 'Zzz', 'Nord' }, { ['my-theme'] = true, Nord = true }, { 'Nord' })
    check('merge accepts array builtin and map custom', #arr_builtin == 3)
    check('merge array builtin order', arr_builtin[1].name == 'Nord' and arr_builtin[1].group == 'recent'
      and arr_builtin[2].name == 'my-theme' and arr_builtin[2].group == 'custom'
      and arr_builtin[3].name == 'Zzz' and arr_builtin[3].group == 'builtin')

    local map_builtin = colors.merge({ Zzz = true, Nord = true }, { 'my-theme', 'Nord' }, {})
    check('merge accepts map builtin and array custom', #map_builtin == 3)
    check('merge map builtin order', map_builtin[1].name == 'Nord' and map_builtin[1].group == 'custom'
      and map_builtin[2].name == 'my-theme' and map_builtin[2].group == 'custom'
      and map_builtin[3].name == 'Zzz' and map_builtin[3].group == 'builtin')

    local dup_count = 0
    for _, x in ipairs(arr_builtin) do if x.name == 'Nord' then dup_count = dup_count + 1 end end
    check('merge suppresses cross-group duplicates once', dup_count == 1)

    local empty = colors.merge({}, {}, {})
    check('merge tolerates empty inputs', type(empty) == 'table' and #empty == 0)

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

    -- Fix A：WezTerm 用 TOML 的 [metadata] name 当方案名；文件名不同的文件必须
    -- 以 metadata 名出现在列表里，两个文件撞同一个 metadata 名只出现一次。
    tmp.reset()
    local ok_a, err_a = pcall(function()
      check('wrote metadata scheme', tmp.write('Fancy File.toml', tmp.metadata_toml))
      check('wrote plain scheme', tmp.write('plain-theme.toml', tmp.plain_toml))
      check('wrote second metadata scheme',
        tmp.write('Another File.toml', tmp.metadata_toml))

      local listed_tmp = colors.list_custom(tmp.colors_dir)
      check('list_custom lists metadata name', has_value(listed_tmp, 'Fancy Name'))
      check('list_custom lists plain filename stem', has_value(listed_tmp, 'plain-theme'))
      check('list_custom hides metadata file stem', not has_value(listed_tmp, 'Fancy File'))
      check('list_custom dedupes by metadata name', #listed_tmp == 2
        and listed_tmp[1] == 'Fancy Name' and listed_tmp[2] == 'plain-theme')
    end)
    tmp.cleanup()
    if not ok_a then error(err_a) end

    -- Fix B：default_scheme 也可以指向 colors/<name>.toml；metadata 改名时写入真实名。
    tmp.reset()
    local ok_b, err_b = pcall(function()
      tmp.write('Fancy File.toml', tmp.metadata_toml)
      tmp.write('plain-theme.toml', tmp.plain_toml)

      local custom_cfg = {}
      colors.apply_initial(custom_cfg, { default_scheme = 'plain-theme' }, tmp.root)
      check('apply_initial accepts custom scheme file', custom_cfg.color_scheme == 'plain-theme')

      local renamed_cfg = {}
      colors.apply_initial(renamed_cfg, { default_scheme = 'Fancy File' }, tmp.root)
      check('apply_initial uses metadata scheme name', renamed_cfg.color_scheme == 'Fancy Name')

      local warnings = {}
      local orig_warn = wezterm.log_warn
      wezterm.log_warn = function(msg) warnings[#warnings + 1] = msg end
      local unknown_cfg = {}
      local ok_unknown, err_unknown = pcall(colors.apply_initial, unknown_cfg,
        { default_scheme = 'No Such Scheme xyz' }, tmp.root)
      wezterm.log_warn = orig_warn
      check('apply_initial survives unknown default with dir', ok_unknown, err_unknown)
      check('apply_initial leaves config untouched for unknown custom', unknown_cfg.color_scheme == nil)
      check('apply_initial warns once for unknown custom', #warnings == 1)
    end)
    tmp.cleanup()
    if not ok_b then error(err_b) end

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
