local wezterm = require 'wezterm'
local proc = require 'modules.proc'

return {
  run = function(check)
    check('proc.exists rejects nil', proc.exists(nil) == false)
    check('proc.exists rejects empty', proc.exists('') == false)
    check('proc.exists rejects non-string', proc.exists(42) == false)
    check('proc.exists rejects absent bare name', proc.exists('definitely-not-a-real-program-xyz.exe') == false)

    local home = os.getenv('WEZTERM_CONFIG_HOME') or wezterm.config_dir
    check('proc.exists finds an absolute path that exists', proc.exists(home .. '/wezterm.lua') == true)
    check('proc.exists rejects an absent absolute path',
      proc.exists(home .. '/no-such-file-xyz.lua') == false)

    -- PATH 分支：cmd.exe 随 Windows 提供且必然在 PATH 上
    check('proc.exists finds a program on PATH', proc.exists('cmd.exe') == true)
  end,
}
