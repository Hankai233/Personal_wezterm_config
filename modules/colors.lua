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

-- 方案名由 WezTerm 决定：TOML 里有 [metadata] name 就用它，否则才用文件名。
-- 所以不能直接拿文件名当方案名，否则带 metadata 的文件选中后会“找不到方案”。
-- list_custom 只在选择器的按键路径上调用；这里的 load_scheme 是同步读文件，
-- 不受配置加载期“不能 yield”的限制。
function M.list_custom(dir)
  local ok, files = pcall(function() return wezterm.glob(dir .. '/*.toml') end)
  if not ok or type(files) ~= 'table' then return {} end
  local names, seen = {}, {}
  for _, f in ipairs(files) do
    local name = name_of(f)
    -- load_scheme 返回 (颜色表, metadata)；第二项里的 name 就是 WezTerm 用的方案名。
    local ok_load, _, meta = pcall(wezterm.color.load_scheme, f)
    if ok_load and type(meta) == 'table' and type(meta.name) == 'string' and meta.name ~= '' then
      name = meta.name
    end
    if not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
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

function M.apply_initial(config, s, dir)
  dir = dir or wezterm.config_dir
  -- 把 colors/ 注册成 WezTerm 的原生方案目录；这样即使通过 --config-file 指向
  -- 别处启动，colors/*.toml 也会被原生加载。纯字符串拼接，配置加载期不 yield。
  config.color_scheme_dirs = { dir .. '/colors' }
  local names = M.builtin_names()
  for _, n in ipairs(names) do
    if n == s.default_scheme then
      config.color_scheme = n
      return
    end
  end
  -- 也接受 colors/<name>.toml 里的自定义方案。这里是配置加载阶段：只读单个文件，
  -- 不能用 wezterm.glob（会让配置加载报 yield across C-call boundary）。
  local ok, _, meta = pcall(wezterm.color.load_scheme, dir .. '/colors/' .. tostring(s.default_scheme) .. '.toml')
  if ok then
    if type(meta) == 'table' and type(meta.name) == 'string' and meta.name ~= '' then
      config.color_scheme = meta.name -- TOML metadata 名才是 WezTerm 认的方案名
    else
      config.color_scheme = s.default_scheme
    end
    return
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
