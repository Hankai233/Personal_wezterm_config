# WezTerm 配置

零第三方依赖，按功能拆成模块。改行为先看 `modules/settings.lua`，那里是唯一常量区；其余模块只读它。

## 目录结构

| 路径 | 作用 |
|---|---|
| `wezterm.lua` | 真正的入口：把配置目录加进 `package.path`，再 `require 'init'` |
| `init.lua` | 组装 `config`：字体 → 配色 → 默认 shell → 快捷键 |
| `modules/settings.lua` | 唯一常量区：字体、字号、shell 列表、默认配色、scrollback、窗口内边距 |
| `modules/appearance.lua` | 应用字体 / 行高 / `harfbuzz_features` |
| `modules/shells.lua` | 默认 shell 探测与回退、`Ctrl+Shift+S` 菜单 |
| `modules/colors.lua` | 初始配色与 `colors/` 目录注册 |
| `modules/keys.lua` | 自定义键、鼠标绑定、`Ctrl+Shift+?` 帮助浮层 |
| `colors/example.toml` | 自定义配色模板（带注释） |
| `tests/` | `harness.lua` + `cases/*.lua` + `verify.ps1` |

## 常用操作

下表是配置里自定义的绑定（`modules/keys.lua`）。其余（如 `Ctrl+=` / `Ctrl+-` / `Ctrl+0` 字号缩放、`Ctrl+Shift+R` 重载配置）沿用 WezTerm 默认。

