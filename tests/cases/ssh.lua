local wezterm = require 'wezterm'
local ssh = require 'modules.ssh'
local proc = require 'modules.proc'

local function list_equal(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' or #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

local function names(hosts)
  local out = {}
  for i, h in ipairs(hosts) do out[i] = h.name end
  return out
end

-- 生产代码用 wezterm.action_callback 包选择回调；这里把闭包抓出来，动作本身照常返回。
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

local function make_window()
  local w = { performed = {} }
  function w:perform_action(action, p)
    self.performed[#self.performed + 1] = { action = action, pane = p }
  end
  return w
end

local cfg = {
  ssh_prog = 'ssh.exe',
  sort_default = 'recent',
  hosts = {
    { name = 'zeta', host = '10.0.0.9', user = 'root', group = 'lan' },
    { name = 'Alpha', host = 'alpha.example.com', user = 'hanka', port = 2222, group = 'cloud' },
    { name = 'beta', host = 'beta.example.com', note = '测试机' },
    { name = 'gamma', host = 'gamma.example.com', group = 'cloud', identity = 'C:/k/id_ed25519' },
  },
}

return {
  run = function(check)
    -- ---------------- build_argv ----------------
    check('argv minimal host only',
      list_equal(ssh.build_argv(cfg, { name = 'a', host = 'h1' }), { 'ssh.exe', 'h1' }))
    check('argv adds user@ when user set',
      list_equal(ssh.build_argv(cfg, { name = 'a', host = 'h1', user = 'u' }), { 'ssh.exe', 'u@h1' }))
    check('argv adds -p for non-22 port',
      list_equal(ssh.build_argv(cfg, { name = 'a', host = 'h1', user = 'u', port = 2222 }),
        { 'ssh.exe', '-p', '2222', 'u@h1' }))
    check('argv omits -p for port 22',
      list_equal(ssh.build_argv(cfg, { name = 'a', host = 'h1', user = 'u', port = 22 }), { 'ssh.exe', 'u@h1' }))
    check('argv omits -p for string port 22',
      list_equal(ssh.build_argv(cfg, { name = 'a', host = 'h1', port = '22' }), { 'ssh.exe', 'h1' }))
    check('argv adds -i for identity',
      list_equal(ssh.build_argv(cfg, { name = 'a', host = 'h1', identity = 'C:/k/x' }),
        { 'ssh.exe', '-i', 'C:/k/x', 'h1' }))
    check('argv appends extra args before target',
      list_equal(ssh.build_argv(cfg, { name = 'a', host = 'h1', extra = { '-o', 'ProxyJump=b' } }),
        { 'ssh.exe', '-o', 'ProxyJump=b', 'h1' }))
    check('argv order is port then identity then extra then target',
      list_equal(ssh.build_argv(cfg, {
        name = 'a', host = 'h1', user = 'u', port = 2200,
        identity = 'K', extra = { '-A' },
      }), { 'ssh.exe', '-p', '2200', '-i', 'K', '-A', 'u@h1' }))
    check('argv honours custom ssh_prog',
      list_equal(ssh.build_argv({ ssh_prog = 'C:/custom/ssh.exe' }, { name = 'a', host = 'h1' }),
        { 'C:/custom/ssh.exe', 'h1' }))
    local src = { name = 'a', host = 'h1', extra = { '-A' } }
    ssh.build_argv(cfg, src)
    check('argv does not mutate the host record', #src.extra == 1 and src.extra[1] == '-A')

    -- ---------------- label ----------------
    check('label has group/name/target/note',
      ssh.label({ name = 'vps', host = 'ex.com', user = 'root', port = 2222, group = 'cloud', note = 'n' })
        == '[cloud]  vps  root@ex.com:2222  -- n')
    check('label omits brackets without group',
      ssh.label({ name = 'vps', host = 'ex.com', user = 'root' }) == 'vps  root@ex.com')
    check('label omits port 22',
      ssh.label({ name = 'vps', host = 'ex.com', port = 22, user = 'r' }) == 'vps  r@ex.com')

    -- ---------------- sort ----------------
    check('sort by name is case-insensitive',
      list_equal(names(ssh.sort_hosts(cfg.hosts, 'name', {})),
        { 'Alpha', 'beta', 'gamma', 'zeta' }))
    check('sort by group puts grouped first then name, ungrouped last',
      list_equal(names(ssh.sort_hosts(cfg.hosts, 'group', {})),
        { 'Alpha', 'gamma', 'zeta', 'beta' }))
    check('sort by recent puts recently used first then name',
      list_equal(names(ssh.sort_hosts(cfg.hosts, 'recent', { 'zeta', 'beta' })),
        { 'zeta', 'beta', 'Alpha', 'gamma' }))
    check('sort ignores unknown recent names',
      list_equal(names(ssh.sort_hosts(cfg.hosts, 'recent', { 'ghost' })),
        { 'Alpha', 'beta', 'gamma', 'zeta' }))
    check('sort does not mutate the input list',
      (function()
        local input = { cfg.hosts[1], cfg.hosts[2] }
        ssh.sort_hosts(input, 'name', {})
        return input[1].name == 'zeta' and input[2].name == 'Alpha'
      end)())
    check('sort is deterministic for equal names',
      (function()
        local same = { { name = 'x', host = 'h1' }, { name = 'x', host = 'h2' } }
        local out = ssh.sort_hosts(same, 'name', {})
        return out[1].host == 'h1' and out[2].host == 'h2'
      end)())

    -- ---------------- hosts / modes ----------------
    check('valid_hosts drops records without name or host',
      #ssh.valid_hosts({ hosts = { { name = 'ok', host = 'h' }, { name = 'noname' }, { host = 'nohost' }, 'junk' } }) == 1)
    check('valid_hosts tolerates missing cfg', #ssh.valid_hosts(nil) == 0)
    check('normalize_mode rejects junk', ssh.normalize_mode('bogus') == 'recent')
    check('normalize_mode keeps known mode', ssh.normalize_mode('group') == 'group')
    check('next_mode cycles recent -> name', ssh.next_mode('recent') == 'name')
    check('next_mode cycles name -> group', ssh.next_mode('name') == 'group')
    check('next_mode cycles group -> recent', ssh.next_mode('group') == 'recent')

    -- ---------------- GLOBAL-backed state ----------------
    local orig_global = wezterm.GLOBAL
    local ok_state, err_state = pcall(function()
      wezterm.GLOBAL = {}

      check('sort_mode falls back to cfg.sort_default', ssh.sort_mode(cfg) == 'recent')
      check('sort_mode defaults to recent without cfg', ssh.sort_mode(nil) == 'recent')
      ssh.set_sort_mode('group')
      check('set_sort_mode persists', ssh.sort_mode(cfg) == 'group')
      check('set_sort_mode overrides cfg default', ssh.sort_mode({ sort_default = 'name' }) == 'group')
      ssh.set_sort_mode('bogus')
      check('set_sort_mode normalizes junk', ssh.sort_mode(cfg) == 'recent')

      check('recent_names empty initially', #ssh.recent_names() == 0)
      ssh.push_recent('a')
      ssh.push_recent('b')
      ssh.push_recent('a')
      check('push_recent dedupes and keeps newest first', list_equal(ssh.recent_names(), { 'a', 'b' }))
      for i = 1, 20 do ssh.push_recent('h' .. i) end
      check('push_recent caps the list', #ssh.recent_names() == ssh.RECENT_MAX)
      check('push_recent keeps the newest at the front', ssh.recent_names()[1] == 'h20')
      check('push_recent ignores junk', (function()
        local before = #ssh.recent_names()
        ssh.push_recent(nil)
        ssh.push_recent('')
        return #ssh.recent_names() == before
      end)())
      local snapshot = ssh.recent_names()
      snapshot[1] = 'mutated'
      check('recent_names returns a copy', ssh.recent_names()[1] == 'h20')
    end)
    wezterm.GLOBAL = orig_global
    if not ok_state then error(err_state) end

    -- ---------------- choices ----------------
    local ok_choices, err_choices = pcall(function()
      local choices, ordered = ssh.choices(cfg, 'name', {})
      check('choices count matches valid hosts', #choices == 4 and #ordered == 4)
      check('choices ids are 1-based strings', choices[1].id == '1' and choices[4].id == '4')
      check('choices follow the requested sort', ordered[1].name == 'Alpha' and ordered[4].name == 'zeta')
      check('choices labels use label()', choices[1].label == ssh.label(ordered[1]))
      check('choices carry the group prefix for filtering', choices[1].label:find('[cloud]', 1, true) ~= nil)
    end)
    if not ok_choices then error(err_choices) end

    -- ---------------- picker ----------------
    local orig_exists = proc.exists
    local orig_warn = wezterm.log_warn
    local warnings = {}
    wezterm.log_warn = function(msg) warnings[#warnings + 1] = msg end
    local orig_global2 = wezterm.GLOBAL

    local ok_picker, err_picker = pcall(function()
      wezterm.GLOBAL = {}
      proc.exists = function() return true end

      local win = make_window()
      local pane = { tag = 'ssh-pane' }
      local cb = with_captured_callback(function()
        ssh.picker_action(cfg)(win, pane)
      end)

      check('ssh picker performs exactly one action', #win.performed == 1)
      local first = win.performed[1]
      check('ssh picker passes the pane', first ~= nil and first.pane == pane)
      local isel = first and first.action.InputSelector
      check('ssh picker builds an InputSelector', isel ~= nil)
      check('ssh picker enables fuzzy filtering', isel ~= nil and isel.fuzzy == true)
      check('ssh picker title names the sort mode',
        isel ~= nil and isel.title:find('SSH 主机', 1, true) ~= nil and isel.title:find('recent', 1, true) ~= nil)
      check('ssh picker lists every host', isel ~= nil and #isel.choices == 4)
      check('ssh picker registers a real callback action',
        isel ~= nil and isel.action ~= nil and type(isel.action.EmitEvent) == 'string')
      check('ssh picker captures the callback', type(cb) == 'function')

      if type(cb) == 'function' then
        -- recent 模式且没有最近记录时按名称排序，id 1 是 Alpha（带 2222 端口）
        local win2 = make_window()
        local pane2 = { tag = 'ssh-pane-2' }
        local ok_cb, err_cb = pcall(cb, win2, pane2, '1')
        check('ssh callback runs without error', ok_cb, err_cb)
        local spawn = win2.performed[1] and win2.performed[1].action.SpawnCommandInNewTab
        check('ssh callback spawns a new tab', spawn ~= nil)
        check('ssh callback uses the callback pane', win2.performed[1] ~= nil and win2.performed[1].pane == pane2)
        check('ssh callback pins the exact argv',
          spawn ~= nil and list_equal(spawn.args, { 'ssh.exe', '-p', '2222', 'hanka@alpha.example.com' }))
        check('ssh callback records the host in recents', ssh.recent_names()[1] == 'Alpha')

        local win3 = make_window()
        pcall(cb, win3, pane2, '99')
        check('ssh callback ignores an unknown id', #win3.performed == 0)
      end
    end)
    if not ok_picker then error(err_picker) end

    -- 主机清单为空 / 找不到 ssh 时不弹空壳菜单
    local ok_empty, err_empty = pcall(function()
      warnings = {}
      local win = make_window()
      ssh.picker_action({ ssh_prog = 'ssh.exe', hosts = {} })(win, {})
      check('ssh picker performs nothing with an empty host list', #win.performed == 0)
      check('ssh picker warns once on an empty host list', #warnings == 1)
      check('ssh picker warning points at ssh_hosts.lua',
        warnings[1] ~= nil and warnings[1]:find('ssh_hosts.lua', 1, true) ~= nil)

      warnings = {}
      proc.exists = function() return false end
      local win2 = make_window()
      ssh.picker_action(cfg)(win2, {})
      check('ssh picker performs nothing without ssh', #win2.performed == 0)
      check('ssh picker warns when ssh is missing', #warnings == 1)
      check('ssh picker warning names the program',
        warnings[1] ~= nil and warnings[1]:find('ssh.exe', 1, true) ~= nil)
    end)
    proc.exists = orig_exists
    wezterm.GLOBAL = orig_global2
    if not ok_empty then error(err_empty) end

    -- ---------------- sort cycle ----------------
    local orig_toast = wezterm.toast_notification
    local orig_global3 = wezterm.GLOBAL
    local toasts = {}
    local ok_cycle, err_cycle = pcall(function()
      wezterm.GLOBAL = {}
      wezterm.toast_notification = function(t)
        toasts[#toasts + 1] = t
        return true
      end

      local win = make_window()
      ssh.cycle_sort_action(cfg)(win, {})
      check('cycle does not touch the pane', #win.performed == 0)
      check('cycle persists the next mode', ssh.sort_mode(cfg) == 'name')
      check('cycle announces the new mode', #toasts == 1 and toasts[1].body:find('name', 1, true) ~= nil)

      ssh.cycle_sort_action(cfg)(win, {})
      ssh.cycle_sort_action(cfg)(win, {})
      check('cycle wraps back to recent', ssh.sort_mode(cfg) == 'recent')
      check('cycle toasted three times', #toasts == 3)
    end)
    wezterm.toast_notification = orig_toast
    wezterm.GLOBAL = orig_global3
    wezterm.log_warn = orig_warn
    if not ok_cycle then error(err_cycle) end
  end,
}
