local wezterm = require 'wezterm'

local home = os.getenv('WEZTERM_CONFIG_HOME') or wezterm.config_dir
local out_path = os.getenv('WEZTEST_OUT') or (home .. '/tests/last-run.txt')

package.path = home .. '/?.lua;' .. home .. '/?/init.lua;' .. package.path

local results = {}
local passed, failed = 0, 0

local function check(name, ok, detail)
  if ok then
    passed = passed + 1
    results[#results + 1] = 'PASS ' .. name
  else
    failed = failed + 1
    results[#results + 1] = 'FAIL ' .. name .. (detail and (' :: ' .. tostring(detail)) or '')
  end
end

local cases = { 'settings', 'appearance', 'shells' }
for _, c in ipairs(cases) do
  local ok, mod = pcall(require, 'tests.cases.' .. c)
  if not ok then
    check('load case ' .. c, false, mod)
  else
    local rok, rerr = pcall(mod.run, check)
    if not rok then check('run case ' .. c, false, rerr) end
  end
end

results[#results + 1] = string.format('SUMMARY pass=%d fail=%d', passed, failed)
local f = io.open(out_path, 'w')
if f then
  f:write(table.concat(results, '\n') .. '\n')
  f:close()
end

return {}
