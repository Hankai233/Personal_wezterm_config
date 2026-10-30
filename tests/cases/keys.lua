local wezterm = require 'wezterm'
local keys = require 'modules.keys'

return {
  run = function(check)
    local fake_action_cb = function(fn) return { callback = fn } end
    local built = keys.build(keys.entries, fake_action_cb)

    local want = 0
    for _, e in ipairs(keys.entries) do want = want + 1 + #(e.alts or {}) end
    check('build expands each entry plus its alts', #built == want)

    -- 帮助浮层按 entries 生成：alts 不能混进 entries，否则一个动作会出现两行。
    check('entries stay one row per action', (function()
      for _, e in ipairs(keys.entries) do
        if e.key == '|' or e.key == '_' or e.key == '/' then return false end
      end
      return true
    end)())

    local seen = {}
    for _, e in ipairs(keys.entries) do
      local id = e.mods .. '|' .. e.key
      check('entry has unique binding ' .. id, seen[id] == nil)
      seen[id] = true
      check('entry has label ' .. id, type(e.label) == 'string' and #e.label > 0)
      check('entry has run fn ' .. id, type(e.run) == 'function')
      for _, alt in ipairs(e.alts or {}) do
        local aid = (alt.mods or e.mods) .. '|' .. alt.key
        check('alt binding unique ' .. aid, seen[aid] == nil)
        seen[aid] = true
        check('alt keeps entry mods ' .. aid, (alt.mods or e.mods) == e.mods)
      end
    end

    -- 逐条走 built，顺序必须是 primary -> its alts -> 下一条；alts 必须复用同一
    -- action（同一 EmitEvent），不能重新包一个 callback。
    local idx = 0
    for i, e in ipairs(keys.entries) do
      idx = idx + 1
      local id = string.format('binding[%d] %s', i, e.mods .. '|' .. e.key)
      local b = built[idx] or {}
      local action_cb = type(b.action) == 'table' and b.action.callback or nil
      check(id .. ' action carries that entry run', action_cb == e.run)
      check(id .. ' key copied from entry', b.key == e.key)
      check(id .. ' mods copied from entry', b.mods == e.mods)
      for j, alt in ipairs(e.alts or {}) do
        idx = idx + 1
        local ab = built[idx] or {}
        local aid = string.format('alt[%d.%d] %s', i, j, (alt.mods or e.mods) .. '|' .. alt.key)
        check(aid .. ' shares the primary action', ab.action == b.action)
        check(aid .. ' key copied from alt', ab.key == alt.key)
        check(aid .. ' mods default to entry mods', ab.mods == (alt.mods or e.mods))
      end
    end

    local function has_binding(key, mods)
      for _, b in ipairs(built) do
        if b.key == key and b.mods == mods then return b end
      end
      return nil
    end

    -- 三种 shifted 符号键都要同时注册基础字符与 shifted 字符两种拼写。
    check('split horizontal has | spelling', has_binding('|', 'CTRL|SHIFT') ~= nil)
    check('split vertical has _ spelling', has_binding('_', 'CTRL|SHIFT') ~= nil)
    check('help has / spelling', has_binding('/', 'CTRL|SHIFT') ~= nil)
    check('shifted spellings share the base action', (function()
      local pairs_to_check = {
        { '\\', '|' }, { '-', '_' }, { '?', '/' },
      }
      for _, p in ipairs(pairs_to_check) do
        local base = has_binding(p[1], 'CTRL|SHIFT')
        local alt = has_binding(p[2], 'CTRL|SHIFT')
        if base == nil or alt == nil or base.action ~= alt.action then return false end
      end
      return true
    end)())

    check('entries contain shell menu', (function()
      for _, e in ipairs(keys.entries) do if e.key == 'S' and e.mods == 'CTRL|SHIFT' then return true end end
      return false
    end)())

    check('entries contain help', (function()
      for _, e in ipairs(keys.entries) do if e.key == '?' and e.mods == 'CTRL|SHIFT' then return true end end
      return false
    end)())

    -- 帮助浮层的 run 必须被真正执行：以前整个 suite 不碰它，删掉函数体也能全绿。
    local help = nil
    for _, e in ipairs(keys.entries) do
      if e.key == '?' and e.mods == 'CTRL|SHIFT' then help = e end
    end
    check('help entry has run fn', help ~= nil and type(help.run) == 'function')

    local win = { performed = {} }
    function win:perform_action(action, p) self.performed[#self.performed + 1] = { action = action, pane = p } end
    local pane = { tag = 'help-pane' }
    local ok_help, err_help = pcall(function()
      if help and type(help.run) == 'function' then help.run(win, pane) end
    end)
    check('help run executes without error', ok_help, err_help)
    check('help run performs exactly one action', #win.performed == 1)
    local isel = win.performed[1] and win.performed[1].action.InputSelector
    check('help run opens an InputSelector on the given pane', isel ~= nil and win.performed[1].pane == pane)
    check('help selector title and fuzzy', isel ~= nil and isel.title == 'WezTerm 快捷键帮助' and isel.fuzzy == true)
    check('help selector has one choice per entry', isel ~= nil and #isel.choices == #keys.entries)
    check('help selector labels correspond to entries', (function()
      if not isel or #isel.choices ~= #keys.entries then return false end
      for i, e in ipairs(keys.entries) do
        local c = isel.choices[i]
        if not c or c.id ~= tostring(i) then return false end
        if not c.label:find(e.mods .. '+' .. e.key, 1, true) then return false end
        if not c.label:find(e.label, 1, true) then return false end
      end
      return true
    end)())

    -- id → entry 的分发是独立 helper；用桩 entries 证明“选中哪个就执行哪个”。
    check('dispatch helper is exported', type(keys.dispatch) == 'function')
    if type(keys.dispatch) == 'function' then
      local calls = {}
      local stub = {
        { key = 'X', mods = 'CTRL', label = 'stub one', run = function(w, p) calls[#calls + 1] = { w = w, p = p, which = 1 } end },
        { key = 'Y', mods = 'CTRL', label = 'stub two', run = function(w, p) calls[#calls + 1] = { w = w, p = p, which = 2 } end },
      }
      keys.dispatch(stub, '2', win, pane)
      check('dispatch calls the chosen entry run', #calls == 1 and calls[1].which == 2)
      check('dispatch passes window and pane', calls[1] ~= nil and calls[1].w == win and calls[1].p == pane)
      keys.dispatch(stub, '99', win, pane)
      check('dispatch ignores unknown id', #calls == 1)
      keys.dispatch(stub, '1', win, pane)
      check('dispatch resolves each id by position', #calls == 2 and calls[2].which == 1)
    end

    -- 帮助浮层的 action_callback 必须走 dispatch helper（替换 helper 验证接线）。
    local real_action_cb = wezterm.action_callback
    local real_dispatch = keys.dispatch
    local captured_cb, delegated = nil, {}
    local ok_wire, err_wire = pcall(function()
      wezterm.action_callback = function(fn) captured_cb = fn; return real_action_cb(fn) end
      keys.dispatch = function(entries, id, w, p) delegated[#delegated + 1] = { entries = entries, id = id, w = w, p = p } end
      if help and type(help.run) == 'function' then help.run(win, pane) end
      check('help registers an action callback', type(captured_cb) == 'function')
      if type(captured_cb) == 'function' then captured_cb(win, pane, '7') end
      check('help callback delegates chosen id to dispatch', #delegated == 1 and delegated[1].id == '7'
        and delegated[1].entries == keys.entries and delegated[1].w == win and delegated[1].p == pane)
    end)
    wezterm.action_callback = real_action_cb
    keys.dispatch = real_dispatch
    if not ok_wire then error(err_wire) end

    local mb = keys.mouse_bindings()
    check('mouse_bindings non-empty', type(mb) == 'table' and #mb >= 1)
    check('mouse_bindings right click paste', mb[1].event.Up.button == 'Right')
  end,
}
