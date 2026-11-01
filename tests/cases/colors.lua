local wezterm = require 'wezterm'
local colors = require 'modules.colors'
local s = require 'modules.settings'
local tmp = require 'tests.tmpdir'

return {
  run = function(check)
    local names = colors.builtin_names()
    check('builtin_names non-empty', type(names) == 'table' and #names > 100)
    local found = false
    for _, n in ipairs(names) do if n == 'Catppuccin Mocha' then found = true end end
    check('builtin contains Catppuccin Mocha', found)

    local default_ok = false
    for _, n in ipairs(names) do if n == s.default_scheme then default_ok = true end end
    check('settings.default_scheme resolvable', default_ok)

    -- Fix B：default_scheme 也可以指向 colors/<name>.toml；metadata 改名时写入真实名。
    tmp.with(function()
      tmp.write('Fancy File.toml', tmp.metadata_toml)
      tmp.write('plain-theme.toml', tmp.plain_toml)

      local custom_cfg = {}
      colors.apply_initial(custom_cfg, { default_scheme = 'plain-theme' }, tmp.root)
      check('apply_initial accepts custom scheme file', custom_cfg.color_scheme == 'plain-theme')
      -- colors/*.toml 必须同时注册到 WezTerm 的方案目录；否则用 --config-file
      -- 从别处启动时，这些方案不会被原生加载。
      check('apply_initial registers color_scheme_dirs for an explicit dir',
        type(custom_cfg.color_scheme_dirs) == 'table'
          and #custom_cfg.color_scheme_dirs == 1
          and custom_cfg.color_scheme_dirs[1] == tmp.root .. '/colors')

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

    -- apply_initial 是 init.lua 里唯一与运行时配置交互的入口，必须真的写进 config
    local cfg = {}
    colors.apply_initial(cfg, { default_scheme = 'Catppuccin Mocha' })
    check('apply_initial sets a valid builtin scheme', cfg.color_scheme == 'Catppuccin Mocha')

    local applied = {}
    colors.apply_initial(applied, s)
    check('apply_initial applies settings.default_scheme', applied.color_scheme == s.default_scheme)
    -- 即使通过 --config-file 指向仓库外的路径，也要把本仓库的 colors/ 注册给
    -- WezTerm（原生字段，配置加载期只做字符串拼接，不 yield）。
    check('apply_initial registers the default colors dir',
      type(applied.color_scheme_dirs) == 'table'
        and #applied.color_scheme_dirs == 1
        and applied.color_scheme_dirs[1] == wezterm.config_dir .. '/colors')

    local unknown = {}
    colors.apply_initial(unknown, { default_scheme = 'No Such Scheme xyz' })
    check('apply_initial leaves config untouched for unknown scheme', unknown.color_scheme == nil)

    -- 选择器已删除：这些入口不能再被实现意外带回（README 已不再宣传）。
    check('colors picker helpers are gone',
      colors.picker_action == nil and colors.merge == nil and colors.list_custom == nil
        and colors.recent_names == nil and colors.push_recent == nil)
  end,
}
