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

    for _, b in ipairs(built) do
      check('binding action wrapped', type(b.action) == 'table' and type(b.action.callback) == 'function')
      check('binding has key', type(b.key) == 'string' and #b.key > 0)
      check('binding has mods', type(b.mods) == 'string' and #b.mods > 0)
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
