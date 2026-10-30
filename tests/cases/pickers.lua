local wezterm = require 'wezterm'
local shells = require 'modules.shells'
local colors = require 'modules.colors'
local s = require 'modules.settings'

-- 假 window：记录 perform_action 的动作与 pane，并模拟 config overrides 读写。
-- 真 WezTerm 的 get_config_overrides 每次返回新表（nil 时返回 nil），不会把内部
-- 状态交出去；这里同样返回副本，测试只能断言字段，不能断言与 fake 内部是同一张表。
local function make_window(overrides)
  local w = { performed = {}, set_calls = {}, overrides = overrides }
  function w:perform_action(action, p)
    self.performed[#self.performed + 1] = { action = action, pane = p }
  end
  function w:get_config_overrides()
    if self.overrides == nil then return nil end
    local copy = {}
    for k, v in pairs(self.overrides) do copy[k] = v end
    return copy
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

local function make_window_and_pane()
  return make_window(), { tag = 'pane-1' }
end

local function argv_equal(actual, expected)
  if type(actual) ~= 'table' or #actual ~= #expected then return false end
  for i = 1, #expected do
    if actual[i] ~= expected[i] then return false end
  end
  return true
end

local function list_equal(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' or #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

return {
  run = function(check)
    -- ---------- shells.picker_action ----------
    -- 合成 settings + 桩 shells.exists：断言与宿主实际装了哪些 shell 无关。
    local fake = {
      shell_menu_order = { 'a', 'b' },
      shells = {
        a = { label = 'A', prog = 'pwsh.exe', args = { '-NoLogo' } },
        b = { label = 'B', prog = 'cmd.exe', args = {} },
      },
    }

    local orig_exists = shells.exists
    shells.exists = function() return true end

    local ok_shell, err_shell = pcall(function()
      local win, pane = make_window_and_pane()
      local shell_cb = with_captured_callback(function()
        shells.picker_action(fake)(win, pane)
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
        if #is.choices ~= 2 then labels_ok = false end
        local want = { { id = '1', label = 'A' }, { id = '2', label = 'B' } }
        for i, e in ipairs(want) do
          local c = is.choices[i]
          if not c or c.label ~= e.label then labels_ok = false end
          if not c or c.id ~= e.id then ids_ok = false end
        end
      end
      check('shell picker choices labels match synthetic settings', labels_ok)
      check('shell picker choices ids are 1-based strings', ids_ok)

      check('shell picker captured callback', type(shell_cb) == 'function')
      if type(shell_cb) == 'function' then
        -- 两个选择都断言完整 argv：空 args 的 shape 也必须只剩 argv[1]。
        local cases = {
          { id = '1', argv = { 'pwsh.exe', '-NoLogo' } },
          { id = '2', argv = { 'cmd.exe' } },
        }
        for _, case in ipairs(cases) do
          local pane2 = { tag = 'pane-' .. case.id }
          win.performed = {}
          local ok, cerr = pcall(shell_cb, win, pane2, case.id)
          check('shell callback ' .. case.id .. ' runs without error', ok, cerr)
          local spawn = win.performed[1] and win.performed[1].action.SpawnCommandInNewTab
          check('shell callback ' .. case.id .. ' spawns new tab', spawn ~= nil)
          check('shell callback ' .. case.id .. ' uses the callback pane', win.performed[1] ~= nil and win.performed[1].pane == pane2)
          check('shell callback ' .. case.id .. ' pins exact SpawnCommandInNewTab argv',
            spawn ~= nil and argv_equal(spawn.args, case.argv))
        end
      end
    end)
    shells.exists = orig_exists
    if not ok_shell then error(err_shell) end

    -- 没有可用 shell 时不弹选择器（回到真实 exists；这个 prog 一定不存在）
    local none = {
      shell_menu_order = { 'nope' },
      shells = { nope = { label = 'Nope', prog = 'definitely-not-a-real-program-xyz.exe', args = {} } },
    }
    local nwin, npane = make_window_and_pane()
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
        -- 真 API 返回副本，只能断言写回 window 的那张表的字段，不能断言同一性
        local written = cwin.set_calls[1]
        check('color callback writes color_scheme from chosen id', written ~= nil and written.color_scheme == 'my-theme')
        check('color callback preserves existing overrides', written ~= nil and written.font_size == 13)
        check('color callback writes overrides through window', #cwin.set_calls == 1)
        local recents = wezterm.GLOBAL.recent_schemes
        check('color callback pushes chosen name into recents', recents[1] == 'my-theme' and recents[2] == 'Tokyo Night')

        -- nil overrides：真 API 可能返回 nil，回调必须自行新建表
        local nwin = make_window(nil)
        local nok = pcall(color_cb, nwin, cpane, '4')
        check('color callback handles nil overrides', nok and #nwin.set_calls == 1)
        check('color callback writes picked scheme when overrides are nil',
          nwin.set_calls[1] ~= nil and nwin.set_calls[1].color_scheme == 'Catppuccin Mocha')

        -- unknown id：不写 overrides、不动 recents
        local before = cwin.set_calls[1].color_scheme
        local recents_before = {}
        for i, v in ipairs(wezterm.GLOBAL.recent_schemes) do recents_before[i] = v end
        pcall(color_cb, cwin, cpane, '99')
        check('color callback ignores unknown id', cwin.set_calls[1].color_scheme == before and #cwin.set_calls == 1)
        check('color callback leaves recents unchanged for unknown id',
          list_equal(wezterm.GLOBAL.recent_schemes, recents_before))
      end
    end)

    wezterm.GLOBAL = orig_global
    colors.builtin_names = orig_builtin
    colors.list_custom = orig_custom
    if not ok then error(err) end

    -- ---------- colors.picker_action: 空菜单 ----------
    local orig_global2 = wezterm.GLOBAL
    local orig_custom2 = colors.list_custom
    local orig_get_builtin = wezterm.color.get_builtin_schemes
    local orig_warn = wezterm.log_warn
    local warnings = {}
    wezterm.log_warn = function(msg) warnings[#warnings + 1] = msg end

    local ok_empty, err_empty = pcall(function()
      wezterm.GLOBAL = {}
      -- builtin 不可用：走 colors.builtin_names 里 pcall 的兜底路径
      wezterm.color.get_builtin_schemes = function() return {} end
      colors.list_custom = function() return {} end

      local ewin, epane = make_window_and_pane()
      colors.picker_action(s)(ewin, epane)

      check('color picker performs nothing when no scheme exists', #ewin.performed == 0)
      check('color picker warns exactly once when empty', #warnings == 1)
      check('color picker warning names the empty scheme list',
        warnings[1] ~= nil and warnings[1]:find('没有可用的配色方案', 1, true) ~= nil)
    end)

    wezterm.GLOBAL = orig_global2
    colors.list_custom = orig_custom2
    wezterm.color.get_builtin_schemes = orig_get_builtin
    wezterm.log_warn = orig_warn
    if not ok_empty then error(err_empty) end
  end,
}
