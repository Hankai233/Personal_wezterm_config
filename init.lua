local wezterm = require 'wezterm'

local settings = require 'modules.settings'
local appearance = require 'modules.appearance'

local config = wezterm.config_builder()

appearance.apply(config, settings)

return config
