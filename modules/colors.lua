local wezterm = require 'wezterm'

local M = {}

local function name_of(path)
  local base = path:gsub('\\', '/'):match('([^/]+)$') or ''
  return (base:gsub('%.toml$', ''))
end

function M.builtin_names()
  local ok, schemes = pcall(wezterm.color.get_builtin_schemes)
  if not ok or type(schemes) ~= 'table' then return {} end
  local names = {}
  for name in pairs(schemes) do names[#names + 1] = name end
  table.sort(names)
  return names
end

function M.list_custom(dir)
  local ok, files = pcall(function() return wezterm.glob(dir .. '/*.toml') end)
  if not ok or type(files) ~= 'table' then return {} end
  local names = {}
  for _, f in ipairs(files) do names[#names + 1] = name_of(f) end
  table.sort(names)
  return names
end

-- 最近使用：wezterm.GLOBAL 跨配置重载保留；配置加载阶段可能不可用，用 pcall 兜底
function M.recent_names()
  local ok, g = pcall(function() return wezterm.GLOBAL end)
  if not ok or type(g) ~= 'table' or type(g.recent_schemes) ~= 'table' then return {} end
  return g.recent_schemes
end

function M.push_recent(name)
  local ok, g = pcall(function() return wezterm.GLOBAL end)
  if not ok or type(g) ~= 'table' then return end
  local list = {}
  list[1] = name
  for _, n in ipairs(g.recent_schemes or {}) do
    if n ~= name and #list < 5 then list[#list + 1] = n end
  end
  g.recent_schemes = list
end

-- 返回 [{name, group}]：recent > custom > builtin，同名片后者覆盖前者
function M.merge(builtin, custom, recent)
  local out, seen = {}, {}

  for _, n in ipairs(recent or {}) do
    if not seen[n] then
      seen[n] = true
      out[#out + 1] = { name = n, group = 'recent' }
    end
  end

  for _, n in ipairs(custom or {}) do
    if not seen[n] then
      seen[n] = true
      out[#out + 1] = { name = n, group = 'custom' }
    end
  end

  local bnames = {}
  for n in pairs(builtin or {}) do bnames[#bnames + 1] = n end
  table.sort(bnames)
  for _, n in ipairs(bnames) do
    if not seen[n] then
      seen[n] = true
      out[#out + 1] = { name = n, group = 'builtin' }
    end
  end

  return out
end

function M.apply_initial(config, s)
  local names = M.builtin_names()
  for _, n in ipairs(names) do
    if n == s.default_scheme then
      config.color_scheme = n
      return
    end
  end
  wezterm.log_warn('wezterm-config: 配色 "' .. tostring(s.default_scheme) .. '" 不存在，使用 WezTerm 默认配色')
end

-- Task 6 实现真实菜单
function M.picker_action(s)
  return function(window, pane)
    wezterm.log_warn('wezterm-config: 配色菜单尚未实现')
  end
end

return M
