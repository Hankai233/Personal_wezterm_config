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
    check('default_prog falls back to cmd', shells.default_prog(s, none)[1] == 'cmd.exe')

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
