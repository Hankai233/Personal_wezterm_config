local shells = require 'modules.shells'
local s = require 'modules.settings'

return {
  run = function(check)
    local only_pwsh = function(prog) return prog == 'pwsh.exe' end
    local d1 = shells.default_prog(s, only_pwsh)
    check('default_prog prefers pwsh', d1[1] == 'pwsh.exe' and d1[2] == '-NoLogo')

    local only_ps51 = function(prog) return prog == 'powershell.exe' end
    check('default_prog falls back to powershell 5.1', shells.default_prog(s, only_ps51)[1] == 'powershell.exe')

    local none = function() return false end
    local fb = shells.default_prog(s, none)
    check('default_prog falls back to last shells_order entry from settings', fb[1] == s.shells.cmd.prog)
    check('fallback copies that entry argv', #fb == 1 + #s.shells.cmd.args)

    -- 合成 settings：证明回退项与 argv 都来自 settings，而非硬编码
    local fake = {
      shells_order = { 'alpha', 'ghost', 'omega' },
      shells = {
        alpha = { prog = 'alpha.exe', args = { '-a' } },
        omega = { prog = 'omega.exe', args = { '-o', '--x' } },
      },
    }
    local ff = shells.default_prog(fake, none)
    check('fallback uses last defined shells_order entry', ff[1] == 'omega.exe')
    check('fallback copies fallback argv', #ff == 3 and ff[2] == '-o' and ff[3] == '--x')
    ff[2] = 'mutated'
    check('fallback does not alias settings argv', fake.shells.omega.args[1] == '-o')

    -- 回归：default_shell 指向非 shells_order 首位的有效 key 时必须生效
    local all = function() return true end
    local pref = {
      default_shell = 'omega',
      shells_order = { 'alpha', 'omega' },
      shells = {
        alpha = { prog = 'alpha.exe', args = { '-a' } },
        omega = { prog = 'omega.exe', args = { '-o', '--y' } },
      },
    }
    local dp = shells.default_prog(pref, all)
    check('default_prog honours default_shell when it is not shells_order[1]', dp[1] == 'omega.exe')
    check('default_prog keeps default_shell argv', #dp == 3 and dp[2] == '-o' and dp[3] == '--y')
    dp[2] = 'mutated'
    check('default_prog does not alias default_shell argv', pref.shells.omega.args[1] == '-o')

    -- default_shell 在 shells 里未定义 → 回退到 shells_order 首个可用项
    local bad_key = {
      default_shell = 'nope',
      shells_order = { 'alpha', 'omega' },
      shells = { alpha = { prog = 'alpha.exe', args = {} }, omega = { prog = 'omega.exe', args = {} } },
    }
    check('default_prog ignores undefined default_shell key', shells.default_prog(bad_key, all)[1] == 'alpha.exe')

    -- default_shell 为空串 → 同样回退
    local empty_key = {
      default_shell = '',
      shells_order = { 'alpha', 'omega' },
      shells = { alpha = { prog = 'alpha.exe', args = {} }, omega = { prog = 'omega.exe', args = {} } },
    }
    check('default_prog ignores empty default_shell', shells.default_prog(empty_key, all)[1] == 'alpha.exe')

    -- default_shell 已定义但 prog 不存在 → 继续按 shells_order 降级
    local pref_missing = {
      default_shell = 'omega',
      shells_order = { 'alpha', 'omega' },
      shells = { alpha = { prog = 'alpha.exe', args = {} }, omega = { prog = 'omega.exe', args = {} } },
    }
    local only_alpha = function(prog) return prog == 'alpha.exe' end
    check('default_prog skips missing default_shell prog', shells.default_prog(pref_missing, only_alpha)[1] == 'alpha.exe')

    local ch = shells.choices(s, all)
    check('choices count matches shell_menu_order', #ch == #s.shell_menu_order)
    check('choices have label/prog/args', type(ch[1].label) == 'string' and type(ch[1].prog) == 'string' and type(ch[1].args) == 'table')
    check('choices order preserved', ch[1].prog == 'pwsh.exe' and ch[#ch].prog == 'wsl.exe')

    local only_cmd = function(prog) return prog == 'cmd.exe' end
    check('choices filters missing shells', #shells.choices(s, only_cmd) == 1)

    check('exists finds pwsh on PATH', shells.exists('pwsh.exe') == true)
    check('exists rejects absent exe', shells.exists('no-such-exe-xyz.exe') == false)
    -- 同步实现的回归点：绝对路径与 PATH 裸名都必须走 io.open，不能走异步的 glob
    check('exists finds absolute path', shells.exists('C:/Program Files/WezTerm/wezterm.exe') == true)
    check('exists rejects absent bare name', shells.exists('definitely-not-a-real-program-xyz.exe') == false)
  end,
}
