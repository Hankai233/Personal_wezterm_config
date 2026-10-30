local wezterm = require 'wezterm'
local settings = require 'modules.settings'
local shells = require 'modules.shells'
local colors = require 'modules.colors'

local M = {}

local function do_action(tbl)
  return function(window, pane)
    window:perform_action(tbl, pane)
  end
end

-- 大写字母键在 20240203 会归一化：SHIFT 隐含在字符里，show-keys 把它显示成
-- CTRL S，但实际匹配的仍是 Ctrl+Shift+S（见 WezTerm 20201031 发行说明）。
M.entries = {
  { key = 'T', mods = 'CTRL|SHIFT', label = '新建标签页', run = do_action(wezterm.action.SpawnTab 'CurrentPaneDomain') },
  { key = 'S', mods = 'CTRL|SHIFT', label = '新建标签页并选择 shell', run = shells.picker_action(settings) },
  { key = 'A', mods = 'CTRL|SHIFT', label = '切换配色方案', run = colors.picker_action(settings) },
  { key = '\\', mods = 'CTRL|SHIFT', label = '左右分屏', run = do_action(wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' }) },
  { key = '-', mods = 'CTRL|SHIFT', label = '上下分屏', run = do_action(wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' }) },
  -- 20240203 只接受物理键码名（LeftArrow/RightArrow/UpArrow/DownArrow），
  -- 'Left'/'Right' 这类写法会报 invalid KeyCode string 并让整个配置加载失败。
  { key = 'LeftArrow', mods = 'ALT', label = '切到左侧 pane', run = do_action(wezterm.action.ActivatePaneDirection 'Left') },
  { key = 'RightArrow', mods = 'ALT', label = '切到右侧 pane', run = do_action(wezterm.action.ActivatePaneDirection 'Right') },
  { key = 'UpArrow', mods = 'ALT', label = '切到上方 pane', run = do_action(wezterm.action.ActivatePaneDirection 'Up') },
  { key = 'DownArrow', mods = 'ALT', label = '切到下方 pane', run = do_action(wezterm.action.ActivatePaneDirection 'Down') },
  { key = 'J', mods = 'CTRL|SHIFT', label = '模糊跳转 pane', run = do_action(wezterm.action.PaneSelect { mode = 'Activate' }) },
  {
    key = 'Space',
    mods = 'CTRL|SHIFT',
    label = 'QuickSelect（URL / 路径 / IP）',
    run = do_action(wezterm.action.QuickSelectArgs {
      patterns = {
        [[\b\w+://[^\s"']+]],
        [[\b\d{1,3}(\.\d{1,3}){3}\b]],
        [=[[A-Za-z0-9_.~/-]{4,}]=],
      },
    }),
  },
  { key = '?', mods = 'CTRL|SHIFT', label = '快捷键帮助', run = nil }, -- 下面补
}

-- 帮助浮层：列出全部自定义键，选中即执行
M.entries[#M.entries].run = function(window, pane)
  local choices = {}
  for i, e in ipairs(M.entries) do
    choices[i] = { id = tostring(i), label = string.format('%-14s %s', e.mods .. '+' .. e.key, e.label) }
  end
  window:perform_action(wezterm.action.InputSelector {
    title = 'WezTerm 快捷键帮助',
    fuzzy = true,
    choices = choices,
    action = wezterm.action_callback(function(win, p, id)
      local e = M.entries[tonumber(id)]
      if e and e.run then e.run(win, p) end
    end),
  }, pane)
end

function M.build(entries, action_cb)
  local list = {}
  for i, e in ipairs(entries) do
    list[i] = { key = e.key, mods = e.mods, action = action_cb(e.run) }
  end
  return list
end

function M.mouse_bindings()
  return {
    {
      event = { Up = { streak = 1, button = 'Right' } },
      mods = 'NONE',
      -- 20240203 的 PasteFrom 直接接收 ClipboardPasteSource 字符串；
      -- 表形式 { source = 'Clipboard' } 属于更新版本的写法，在此版本会报
      -- "`source` is not a valid ClipboardPasteSource variant"。
      action = wezterm.action.PasteFrom 'Clipboard',
    },
  }
end

return M
