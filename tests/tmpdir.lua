-- 测试用的真实临时 colors/ 目录：只有写盘才能让 wezterm.color.load_scheme 读到
-- [metadata] name。放在仓库 tests/ 下（Windows 的系统临时目录在沙箱里可能不可写），
-- 用 rmdir /S /Q 清理；空目录 git 不跟踪，中途失败也不会留下未跟踪文件。
local wezterm = require 'wezterm'

local M = {}
local home = os.getenv('WEZTERM_CONFIG_HOME') or wezterm.config_dir
M.root = home .. '/tests/.tmp-colors'
M.colors_dir = M.root .. '/colors'

local function shell(cmd) pcall(os.execute, cmd) end
local function win(path) return path:gsub('/', '\\') end

function M.path(name) return M.colors_dir .. '/' .. name end

function M.write(name, text)
  local f = io.open(M.path(name), 'wb')
  if not f then return false end
  f:write(text)
  f:close()
  return true
end

function M.reset()
  M.cleanup()
  shell('mkdir "' .. win(M.colors_dir) .. '" 2>nul')
end

function M.cleanup()
  shell('rmdir /S /Q "' .. win(M.root) .. '" 2>nul')
end

-- 文件名 "Fancy File" 与 [metadata] name "Fancy Name" 不同，用于验证方案名以
-- metadata 为准；colors 部分与 colors/example.toml 同构。
M.metadata_toml = [[
[metadata]
name = "Fancy Name"

[colors]
foreground = "#eeeeee"
background = "#111111"
cursor_bg = "#eeeeee"
cursor_border = "#eeeeee"
cursor_fg = "#111111"
selection_bg = "#44475a"
selection_fg = "#f8f8f2"

ansi = [
  "#111111", "#ff5555", "#50fa7b", "#f1fa8c",
  "#6272a4", "#ff79c6", "#8be9fd", "#bbbbbb",
]
brights = [
  "#44475a", "#ff5555", "#50fa7b", "#f1fa8c",
  "#6272a4", "#ff79c6", "#8be9fd", "#ffffff",
]
]]

M.plain_toml = [[
[colors]
foreground = "#eeeeee"
background = "#111111"
cursor_bg = "#eeeeee"
cursor_border = "#eeeeee"
cursor_fg = "#111111"
selection_bg = "#44475a"
selection_fg = "#f8f8f2"

ansi = [
  "#111111", "#ff5555", "#50fa7b", "#f1fa8c",
  "#6272a4", "#ff79c6", "#8be9fd", "#bbbbbb",
]
brights = [
  "#44475a", "#ff5555", "#50fa7b", "#f1fa8c",
  "#6272a4", "#ff79c6", "#8be9fd", "#ffffff",
]
]]

return M
