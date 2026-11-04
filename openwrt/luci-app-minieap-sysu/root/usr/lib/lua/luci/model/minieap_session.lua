-- State transitions for the live MiniEAP output stream, not historical syslog.
local M = {}
function M.update(state, line, carrier, now)
    local phase, since = state.phase, state.since
    local message = line and line:gsub("\27%[[%d;]*m", ""):match("^%[[^%]]+%]%[[IWE]%]%s*(.-)%s*$")
    if not carrier then phase, since = "disconnected", nil
    elseif message == "认证成功" then
        if phase ~= "connected" then phase, since = "connected", now end
    elseif message and message:match("^认证掉线") then phase, since = "offline", nil
    elseif message and message:match("^认证失败") then
        phase, since = "failed", nil
    elseif message == "MiniEAP 已退出" then phase, since = "stopped", nil
    elseif message == "正在查找认证服务器" then phase, since = "authenticating", nil
    elseif phase == "disconnected" then phase, since = "authenticating", nil end
    local changed = phase ~= state.phase or since ~= state.since
    state.phase, state.since = phase, since
    return changed
end
return M
