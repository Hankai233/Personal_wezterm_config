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

-- 同步存在性检查：wezterm.glob 是异步的（内部 coroutine.yield），在 require 加载的
-- 配置块里调用会报 "attempt to yield across a C-call boundary" 并让整个配置回退默认值。
-- io.open 只打开句柄、不读内容，任何上下文都安全。
-- errno 22 (EINVAL) 是 Windows App Execution Alias 的表现（如 WindowsApps\pwsh.exe 这类
-- 0 字节 reparse point，CreateProcess 能正常拉起）；目录会返回 13 (EACCES)，不算可执行项。
local EINVAL = 22

local function file_exists(path)
  local f, _, errno = io.open(path, 'r')
  if f then
    f:close()
    return true
  end
  return errno == EINVAL
end

-- prog 可能是绝对路径，也可能只是 PATH 中的文件名
function M.exists(prog)
  if type(prog) ~= 'string' or prog == '' then return false end
  if prog:match('^%a:[/\\]') or prog:match('^[/\\]') then
    return file_exists(prog)
  end
  local path = os.getenv('PATH') or ''
  for dir in path:gmatch('[^;]+') do
    if file_exists(dir .. '\\' .. prog) then return true end
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

-- 菜单动作：按下键时才枚举 shell 与文件，配置加载阶段不做任何 IO
function M.picker_action(s)
  return function(window, pane)
    local items = M.choices(s)
    if #items == 0 then
      wezterm.log_warn('wezterm-config: 没有可用的 shell')
      return
    end
    local choices = {}
    for i, it in ipairs(items) do
      choices[i] = { id = tostring(i), label = it.label }
    end
    window:perform_action(wezterm.action.InputSelector {
      title = '在哪个 shell 打开新标签？',
      fuzzy = true,
      choices = choices,
      action = wezterm.action_callback(function(win, p, id)
        local it = items[tonumber(id)]
        if not it then return end
        -- 20240203 的 SpawnCommand 没有 prog 字段：可执行文件必须是 args[1]
        win:perform_action(wezterm.action.SpawnCommandInNewTab {
          args = prog_with_args(it),
        }, p)
      end),
    }, pane)
  end
end

return M
