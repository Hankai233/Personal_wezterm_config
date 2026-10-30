local wezterm = require 'wezterm'
local shells = require 'modules.shells'
local colors = require 'modules.colors'
local s = require 'modules.settings'

-- 假 window：记录 perform_action 的动作与 pane，并模拟 config overrides 读写。
local function make_window(overrides)
  local w = { performed = {}, set_calls = {}, overrides = overrides }
  function w:perform_action(action, p)
    self.performed[#self.performed + 1] = { action = action, pane = p }
  end
  function w:get_config_overrides()
    return self.overrides
  end
  function w:set_config_overrides(o)
    self.overrides = o
    self.set_calls[#self.set_calls + 1] = o
  end
  return w
end

-- 生产代码用 wezterm.action_callback 包选择回调。真 API 返回合法 KeyAssignment
-- （EmitEvent 动作），InputSelector 只接受这种值，所以不能把回调换成普通表；
-- 这里包一层把闭包抓出来，同时原样返回真动作。
local function with_captured_callback(body)
  local captured
  local real = wezterm.action_callback
  wezterm.action_callback = function(fn)
    captured = fn
    return real(fn)
  end
  local ok, err = pcall(body)
  wezterm.action_callback = real
  if not ok then error(err) end
  return captured
end

local function make_shell_window()
  local win = make_window()
  local pane = { tag = 'pane-1' }
  return win, pane
end

return {
  run = function(check)
    -- ---------- shells.picker_action ----------
    local expected = shells.choices(s)
    check('shell picker test needs at least two detected shells', #expected >= 2)

    local win, pane = make_shell_window()
    local shell_cb = with_captured_callback(function()
      shells.picker_action(s)(win, pane)
    end)

    check('shell picker performs exactly one action', #win.performed == 1)
    local first = win.performed[1]
    check('shell picker passes pane to perform_action', first ~= nil and first.pane == pane)
    local is = first and first.action.InputSelector
    check('shell picker builds InputSelector', is ~= nil)
    check('shell picker title and fuzzy', is ~= nil and is.title == '在哪个 shell 打开新标签？' and is.fuzzy == true)
    check('shell picker registers a real callback action', is ~= nil and is.action ~= nil and type(is.action.EmitEvent) == 'string')

    local labels_ok, ids_ok = is ~= nil, is ~= nil
    if is then
      if #is.choices ~= #expected then labels_ok = false end
      for i, e in ipairs(expected) do
        local c = is.choices[i]
        if not c or c.label ~= e.label then labels_ok = false end
        if not c or c.id ~= tostring(i) then ids_ok = false end
      end
    end
    check('shell picker choices labels match shells.choices', labels_ok)
    check('shell picker choices ids are 1-based strings', ids_ok)

    check('shell picker captured callback', type(shell_cb) == 'function')
    if type(shell_cb) == 'function' and is ~= nil and #expected >= 2 then
      local target = expected[2]
      local pane2 = { tag = 'pane-2' }
      win.performed = {}
      local ok, cerr = pcall(shell_cb, win, pane2, '2')
      check('shell callback runs without error', ok, cerr)
      local spawn = win.performed[1] and win.performed[1].action.SpawnCommandInNewTab
      check('shell callback spawns new tab', spawn ~= nil)
      check('shell callback uses the callback pane', win.performed[1] ~= nil and win.performed[1].pane == pane2)
      -- 20240203 的 SpawnCommand 没有 prog 字段，prog 必须是 args[1]
      local argv_ok = spawn ~= nil and spawn.args ~= nil and #spawn.args == 1 + #target.args
        and spawn.args[1] == target.prog
      if argv_ok then
        for i = 1, #target.args do
          if spawn.args[i + 1] ~= target.args[i] then argv_ok = false end
        end
      end
      check('shell callback spawns choice 2 prog as argv[1]', spawn ~= nil and spawn.args ~= nil and spawn.args[1] == target.prog)
      check('shell callback appends choice 2 args', argv_ok)
      check('choice 2 actually carries argv (pins args, not just prog)', #target.args > 0)
    end

    -- 没有可用 shell 时不弹选择器
    local none = {
      shell_menu_order = { 'nope' },
      shells = { nope = { label = 'Nope', prog = 'definitely-not-a-real-program-xyz.exe', args = {} } },
    }
    local nwin, npane = make_shell_window()
    local no_cb = with_captured_callback(function()
      shells.picker_action(none)(nwin, npane)
    end)
    check('shell picker performs nothing when no shell exists', #nwin.performed == 0)
    check('shell picker registers no callback when empty', no_cb == nil)

    -- ---------- colors.picker_action ----------
    local orig_global = wezterm.GLOBAL
    local orig_builtin = colors.builtin_names
    local orig_custom = colors.list_custom

    local ok, err = pcall(function()
      wezterm.GLOBAL = { recent_schemes = { 'Tokyo Night' } }
      colors.builtin_names = function()
        return { 'Nord', 'Zzz', 'Catppuccin Mocha', 'Tokyo Night' }
      end
      colors.list_custom = function()
        return { 'my-theme', 'Nord' }
      end

      local cwin = make_window({ font_size = 13 })
      local cpane = { tag = 'pane-c' }
      local color_cb = with_captured_callback(function()
        colors.picker_action(s)(cwin, cpane)
      end)

      check('color picker performs exactly one action', #cwin.performed == 1)
      local cfirst = cwin.performed[1]
      check('color picker passes pane to perform_action', cfirst ~= nil and cfirst.pane == cpane)
      local cis = cfirst and cfirst.action.InputSelector
      check('color picker builds InputSelector', cis ~= nil)
      check('color picker title and fuzzy', cis ~= nil and cis.title == '切换配色方案（输入可过滤）' and cis.fuzzy == true)
      check('color picker registers a real callback action', cis ~= nil and cis.action ~= nil and type(cis.action.EmitEvent) == 'string')

      -- recent [Tokyo Night] > custom 排序 [Nord, my-theme] > builtin 排序去重
      local want = {
        '[最近] Tokyo Night',
        '[自定义] Nord',
        '[自定义] my-theme',
        'Catppuccin Mocha',
        'Zzz',
      }
      local order_ok = cis ~= nil and #cis.choices == #want
      local ids_ok = cis ~= nil
      if cis then
        for i, label in ipairs(want) do
          local c = cis.choices[i]
          if not c or c.label ~= label then order_ok = false end
          if not c or c.id ~= tostring(i) then ids_ok = false end
        end
      end
      check('color picker labels tagged and in merge order', order_ok)
      check('color picker choices ids are 1-based strings', ids_ok)

      check('color picker captured callback', type(color_cb) == 'function')
      if type(color_cb) == 'function' and cis ~= nil then
        local ok2 = pcall(color_cb, cwin, cpane, '3')
        check('color callback runs without error', ok2)
        check('color callback sets color_scheme from chosen id', cwin.overrides.color_scheme == 'my-theme')
        check('color callback preserves existing overrides', cwin.overrides.font_size == 13)
        check('color callback writes overrides through window', #cwin.set_calls == 1 and cwin.set_calls[1] == cwin.overrides)
        local recents = wezterm.GLOBAL.recent_schemes
        check('color callback pushes chosen name into recents', recents[1] == 'my-theme' and recents[2] == 'Tokyo Night')

        local before = cwin.overrides.color_scheme
        pcall(color_cb, cwin, cpane, '99')
        check('color callback ignores unknown id', cwin.overrides.color_scheme == before and #cwin.set_calls == 1)
      end
    end)

    wezterm.GLOBAL = orig_global
    colors.builtin_names = orig_builtin
    colors.list_custom = orig_custom
    if not ok then error(err) end
  end,
}
