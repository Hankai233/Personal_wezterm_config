local wezterm = require 'wezterm'
local proc = require 'modules.proc'

local M = {}

-- 排序模式：循环顺序即下面这个数组的顺序
M.MODES = { 'recent', 'name', 'group' }
M.RECENT_MAX = 10

local RECENT_KEY = 'ssh_recent_hosts'
local MODE_KEY = 'ssh_sort_mode'

local function is_nonempty_string(v)
  return type(v) == 'string' and v ~= ''
end

-- wezterm.GLOBAL 在个别上下文可能取不到，取不到就退化成「无记忆」
local function globals()
  local ok, g = pcall(function() return wezterm.GLOBAL end)
  if ok and type(g) == 'table' then return g end
  return nil
end

local function index_of(list, value)
  for i, v in ipairs(list) do
    if v == value then return i end
  end
  return nil
end

function M.normalize_mode(mode)
  if is_nonempty_string(mode) and index_of(M.MODES, mode) then return mode end
  return M.MODES[1]
end

function M.recent_names()
  local g = globals()
  if not g or type(g[RECENT_KEY]) ~= 'table' then return {} end
  local out = {}
  for i, name in ipairs(g[RECENT_KEY]) do out[i] = name end
  return out
end

function M.push_recent(name)
  if not is_nonempty_string(name) then return end
  local g = globals()
  if not g then return end
  local list = { name }
  for _, n in ipairs(type(g[RECENT_KEY]) == 'table' and g[RECENT_KEY] or {}) do
    if n ~= name and #list < M.RECENT_MAX then list[#list + 1] = n end
  end
  g[RECENT_KEY] = list
end

function M.sort_mode(cfg)
  local g = globals()
  if g and is_nonempty_string(g[MODE_KEY]) then return M.normalize_mode(g[MODE_KEY]) end
  return M.normalize_mode(cfg and cfg.sort_default)
end

function M.set_sort_mode(mode)
  local g = globals()
  if not g then return end
  g[MODE_KEY] = M.normalize_mode(mode)
end

-- 循环切换：recent -> name -> group -> recent
function M.next_mode(mode)
  local current = M.normalize_mode(mode)
  local idx = index_of(M.MODES, current)
  return M.MODES[(idx % #M.MODES) + 1]
end

-- 只保留 name/host 齐全的记录；写错的记录直接跳过，不让整份配置炸掉
function M.valid_hosts(cfg)
  local out = {}
  for _, h in ipairs((cfg and cfg.hosts) or {}) do
    if type(h) == 'table' and is_nonempty_string(h.name) and is_nonempty_string(h.host) then
      out[#out + 1] = h
    end
  end
  return out
end

-- 菜单与 ssh 共用的目标串：user@host，端口只在非 22 时单独出现
function M.target(h)
  local host = tostring(h.host)
  if is_nonempty_string(h.user) then
    return h.user .. '@' .. host
  end
  return host
end

-- argv 顺序固定：ssh [-p port] [-i identity] <extra...> [user@]host
-- 纯函数，便于测试钉死；返回新表，不引用 ssh_hosts.lua 里的任何表
function M.build_argv(cfg, h)
  local argv = { (cfg and cfg.ssh_prog) or 'ssh.exe' }
  local port = tonumber(h.port)
  if port and port ~= 22 then
    argv[#argv + 1] = '-p'
    argv[#argv + 1] = tostring(port)
  end
  if is_nonempty_string(h.identity) then
    argv[#argv + 1] = '-i'
    argv[#argv + 1] = h.identity
  end
  for _, a in ipairs(h.extra or {}) do
    argv[#argv + 1] = tostring(a)
  end
  argv[#argv + 1] = M.target(h)
  return argv
end

-- 菜单标签：[group]  name  user@host:port  -- note
function M.label(h)
  local parts = {}
  if is_nonempty_string(h.group) then parts[#parts + 1] = '[' .. h.group .. ']' end
  parts[#parts + 1] = h.name
  local target = M.target(h)
  local port = tonumber(h.port)
  if port and port ~= 22 then target = target .. ':' .. tostring(port) end
  parts[#parts + 1] = target
  if is_nonempty_string(h.note) then parts[#parts + 1] = '-- ' .. h.note end
  return table.concat(parts, '  ')
end

-- 排序：返回新数组，不改动入参；同键用原始下标兜底，保证结果稳定可预期
function M.sort_hosts(hosts, mode, recent)
  mode = M.normalize_mode(mode)
  local rank = {}
  for i, name in ipairs(recent or {}) do
    if rank[name] == nil then rank[name] = i end
  end
  local missing = math.huge

  local decorated = {}
  for i, h in ipairs(hosts or {}) do
    local group = is_nonempty_string(h.group) and h.group:lower() or ''
    decorated[i] = {
      host = h,
      index = i,
      name = h.name:lower(),
      -- 没有分组的条目排在分组之后
      group_key = group == '' and '\255' or group,
      recent_key = rank[h.name] or missing,
    }
  end

  table.sort(decorated, function(a, b)
    if mode == 'recent' then
      if a.recent_key ~= b.recent_key then return a.recent_key < b.recent_key end
    elseif mode == 'group' then
      if a.group_key ~= b.group_key then return a.group_key < b.group_key end
    end
    if a.name ~= b.name then return a.name < b.name end
    return a.index < b.index
  end)

  local out = {}
  for i, d in ipairs(decorated) do out[i] = d.host end
  return out
end

function M.choices(cfg, mode, recent)
  local ordered = M.sort_hosts(M.valid_hosts(cfg), mode, recent)
  local choices = {}
  for i, h in ipairs(ordered) do
    choices[i] = { id = tostring(i), label = M.label(h) }
  end
  return choices, ordered
end

-- 菜单动作：按下键才探测 ssh、枚举主机；配置加载阶段不做任何 IO
function M.picker_action(cfg)
  return function(window, pane)
    local prog = (cfg and cfg.ssh_prog) or 'ssh.exe'
    if not proc.exists(prog) then
      wezterm.log_warn('wezterm-config: 找不到 ssh 程序 "' .. tostring(prog) .. '"')
      return
    end
    local hosts = M.valid_hosts(cfg)
    if #hosts == 0 then
      wezterm.log_warn('wezterm-config: SSH 主机清单为空，请在 modules/ssh_hosts.lua 里添加')
      return
    end

    local mode = M.sort_mode(cfg)
    local choices, ordered = M.choices(cfg, mode, M.recent_names())
    window:perform_action(wezterm.action.InputSelector {
      title = 'SSH 主机 · 排序：' .. mode .. '（输入可筛选）',
      fuzzy = true,
      choices = choices,
      action = wezterm.action_callback(function(win, p, id)
        local h = ordered[tonumber(id)]
        if not h then return end
        -- 20240203 的 SpawnCommand 没有 prog 字段：可执行文件必须是 args[1]
        win:perform_action(wezterm.action.SpawnCommandInNewTab {
          args = M.build_argv(cfg, h),
        }, p)
        M.push_recent(h.name)
      end),
    }, pane)
  end
end

-- 循环切换排序模式；toast 不可用时退回日志，绝不因为提示失败而中断
function M.cycle_sort_action(cfg)
  return function(window, pane)
    local mode = M.next_mode(M.sort_mode(cfg))
    M.set_sort_mode(mode)
    local body = 'SSH 排序：' .. mode
    local ok = pcall(function()
      wezterm.toast_notification({ title = 'WezTerm', body = body })
    end)
    if not ok then wezterm.log_info(body) end
  end
end

return M
