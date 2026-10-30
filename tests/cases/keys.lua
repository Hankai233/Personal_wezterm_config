local keys = require 'modules.keys'

return {
  run = function(check)
    local fake_action_cb = function(fn) return { callback = fn } end
    local built = keys.build(keys.entries, fake_action_cb)

    check('build returns one binding per entry', #built == #keys.entries)

    local seen = {}
    for _, e in ipairs(keys.entries) do
      local id = e.mods .. '|' .. e.key
      check('entry has unique binding ' .. id, seen[id] == nil)
      seen[id] = true
      check('entry has label ' .. id, type(e.label) == 'string' and #e.label > 0)
      check('entry has run fn ' .. id, type(e.run) == 'function')
    end

    -- Per-index identity, not just shape: a build that wired every binding to
    -- entries[1].run (or shifted the mapping by one) must fail here. Names carry
    -- the index and the entry id so no two checks collide in the summary.
    for i, e in ipairs(keys.entries) do
      local id = string.format('binding[%d] %s', i, e.mods .. '|' .. e.key)
      local b = built[i] or {}
      local action_cb = type(b.action) == 'table' and b.action.callback or nil
      check(id .. ' action carries that entry run', action_cb == e.run)
      check(id .. ' key copied from entry', b.key == e.key)
      check(id .. ' mods copied from entry', b.mods == e.mods)
    end

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