| 操作 | 快捷键 |
|---|---|
| 新建标签页 | `Ctrl+Shift+T` |
| 新建标签页并选择 shell | `Ctrl+Shift+S` |
| 全选（copy mode 组合） | `Ctrl+Shift+A` |
| 关闭分屏（需确认） | `Ctrl+Shift+Q` |
| 左右分屏 | `Ctrl+Shift+\` |
| 上下分屏 | `Ctrl+Shift+-` |
| pane 焦点（左 / 右 / 上 / 下） | `Alt+←` / `Alt+→` / `Alt+↑` / `Alt+↓` |
| pane 模糊跳转 | `Ctrl+Shift+J` |
| QuickSelect（URL / IP / 路径） | `Ctrl+Shift+Space` |
| 快捷键帮助（选中即执行） | `Ctrl+Shift+?` |
| 粘贴 | 鼠标右键单击 |

`show-keys` 会把大写 ASCII 字母键显示成 `CTRL S`、`CTRL A` 这类省略 SHIFT 的形式（只有大写字母会折叠 SHIFT），实际匹配的仍是 `Ctrl+Shift+S` / `Ctrl+Shift+A`；`?` 这类标点保留 SHIFT，显示成 `SHIFT | CTRL ?`。另外 `\` / `-` / `?` 还同时注册了 shifted 字符（`|` / `_` / `/`）的拼写，Ctrl+Shift 下无论事件按哪种字符投递都能命中。

`Ctrl+Shift+A` 的全选不是原生 `SelectAll`（WezTerm 20240203 没有这个动作），而是 `ActivateCopyMode` + 跳到回滚顶部 + `Cell` 选区 + 跳到回滚底部的 `Multiple` 组合；自动化测试只断言这个动作被正确构造，真实按键后的选区效果需要在窗口里手动冒烟一次。

加自定义键：在 `modules/keys.lua` 的 `M.entries` 里加一条 `{ key, mods, label, run }`，`Ctrl+Shift+?` 帮助浮层会自动收录并执行它。

## 外观

- 字体 `Maple Mono NF CN`，11pt，行高 1.0，`harfbuzz_features = { 'calt', 'liga' }`。配置只显式指定这一个家族（自带 CJK 与 Nerd 图标）；缺字由 WezTerm 内置回退（`JetBrains Mono` / `Noto Color Emoji` / `Symbols Nerd Font Mono` 等）补齐，`ls-fonts` 里能看到。
- 窗口内边距 4、scrollback 10000 行由 `modules/settings.lua` 驱动，并在 `modules/appearance.lua` 里落到 `config`。`copy_on_select` 不是 WezTerm 20240203 的配置项：在返回 `config` 表的配置里写入它会因字段无效导致整份配置被丢弃（不是静默忽略），选中即复制是该版本默认的鼠标行为，所以不再暴露这个死开关。

## 自定义配色

- 换配色不再有选择器：改 `modules/settings.lua` 的 `default_scheme`，再按 `Ctrl+Shift+R` 重载（或重启）。默认是内置方案 `Catppuccin Mocha`。
- `default_scheme` 既可以是内置方案名，也可以是 `colors/` 下某个文件的**文件名（不含 `.toml`）**；按文件名找到文件后，实际生效的仍是该文件 `[metadata] name` 里的真实方案名。两者都匹配不到时告警并落回 WezTerm 默认配色。
- `colors/*.toml` 由 WezTerm 原生加载：TOML 里有 `[metadata] name` 时用它作方案名，没有时才用文件名（去掉 `.toml`）。`colors/example.toml` 没有 metadata，所以填 `default_scheme = 'example'` 就能生效。
- `modules/colors.lua` 在配置加载时把 `<配置目录>/colors` 写进 `config.color_scheme_dirs`；即使通过 `--config-file` 从默认配置目录之外启动，这些自定义方案也会注册进 WezTerm（原生 TOML 加载，不靠本仓库扫描文件）。
- 与内置方案同名时会覆盖内置方案（这是 WezTerm 文档行为，本仓库未在命令行里单独实测）。
- 内置方案已有 1000+ 套，想换内置配色直接把方案名填进 `default_scheme` 即可。

## 自定义 shell

都改 `modules/settings.lua`：

| 字段 | 含义 |
|---|---|
| `default_shell` | 首选 shell 的 key（默认 `pwsh`） |
| `shells_order` | 首选不可用时的回退顺序：`pwsh` → `powershell51` → `cmd` |
| `shell_menu_order` | `Ctrl+Shift+S` 菜单的显示顺序：`pwsh` → `powershell51` → `cmd` → `gitbash` → `wsl` |
| `shells` | 每个 shell 的 `label` / `prog` / `args` |

- 存在性探测是同步的 `io.open`（换成异步的 `wezterm.glob` 会让配置加载报 yield across C-call boundary），`prog` 可以是 `PATH` 里的文件名或绝对路径。
- 菜单在按键时才枚举，只列出 `prog` 存在的项；WSL 项是 `wsl.exe -d Debian`（不带 `--cd`）。
- 全部候选都探测不到时，回退到 `shells_order` 里最后定义的 shell，并写一条 `log_warn`。

## 自检

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\verify.ps1
```

- 用真实 `wezterm` 二进制跑（优先 `PATH` 里的 `wezterm`，否则 `C:\Program Files\WezTerm\wezterm.exe`）。
- 先加载 `tests/harness.lua` 跑 `tests/cases/*.lua`（settings / appearance / shells / colors / keys / pickers），输出 `SUMMARY pass=… fail=…`；有 `FAIL` 即退出码 1。
- 再对真实入口 `wezterm.lua` 做两道门禁：`ls-fonts` 必须打出 `Primary font:` 且没有 `ERROR` / `runtime error`（证明配置真的加载成功，而不是静默回退默认值）；`show-keys` 必须含 `ALT LeftArrow`、`SHIFT | CTRL ?`、`CTRL A`、`CTRL Q` 的 `EmitEvent`（证明自定义键表生效；动作构造失败会静默回退默认键表，这四条会同时消失）。
- 全绿输出 `ALL PASS`（当前 217 条断言）。

## 部署

把本仓库内容复制到 WezTerm 配置目录（排除 `.git`、`.superpowers`、`tests/last-run.txt`）：

```powershell
robocopy E:\Documents\deepseek-harness\default-workspace\wezterm-config C:\Users\Hanka\.config\wezterm /MIR /XD .git .superpowers /XF last-run.txt /R:0 /W:0
```

`/MIR` 是镜像模式：除了把源目录复制过去，还会**删除目标目录里源目录已经没有的文件**（例如已删掉的旧模块或配色），避免残留文件继续生效；`/XD` 排除的 `.git`、`.superpowers` 不受影响。`/R:0 /W:0` 关闭 robocopy 默认的 30 秒重试（默认最多一百万次），脚本化调用会快速失败而不是卡住。复制后在 WezTerm 里按 `Ctrl+Shift+R` 重载或重启。

部署后可用真实二进制确认（`--config-file` 明确指向部署路径，不受正在运行的实例影响）：

```powershell
& "C:\Program Files\WezTerm\wezterm.exe" --config-file "C:\Users\Hanka\.config\wezterm\wezterm.lua" ls-fonts
& "C:\Program Files\WezTerm\wezterm.exe" --config-file "C:\Users\Hanka\.config\wezterm\wezterm.lua" show-keys
```
