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

    local mb = keys.mouse_bindings()
    check('mouse_bindings non-empty', type(mb) == 'table' and #mb >= 1)
    check('mouse_bindings right click paste', mb[1].event.Up.button == 'Right')
  end,
}
