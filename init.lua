local wezterm = require 'wezterm'

local settings = require 'modules.settings'
local appearance = require 'modules.appearance'
local colors = require 'modules.colors'
local shells = require 'modules.shells'
local keys = require 'modules.keys'

local config = wezterm.config_builder()

appearance.apply(config, settings)

colors.apply_initial(config, settings)

config.default_prog = shells.default_prog(settings)

config.mouse_bindings = keys.mouse_bindings()
config.keys = keys.build(keys.entries, function(fn)
  return wezterm.action_callback(fn)
end)

return config
