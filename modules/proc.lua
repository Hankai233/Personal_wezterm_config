local M = {}

-- 同步存在性检查：wezterm.glob 是异步的（内部 coroutine.yield），在 require 加载的
-- 配置块里调用会报 "attempt to yield across a C-call boundary" 并让整个配置回退默认值。
-- io.open 只打开句柄、不读内容，任何上下文都安全。
-- errno 22 (EINVAL) 是 Windows App Execution Alias 的表现（如 WindowsApps\pwsh.exe 这类
-- 0 字节 reparse point，CreateProcess 能正常拉起）；目录会返回 13 (EACCES)，不算可执行项。
local EINVAL = 22

local function file_exists(path)
  local f, _, errno = io.open(path, 'r')
  if f then
    f:close()
    return true
  end
  return errno == EINVAL
end

-- prog 可能是绝对路径，也可能只是 PATH 中的文件名
function M.exists(prog)
  if type(prog) ~= 'string' or prog == '' then return false end
  if prog:match('^%a:[/\\]') or prog:match('^[/\\]') then
    return file_exists(prog)
  end
  local path = os.getenv('PATH') or ''
  for dir in path:gmatch('[^;]+') do
    if file_exists(dir .. '\\' .. prog) then return true end
  end
  return false
end

return M
