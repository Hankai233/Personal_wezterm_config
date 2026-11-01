local wezterm = require 'wezterm'
local shells = require 'modules.shells'

-- 假 window：记录 perform_action 的动作与 pane。
local function make_window()
  local w = { performed = {} }
  function w:perform_action(action, p)
    self.performed[#self.performed + 1] = { action = action, pane = p }
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
  end,
}
