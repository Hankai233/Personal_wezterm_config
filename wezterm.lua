-- WezTerm 从这里进入：先补 package.path，再交给 init.lua
local wezterm = require 'wezterm'
local dir = wezterm.config_dir

package.path = dir .. '/?.lua;' .. dir .. '/?/init.lua;' .. package.path

return require 'init'
