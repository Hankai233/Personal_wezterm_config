-- 唯一可改常量区：想改行为，先改这里。
return {
  font = 'Maple Mono NF CN',
  font_size = 11,
  line_height = 1.0,
  harfbuzz_features = { 'calt', 'liga' },

  -- 默认 shell 与降级顺序
  default_shell = 'pwsh',
  shells_order = { 'pwsh', 'powershell51', 'cmd' },

  -- shell 菜单（顺序即显示顺序）
  shell_menu_order = { 'pwsh', 'powershell51', 'cmd', 'gitbash', 'wsl' },
  shells = {
    pwsh = { label = 'PowerShell 7 (pwsh)', prog = 'pwsh.exe', args = { '-NoLogo' } },
    powershell51 = { label = 'Windows PowerShell 5.1', prog = 'powershell.exe', args = { '-NoLogo' } },
    cmd = { label = 'Command Prompt (cmd)', prog = 'cmd.exe', args = {} },
    gitbash = {
      label = 'Git Bash',
      prog = 'C:/Users/Hanka/scoop/apps/git/current/bin/bash.exe',
      args = { '-l', '-i' },
    },
    wsl = { label = 'WSL: Debian', prog = 'wsl.exe', args = { '-d', 'Debian' } },
  },

  -- 配色
  default_scheme = 'Catppuccin Mocha',

  scrollback_lines = 10000,
  window_padding = { left = 4, right = 4, top = 4, bottom = 4 },
  copy_on_select = true,
}
