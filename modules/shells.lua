local wezterm = require 'wezterm'

local M = {}

-- 复制 prog + argv 到新表，避免返回值引用 settings 里的表
local function prog_with_args(sh)
  local out = { sh.prog }
  for i, a in ipairs(sh.args or {}) do out[i + 1] = a end
  return out
end

-- 回退源：shells_order 中最后一个仍在 settings 里定义的候选（默认即 cmd）
local function last_defined(s)
  for i = #s.shells_order, 1, -1 do
    local sh = s.shells[s.shells_order[i]]
    if sh then return sh end
  end
end

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

-- 首选：settings.default_shell 指向的 shell（仅当 key 非空且在 shells 中有定义、prog 可用）
local function preferred(s, exists_fn)
  local key = s.default_shell
  if type(key) ~= 'string' or key == '' then return nil end
  local sh = s.shells[key]
  if sh and exists_fn(sh.prog) then return sh end
  return nil
end

function M.default_prog(s, exists_fn)
  exists_fn = exists_fn or M.exists
  local pref = preferred(s, exists_fn)
  if pref then return prog_with_args(pref) end
  for _, key in ipairs(s.shells_order) do
    local sh = s.shells[key]
    if sh and exists_fn(sh.prog) then
      return prog_with_args(sh)
    end
  end
  local sh = last_defined(s)
  if not sh then
    wezterm.log_warn('wezterm-config: shells_order 中没有已定义的 shell，使用平台默认 shell')
    return {}
  end
  wezterm.log_warn('wezterm-config: 未找到任何候选 shell，回退到 ' .. sh.prog)
  return prog_with_args(sh)
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
