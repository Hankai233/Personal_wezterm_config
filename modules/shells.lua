local wezterm = require 'wezterm'

local M = {}

-- prog 可能是绝对路径，也可能只是 PATH 中的文件名
function M.exists(prog)
  if type(prog) ~= 'string' or prog == '' then return false end
  if prog:match('^%a:[/\\]') or prog:match('^[/\\]') then
    return wezterm.glob(prog)[1] ~= nil
  end
  local path = os.getenv('PATH') or ''
  for dir in path:gmatch('[^;]+') do
    if wezterm.glob(dir .. '\\' .. prog)[1] then return true end
  end
  return false
end

function M.default_prog(s, exists_fn)
  exists_fn = exists_fn or M.exists
  for _, key in ipairs(s.shells_order) do
    local sh = s.shells[key]
    if sh and exists_fn(sh.prog) then
      local out = { sh.prog }
      for i, a in ipairs(sh.args) do out[i + 1] = a end
      return out
    end
  end
  wezterm.log_warn('wezterm-config: 未找到任何候选 shell，回退到 cmd.exe')
  return { 'cmd.exe' }
end

function M.choices(s, exists_fn)
  exists_fn = exists_fn or M.exists
  local out = {}
  for _, key in ipairs(s.shell_menu_order) do
    local sh = s.shells[key]
    if sh and exists_fn(sh.prog) then
      out[#out + 1] = { label = sh.label, prog = sh.prog, args = sh.args }
    end
  end
  return out
end

-- Task 6 实现：菜单动作（此处先占位返回函数，Task 6 用真实内容替换）
function M.picker_action(s)
  return function(window, pane)
    wezterm.log_warn('wezterm-config: shell 菜单尚未实现')
  end
end

return M
