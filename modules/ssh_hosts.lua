-- SSH 主机清单：只放数据，逻辑在 modules/ssh.lua。
-- 连接走本机 OpenSSH（ssh.exe），所以你的密钥、ssh-agent、ProxyJump 与 ~/.ssh/config 都照旧生效。
--
-- 每条记录只有 name 和 host 是必填，其余可省略：
--   name     菜单里的显示名（唯一，用于「最近使用」记忆）
--   host     主机名或 IP
--   user     登录用户，省略则用当前 Windows 用户名
--   port     端口，省略或 22 时不加 -p
--   identity 私钥路径，填了就自动加 -i
--   group    分组，菜单显示为 [group] 前缀，并支持按组排序/筛选
--   extra    额外参数数组，例如 { '-o', 'ProxyJump=bastion', '-A' }
--   note     备注，只显示在菜单里，不传给 ssh
--
-- 例：
--   { name = 'home-server', host = '10.0.0.5', user = 'hanka', group = 'lan',
--     note = '路由器后面' },
--   { name = 'vps', host = 'example.com', user = 'root', port = 2222,
--     identity = 'C:/Users/Hanka/.ssh/id_ed25519',
--     extra = { '-o', 'StrictHostKeyChecking=accept-new' }, group = 'cloud' },
return {
  -- ssh 可执行文件；想用自定义 ssh 就填绝对路径
  ssh_prog = 'ssh.exe',

  -- 默认排序模式：recent（最近用过的靠前）| name（按名称）| group（按分组）
  sort_default = 'recent',

  -- 主机清单。加主机就往下加一行，Ctrl+Shift+R 重载后即可在菜单里看到。
  hosts = {},
}
