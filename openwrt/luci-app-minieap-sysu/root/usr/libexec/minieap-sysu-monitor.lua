local nx, fs = require "nixio", require "nixio.fs"
local json = require "luci.jsonc"
local session = require "luci.model.minieap_session"
local directory = assert(arg[1])
assert(directory:match("^/tmp/minieap%-sysu%-live%-%d+$"))
local state = {phase = "authenticating"}
local function uptime()
    return assert(tonumber((fs.readfile("/proc/uptime") or ""):match("^[%d.]+")))
end
local function carrier() return (fs.readfile("/sys/class/net/eth0/carrier") or ""):match("^1") ~= nil end
local function save()
    local path = directory .. "/state.json"
    local file = assert(io.open(path .. ".tmp", "w")) -- parent directory and umask are private
    assert(file:write(json.stringify(state))); assert(file:close())
    assert(fs.rename(path .. ".tmp", path))
end
save()
assert(nx.stdin:setblocking(false))
local fds = {{fd = nx.stdin, events = nx.poll_flags("in", "hup")}}
local buffer = ""
local function process(line)
    if session.update(state, line, carrier(), uptime()) then save() end
end
while true do
    if session.update(state, nil, carrier(), uptime()) then save() end
    local ready = nx.poll(fds, 1000)
    if ready and ready > 0 then
        local chunk, code = nx.stdin:read(4096)
        if chunk == "" then break end
        if not chunk and code ~= 11 and code ~= 4 then error("MiniEAP stream read failed") end
        if chunk then
            io.stdout:write(chunk); io.stdout:flush() -- forward unchanged to procd syslog
            buffer = buffer .. chunk
            while true do
                local eol = buffer:find("\n", 1, true)
                if not eol then break end
                process(buffer:sub(1, eol - 1)); buffer = buffer:sub(eol + 1)
            end
            if #buffer > 16384 then buffer = "" end
        end
    end
end
if buffer ~= "" then process(buffer) end
state.phase, state.since = "stopped", nil
save()
