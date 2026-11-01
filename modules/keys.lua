local wezterm = require 'wezterm'
local settings = require 'modules.settings'
local shells = require 'modules.shells'

local M = {}

local function do_action(tbl)
  return function(window, pane)
    window:perform_action(tbl, pane)
  end
end

-- 大写字母键在 20240203 会归一化：SHIFT 隐含在字符里，show-keys 把它显示成
-- CTRL S，但实际匹配的仍是 Ctrl+Shift+S（见 WezTerm 20201031 发行说明）。
-- 带 shift 的符号键（- \ ?）在 US 布局上可能以 shifted 字符（_ | /）投递，
-- 也可能以基础键 + SHIFT 投递；WezTerm 自己的默认绑定就同时注册了两种拼写。
-- 这里给每个动作补一份 alt 拼写，命中哪个都执行同一动作（只会触发一次）。
M.entries = {
  { key = 'T', mods = 'CTRL|SHIFT', label = '新建标签页', run = do_action(wezterm.action.SpawnTab 'CurrentPaneDomain') },
  { key = 'S', mods = 'CTRL|SHIFT', label = '新建标签页并选择 shell', run = shells.picker_action(settings) },
  { key = 'Q', mods = 'CTRL|SHIFT', label = '关闭分屏', run = do_action(wezterm.action.CloseCurrentPane { confirm = true }) },
  {
    key = '\\',
    mods = 'CTRL|SHIFT',
    label = '左右分屏',
    alts = { { key = '|' } },
    run = do_action(wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' }),
  },
  {
    key = '-',
    mods = 'CTRL|SHIFT',
    label = '上下分屏',
    alts = { { key = '_' } },
    run = do_action(wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' }),
  },
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
  { key = '?', mods = 'CTRL|SHIFT', label = '快捷键帮助', alts = { { key = '/' } }, run = nil }, -- 下面补
}

-- 帮助浮层的选项：按 entries 顺序生成，id 是 1-based 字符串。
-- 单独抽出来，测试才能断言“选项数量/标签与 entries 一一对应”。
function M.help_choices(entries)
  local choices = {}
  for i, e in ipairs(entries) do
    choices[i] = {
      id = tostring(i),
      label = string.format('%-14s %s', e.mods .. '+' .. e.key, e.label),
    }
  end
  return choices
end

-- 帮助浮层选中后按 id 回到对应 entry 并执行它自己的 run。
-- 单独抽出来，测试可以用桩 entries 证明“选中哪个就执行哪个”。
function M.dispatch(entries, id, window, pane)
  local e = entries[tonumber(id)]
  if e and e.run then e.run(window, pane) end
end

-- 帮助浮层：列出全部自定义键，选中即执行
M.entries[#M.entries].run = function(window, pane)
  window:perform_action(wezterm.action.InputSelector {
    title = 'WezTerm 快捷键帮助',
    fuzzy = true,
    choices = M.help_choices(M.entries),
    action = wezterm.action_callback(function(win, p, id)
      M.dispatch(M.entries, id, win, p)
    end),
  }, pane)
end

function M.build(entries, action_cb)
  local list = {}
  for _, e in ipairs(entries) do
    -- 同一动作的 alt 拼写复用同一个 action（同一个 EmitEvent），不重复创建回调；
    -- 帮助浮层仍按 entries 生成，一个动作只显示一行。
    local action = action_cb(e.run)
    list[#list + 1] = { key = e.key, mods = e.mods, action = action }
    for _, alt in ipairs(e.alts or {}) do
      list[#list + 1] = { key = alt.key, mods = alt.mods or e.mods, action = action }
    end
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
