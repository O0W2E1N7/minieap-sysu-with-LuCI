local base = assert(arg[1])
package.path = base .. "/root/usr/lib/lua/?.lua;" .. package.path
local conf = "/etc/minieap-sysu.conf"
local initial = "# existing settings\nusername=old-user\npassword=old$!#='\\pass\nnic=eth0\nif-impl=sockraw\ndaemonize=0\npid-file=/var/run/minieap-sysu.pid\n"
local files, modes, calls, enabled, running = {}, {}, {}, false, false
local failwrite, failrename, failrestart, lockbusy = false, false, false, false
local uptime, unique = 100, 0
local directories = {}
local fs = {}
fs.stat = function(path) return directories[path] and {type = "dir"} or nil end
fs.mkdir = function(path, mode) assert(mode == "rwx------"); directories[path] = true; return true end
fs.chmod = function(path, mode) assert(mode == "rwx------"); return directories[path] end
fs.access = function() return true end
fs.dir = function(path)
    local names = {}
    for name in pairs(files) do
        if name:sub(1, #path + 1) == path .. "/" then names[#names + 1] = name:sub(#path + 2) end
    end
    local i = 0
    return function() i = i + 1; return names[i] end
end
fs.readfile = function(path) return files[path] end
fs.remove = function(path) files[path] = nil; return true end
fs.rename = function(a, b)
    if failrename and b == conf then return nil end
    files[b], modes[b] = files[a], modes[a]; files[a] = nil; return true
end
local nx = {
    getpid = function() return 12345 end,
    open_flags = function(...) return table.concat({...}, ",") end,
    open = function(path, flags, mode)
        assert(flags == "wronly,creat,excl" or flags == "wronly,creat")
        -- Match nixio's octal-string parsing: numeric 384 becomes "384"
        -- and is rejected because 8 is not an octal digit.
        local mode_string = tostring(mode)
        if mode_string == "rw-------" then
            mode = 384
        else
            assert(mode_string:match("^[0-7][0-7][0-7]$") or mode_string:match("^[0-7][0-7][0-7][0-7]$"), "invalid nixio permission string")
            mode = assert(tonumber(mode_string, 8))
        end
        if files[path] and flags:find("excl") then return nil end
        files[path], modes[path] = "", mode
        return {
            write = function(self, s)
                if failwrite then return nil end
                -- Exercise partial-write handling.
                local n = math.min(#s, 11)
                files[path] = files[path] .. s:sub(1, n); return n
            end,
            close = function() return true end,
            lock = function(self, mode) assert(mode == "tlock"); return not lockbusy end,
            sync = function() return true end
        }
    end
}
local init = {enabled = function() return enabled end}
for _, action in ipairs({"enable", "disable", "start", "stop", "restart"}) do
    init[action] = function(name)
        assert(name == "minieap-sysu"); calls[#calls + 1] = action
        if action == "enable" then enabled = true end
        if action == "disable" then enabled = false end
        if action == "restart" and failrestart then return false end
        return true
    end
end
local util = {}
util.ubus = function(object)
    if object == "service" then return {["minieap-sysu"] = {instances = {instance1 = {running = running, pid = 777}}}} end
    return {up = true, ["ipv4-address"] = {{address = "192.0.2.10"}}}
end
util.pcdata = function(s)
    return tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;")
end
package.loaded["nixio.fs"], package.loaded["nixio"] = fs, nx
package.loaded["luci.sys"], package.loaded["luci.util"] = {
    init = init, uptime = function() return uptime end,
    uniqueid = function(n) assert(n == 16); unique = unique + 1; return string.format("%032x", unique) end
}, util
-- In-memory JSON stand-in: preserve value-copy behavior without a native dependency.
local function serialize(t)
    local parts = {}
    for k, v in pairs(t) do
        parts[#parts + 1] = "[" .. string.format("%q", k) .. "]=" ..
            (type(v) == "string" and string.format("%q", v) or tostring(v))
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
package.loaded["luci.jsonc"] = {stringify = serialize, parse = function(s)
    local fn = loadstring("return " .. s); return fn and fn() or nil
end}
package.loaded["luci.xml"] = {pcdata = util.pcdata}
util.pcdata = function() error("Deprecated escape function used") end
local model = require "luci.model.minieap_sysu"
local function reset()
    files = {[conf] = initial, ["/sys/class/net/eth0/carrier"] = "1\n"}
    modes, calls, enabled, failwrite, failrename = {}, {}, false, false, false
    failrestart, lockbusy, uptime = false, false, 100
end
assert(not pcall(nx.open, "/invalid-mode", "wronly,creat,excl", 384))
reset()
local status = model.status()
assert(status.username == "old-user" and status.password == nil)
assert(not status.running and status.carrier and status.wan_up)
running = true; assert(model.status().running); running = false
assert(model.save("old-user", "", true))
assert(files[conf]:find("password=old$!#='\\pass", 1, true))
assert(files[conf]:find("pid-file=/var/run/minieap-sysu.pid", 1, true))
assert(files[conf .. ".web-backup"] == initial)
assert(modes[conf] == 384 and modes[conf .. ".web-backup"] == 384)
assert(#calls == 1 and calls[1] == "enable")
reset(); assert(not model.save("new-user", "", true)); assert(files[conf] == initial and #calls == 0)
reset()
local special = "new$!#='\\<>&\"password"
assert(model.save("new-user", special, false))
assert(files[conf]:find("password=" .. special .. "\n", 1, true))
for _, pair in ipairs({{"user\nmodule=evil", "pass"}, {"user", "pass\nmodule=evil"}, {"user", "pass "}, {"user", string.rep("x", 65)}, {"", "pass"}}) do
    reset(); assert(not model.save(pair[1], pair[2], true)); assert(files[conf] == initial and #calls == 0)
end
reset(); failwrite = true
assert(not model.save("new-user", "new-password", true)); assert(files[conf] == initial)
reset(); failrename = true
assert(not model.save("new-user", "new-password", true)); assert(files[conf] == initial)
reset(); files[conf] = initial:gsub("nic=eth0", "nic=br-lan")
assert(not model.save("new-user", "new-password", true)); assert(#calls == 0)
reset(); assert(not model.action("stop; echo bad")); assert(#calls == 0)
assert(model.action("restart")); assert(calls[1] == "restart")

reset(); assert(model.save_restart("new-user", "new-password", true))
assert(calls[1] == "enable" and calls[2] == "restart" and #calls == 2)
reset(); failwrite = true; assert(not model.save_restart("new-user", "new-password", true)); assert(#calls == 0)
reset(); failrestart = true
local ok, msg = model.save_restart("new-user", "new-password", true)
assert(not ok and msg:find("设置已保存", 1, true) and files[conf]:find("username=new-user", 1, true))

reset()
local id = assert(model.ticket("session-a"))
assert(not model.submit(id, "session-b", "restart")); assert(#calls == 0)
assert(model.submit(id, "session-a", "restart")); assert(#calls == 1)
assert(model.submit(id, "session-a", "restart")); assert(#calls == 1)
assert(model.result(id, "session-a").ok and not model.result(id, "session-b"))
assert(not model.submit("../../bad", "session-a", "restart")); assert(#calls == 1)
local second = assert(model.ticket("session-a")); lockbusy = true
assert(not model.submit(second, "session-a", "restart")); assert(#calls == 1)
lockbusy = false; uptime = 2000
assert(not model.submit(second, "session-a", "restart")); assert(#calls == 1)

local loglines = {}
local original_popen = io.popen
local pipe_closed = false
io.popen = function(command)
    local prefix = "/sbin/logread -e '[Mm]ini[Ee][Aa][Pp]' 2>/dev/null"
    assert(command == prefix or command == prefix .. " | tail -n 200")
    local selected = {}
    for _, line in ipairs(loglines) do
        if line:find("[Mm]ini[Ee][Aa][Pp]") then selected[#selected + 1] = line end
    end
    if command ~= prefix then while #selected > 200 do table.remove(selected, 1) end end
    local i, offset = 0, 1
    local raw = table.concat(selected, "\n") .. (#selected > 0 and "\n" or "")
    pipe_closed = false
    return {
        lines = function() return function() i = i + 1; return selected[i] end end,
        read = function(_, n) if offset > #raw then return nil end; local chunk = raw:sub(offset, offset + n - 1); offset = offset + #chunk; return chunk end,
        close = function() pipe_closed = true; return true end
    }
end
reset()
loglines = {"minieap-sysu: old-user previous-secret DIAG hex=abcdef <script>bad()</script>", "other-service: unrelated"}
local logs = model.logs()
assert(logs == loglines[1] and pipe_closed)
loglines = {}; local empty, notice = model.logs(); assert(empty == "" and notice)
for i = 1, 250 do loglines[i] = "minieap-sysu: line " .. i end
logs = model.logs(); assert(logs:match("^minieap%-sysu: line 51\n") and logs:find("line 250", 1, true))
loglines = {"minieap-sysu:" .. string.rep("中文", 2000)}
assert(model.logs() == loglines[1], "Long lines must remain complete")

-- Test the live session state machine independently of wall-clock/syslog history.
local session = require "luci.model.minieap_session"
local live = {phase = "authenticating"}
local function event(message, now, carrier)
    return session.update(live, message and ("[2026/7/2 12:00:00][I] " .. message), carrier ~= false, now)
end
assert(event("认证成功", 20) and live.since == 20)
assert(not event("认证成功", 30) and live.since == 20)
assert(not event("正在回应用户名请求", 40) and live.since == 20)
assert(event(nil, 50, false) and live.since == nil)
assert(event(nil, 60) and live.phase == "authenticating")
assert(event("认证成功", 70) and live.since == 70)
assert(event("认证失败 1 次", 80) and live.phase == "failed" and live.since == nil)
assert(event("正在查找认证服务器", 90) and live.phase == "authenticating")
assert(event("认证成功", 95))
reset(); running = true
files["/tmp/minieap-sysu-live-777/state.json"] = serialize(live)
assert(model.status().connected_seconds == 5)
uptime = 105; assert(model.status().connected_seconds == 10)
files["/sys/class/net/eth0/carrier"] = "0\n"
assert(model.status().connected_seconds == nil)
reset(); running = false; assert(model.status().connected_seconds == nil)
local method, posted, renders, headers, response_code, response_json = "GET", {}, {}, {}
local download = {}
local dispatcher = {
    context = {authtoken = "test-csrf-token"},
    test_post_security = function() return method == "POST" and posted.token == "test-csrf-token" end,
    build_url = function(...) return "/cgi-bin/luci/" .. table.concat({...}, "/") end
}
package.loaded["luci.dispatcher"] = dispatcher
package.loaded["luci.http"] = {
    formvalue = function(k) return posted[k] end,
    header = function(k, v) headers[k] = v end,
    status = function(code) response_code = code end,
    prepare_content = function() end,
    write = function(chunk) download[#download + 1] = chunk end,
    write_json = function(data) response_json = data end
}
package.loaded["luci.template"] = {render = function(name, context) renders[#renders + 1] = context end}
local ctrl = require "luci.controller.minieap_sysu"
reset(); posted = {action = "stop", token = "test-csrf-token"}
ctrl.action_update(); assert(#calls == 0 and #renders == 0)
method = "POST"; posted.token = "wrong"
ctrl.action_update(); assert(#calls == 0 and #renders == 0)
posted.token = "test-csrf-token"
posted.request_id = assert(model.ticket(posted.token))
ctrl.action_update(); assert(calls[1] == "stop")
assert(response_code == 303 and headers.Location:find("?result=", 1, true))
ctrl.action_update(); assert(#calls == 1)
reset(); posted = {token = "test-csrf-token", action = "save", username = "old-user", password = "", enabled = "1"}
posted.request_id = assert(model.ticket(posted.token))
ctrl.action_update(); assert(calls[1] == "enable" and #calls == 1)
posted = {result = posted.request_id}; ctrl.action_index()
assert(renders[#renders].message)
local viewstate = renders[#renders].state
ctrl.action_index(); assert(renders[#renders].message == nil and renders[#renders].error_message == nil)
assert(model.submit(posted.result, "test-csrf-token", "save", "old-user", "", true))
assert(#calls == 1, "Consuming a notice must not allow action replay")
assert(viewstate.username == "old-user" and viewstate.password == nil)
ctrl.action_status(); assert(response_json.state.password == nil and response_json.state.username == nil)
assert(headers["Cache-Control"] == "no-store" and #calls == 1)

loglines = {}
for i = 1, 250 do loglines[i] = "minieap-sysu: " .. i .. string.rep("x", 1100) end
ctrl.action_logs()
assert(table.concat(download) == table.concat(loglines, "\n") .. "\n")
assert(headers["Content-Disposition"]:find("attachment", 1, true) and pipe_closed)
assert(headers["Cache-Control"] == "no-store")

-- Execute the Lua template fragments and check escaping and password omission.
local f = assert(io.open(base .. "/root/usr/lib/lua/luci/view/minieap_sysu/index.htm"))
local template = f:read("*a"); f:close()
local fragments, pos = {}, 1
while true do
    local a, b, body = template:find("<%%(.-)%%>", pos)
    if not a then fragments[#fragments + 1] = "out(" .. string.format("%q", template:sub(pos)) .. ")"; break end
    fragments[#fragments + 1] = "out(" .. string.format("%q", template:sub(pos, a - 1)) .. ")"
    if body:sub(1, 1) == "=" then fragments[#fragments + 1] = "out(" .. body:sub(2) .. ")"
    elseif body:sub(1, 1) ~= "+" then fragments[#fragments + 1] = body end
    pos = b + 1
end
local output = {}
local fn = assert(loadstring(table.concat(fragments, "\n")))
viewstate.username = '\"><script>alert(1)</script>'
setfenv(fn, setmetatable({
    state = viewstate, token = "test-csrf-token", request_id = id, message = "Saved", error_message = nil,
    logs = '<img src=x onerror="alert(1)">',
    out = function(s) output[#output + 1] = tostring(s or "") end
}, {__index = _G}))
fn()
local html = table.concat(output)
assert(not html:find("<script>alert(1)</script>", 1, true))
assert(html:find("&lt;script&gt;", 1, true))
assert(html:find("&lt;img", 1, true) and not html:find('<img src=x', 1, true))
assert(not html:find("old$!", 1, true))
assert(html:find('name="password"', 1, true) and html:find('value="" placeholder=', 1, true))
io.popen = original_popen
print("PASS: Lua 5.1 model/controller/template; same-account secret retention; changed-account validation; atomic writes; save/restart failures; ticket replay, expiry and session binding; lock contention; POST+CSRF+303 redirect; 200-line display, full raw download, one-time notices; HTML escaping; polling excludes credentials.")
