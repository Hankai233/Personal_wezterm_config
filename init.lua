local wezterm = require 'wezterm'

local settings = require 'modules.settings'
local appearance = require 'modules.appearance'
local shells = require 'modules.shells'

local config = wezterm.config_builder()

appearance.apply(config, settings)

config.default_prog = shells.default_prog(settings)

return config
