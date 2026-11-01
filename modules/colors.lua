local wezterm = require 'wezterm'

local M = {}

function M.builtin_names()
  local ok, schemes = pcall(wezterm.color.get_builtin_schemes)
  if not ok or type(schemes) ~= 'table' then return {} end
  local names = {}
  for name in pairs(schemes) do names[#names + 1] = name end
  table.sort(names)
  return names
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

return M
