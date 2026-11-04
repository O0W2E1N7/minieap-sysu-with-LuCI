local base = assert(arg[1])
package.path = base .. "/root/usr/lib/lua/?.lua;" .. package.path
local files, saved, forwarded = {}, {}, {}
local clock, carrier, step = 10, true, 0
local chunks = {"[2026/7/2 12:00:00][I] 认证成", "功\n", "[2026/7/2 12:00:10][I] 认证成功\n",
    false, "[2026/7/2 12:00:30][I] 正在回应用户名请求\n", "[2026/7/2 12:00:31][I] 认证成功\n", ""}
package.loaded['nixio'] = {
    stdin = {setblocking = function(_, value) assert(value == false); return true end,
        read = function() return chunks[step] end},
    poll_flags = function() return 1 end,
    poll = function(_, timeout)
        assert(timeout == 1000); step = step + 1; clock = clock + 1
        carrier = step ~= 4
        return chunks[step] == false and 0 or 1
    end
}
package.loaded['nixio.fs'] = {
    readfile = function(path)
        if path == '/proc/uptime' then return tostring(clock) .. ' 0' end
        if path == '/sys/class/net/eth0/carrier' then return carrier and '1' or '0' end
    end,
    rename = function(a, b) files[b] = files[a]; return true end
}
package.loaded['luci.jsonc'] = {stringify = function(state)
    saved[#saved + 1] = {phase = state.phase, since = state.since}
    return state.phase
end}
local oldopen, oldstdout = io.open, io.stdout
io.open = function(path) return {write = function(_, data) files[path] = data; return true end, close = function() return true end} end
io.stdout = {write = function(_, chunk) forwarded[#forwarded + 1] = chunk end, flush = function() end}
arg[1] = '/tmp/minieap-sysu-live-123'
dofile(base .. '/root/usr/libexec/minieap-sysu-monitor.lua')
io.open, io.stdout = oldopen, oldstdout
assert(saved[1].phase == 'authenticating')
assert(saved[2].phase == 'connected' and saved[2].since == 12)
assert(saved[3].phase == 'disconnected') -- repeated success did not reset since
assert(saved[4].phase == 'authenticating')
assert(saved[5].phase == 'connected' and saved[5].since == 16)
assert(saved[6].phase == 'stopped' and #saved == 6)
assert(table.concat(forwarded):find('认证成功', 1, true))
print('PASS: monitor partial lines, repeated success, carrier loss, reconnection, EOF and unchanged log forwarding.')
