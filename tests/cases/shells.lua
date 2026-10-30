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

    local all = function() return true end
    local ch = shells.choices(s, all)
    check('choices count matches shell_menu_order', #ch == #s.shell_menu_order)
    check('choices have label/prog/args', type(ch[1].label) == 'string' and type(ch[1].prog) == 'string' and type(ch[1].args) == 'table')
    check('choices order preserved', ch[1].prog == 'pwsh.exe' and ch[#ch].prog == 'wsl.exe')

    local only_cmd = function(prog) return prog == 'cmd.exe' end
    check('choices filters missing shells', #shells.choices(s, only_cmd) == 1)

    check('exists finds pwsh on PATH', shells.exists('pwsh.exe') == true)
    check('exists rejects absent exe', shells.exists('no-such-exe-xyz.exe') == false)
  end,
}
