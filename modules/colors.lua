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

-- 数组或映射统一成 {name = true}：builtin 可传字符串数组（builtin_names 的返回值）
local function to_map(x)
  local m = {}
  if type(x) ~= 'table' then return m end
  for k, v in pairs(x) do
    if type(k) == 'number' then m[v] = true else m[k] = true end
  end
  return m
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

  local custom_map = to_map(custom)
  local custom_list = {}
  for n in pairs(custom_map) do custom_list[#custom_list + 1] = n end
  table.sort(custom_list)
  for _, n in ipairs(custom_list) do
    if not seen[n] then
      seen[n] = true
      out[#out + 1] = { name = n, group = 'custom' }
    end
  end

  local builtin_map = to_map(builtin)
  local bnames = {}
  for n in pairs(builtin_map) do bnames[#bnames + 1] = n end
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

-- 菜单动作：按下键时才枚举配色（glob 在这时是安全的）
function M.picker_action(s)
  return function(window, pane)
    local custom_dir = wezterm.config_dir .. '/colors'
    local merged = M.merge(M.builtin_names(), M.list_custom(custom_dir), M.recent_names())
    if #merged == 0 then
      wezterm.log_warn('wezterm-config: 没有可用的配色方案')
      return
    end

    local choices = {}
    for i, item in ipairs(merged) do
      local tag = item.group == 'recent' and '[最近] ' or (item.group == 'custom' and '[自定义] ' or '')
      choices[i] = { id = tostring(i), label = tag .. item.name }
    end

    window:perform_action(wezterm.action.InputSelector {
      title = '切换配色方案（输入可过滤）',
      fuzzy = true,
      choices = choices,
      action = wezterm.action_callback(function(win, p, id)
        local item = merged[tonumber(id)]
        if not item then return end
        -- 读-合并-写，避免冲掉字体缩放等其他 overrides
        local overrides = win:get_config_overrides() or {}
        overrides.color_scheme = item.name
        win:set_config_overrides(overrides)
        M.push_recent(item.name)
      end),
    }, pane)
  end
end

return M
