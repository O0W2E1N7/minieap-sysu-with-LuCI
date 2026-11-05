-- Local LuCI adapter for the existing minieap-sysu service. MIT licensed.
local fs = require "nixio.fs"
local nx = require "nixio"
local sys = require "luci.sys"
local util = require "luci.util"
local json = require "luci.jsonc"
local M = {}
local conf = "/etc/minieap-sysu.conf"
local service = "minieap-sysu"

local function read_config()
    local raw = fs.readfile(conf)
    if not raw or #raw > 16384 then return nil, "无法读取现有认证配置。" end
    local cfg = {}
    for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
        local key, value = line:match("^%s*([%w_-]+)=(.*)$")
        if key and cfg[key] == nil then cfg[key] = value:gsub("%s+$", "") end
    end
    return cfg, raw
end

-- Interface helpers. All of them tolerate a missing /sys or a stubbed test FS.
local IFNAME_PATTERN = "^[%w_.:%-]+$"
local function valid_ifname(name)
    return type(name) == "string" and #name >= 1 and #name <= 15 and name:match(IFNAME_PATTERN) ~= nil
end

local function stat_ok(path)
    if not fs.stat then return false end
    local ok, value = pcall(fs.stat, path)
    return ok and value ~= nil
end

local function read_trim(path)
    if not fs.readfile then return nil end
    local ok, value = pcall(fs.readfile, path)
    if not ok or not value then return nil end
    return (value:gsub("%s+$", ""))
end

-- Only used to label usable candidates, so a missing `ip` binary is harmless.
local function iface_ipv4(name)
    if not sys.exec then return nil end
    local ok, out = pcall(sys.exec, "ip -4 -o addr show dev " .. name .. " 2>/dev/null")
    if not ok or type(out) ~= "string" then return nil end
    return out:match("inet%s+([%d%.]+/%d+)")
end

local function describe_interface(name)
    local base = "/sys/class/net/" .. name
    local carrier_raw = read_trim(base .. "/carrier")
    local info = {
        name = name,
        operstate = read_trim(base .. "/operstate") or "",
        mac = read_trim(base .. "/address") or "",
        carrier = carrier_raw == "1",
        carrier_known = carrier_raw ~= nil,
        physical = stat_ok(base .. "/device"),
        bridge = stat_ok(base .. "/bridge"),
        slave = stat_ok(base .. "/master"),
        wireless = stat_ok(base .. "/phy80211")
    }
    -- A raw-socket EAPOL client only makes sense on a standalone physical port:
    -- a bridge member is forwarded by the bridge, wireless ignores it entirely.
    info.usable = info.physical and not info.bridge and not info.slave and not info.wireless
    if info.bridge then info.kind = "网桥"
    elseif info.wireless then info.kind = "无线"
    elseif info.slave then info.kind = "桥成员"
    elseif info.physical then info.kind = "物理"
    else info.kind = "虚拟" end
    if info.usable then info.ipv4 = iface_ipv4(name) end
    return info
end

function M.interfaces()
    local list, seen = {}, {}
    if fs.dir then
        local ok, iter = pcall(fs.dir, "/sys/class/net")
        if ok and iter then
            for name in iter do
                if valid_ifname(name) and name ~= "lo" and not seen[name] then
                    seen[name] = true
                    list[#list + 1] = describe_interface(name)
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.usable ~= b.usable then return a.usable end
        if a.carrier ~= b.carrier then return a.carrier end
        return a.name < b.name
    end)
    return list
end

local function atomic_write(path, data)
    local tmp = path .. ".web-" .. nx.getpid()
    -- Symbolic owner-only permissions avoid numeric mode interpretation.
    local file = nx.open(tmp, nx.open_flags("wronly", "creat", "excl"), "rw-------")
    if not file then return nil end
    local offset = 1
    while offset <= #data do
        local n = file:write(data:sub(offset))
        if not n or n <= 0 then
            file:close(); fs.remove(tmp); return nil
        end
        offset = offset + n
    end
    local synced = file:sync()
    file:close()
    if not synced or not fs.rename(tmp, path) then fs.remove(tmp); return nil end
    return true
end

function M.status()
    local cfg, err = read_config()
    local configured_nic = cfg and cfg.nic or ""
    if not valid_ifname(configured_nic) then configured_nic = "" end
    local active_nic = configured_nic ~= "" and configured_nic or "eth0"
    -- Never pass the stored password into the template or a response.
    local result = {
        username = cfg and cfg.username or "",
        nic = active_nic,
        nic_configured = configured_nic,
        nic_default = configured_nic == "",
        nic_missing = configured_nic ~= "" and not stat_ok("/sys/class/net/" .. configured_nic),
        configured = cfg and (cfg.username or "") ~= "" and (cfg.password or "") ~= "" or false,
        error = not cfg and err or nil,
        enabled = sys.init.enabled(service),
        running = false,
        carrier = read_trim("/sys/class/net/" .. active_nic .. "/carrier") == "1",
        wan_up = false,
        address = ""
    }
    local ok, state = pcall(util.ubus, "service", "list", {name = service})
    if ok and state and state[service] then
        for _, instance in pairs(state[service].instances or {}) do
            if instance.running then result.running = true; result.pid = tonumber(instance.pid) end
        end
    end
    local wok, wan = pcall(util.ubus, "network.interface.wan", "status", {})
    if wok and wan then
        result.wan_up = wan.up == true
        local addresses = wan["ipv4-address"] or {}
        result.address = addresses[1] and addresses[1].address or ""
    end
    result.phase, result.connection_text = "stopped", "认证已停止"
    if result.running then
        result.phase, result.connection_text = "unknown", "等待下一次认证"
        if result.pid then
            local raw = fs.readfile("/tmp/minieap-sysu-live-" .. result.pid .. "/state.json")
            local live = raw and #raw < 4096 and json.parse(raw)
            if type(live) == "table" then
                local labels = {connected = "已认证", authenticating = "正在连接校园网…", failed = "认证失败", offline = "连接已断开", disconnected = "网线未连接", stopped = "认证已停止"}
                if labels[live.phase] then result.phase, result.connection_text = live.phase, labels[live.phase] end
                if live.phase == "connected" and type(live.since) == "number" and live.since <= sys.uptime() and live.since >= 0 then
                    result.connected_seconds = math.floor(sys.uptime() - live.since)
                    if not result.wan_up then result.connection_text = "认证成功，正在获取网络地址…" end
                end
            end
        end
    end
    if not result.carrier then result.phase, result.connection_text, result.connected_seconds = "disconnected", "网线未连接", nil end
    result.pid = nil
    return result
end

function M.save(username, password, enabled, nic)
    if type(username) ~= "string" or #username < 1 or #username > 64
       or username:find("[%c%s]") then
        return nil, "账号应为 1–64 字节，不能包含空格、换行或控制字符。"
    end
    if type(password) ~= "string" or #password > 64 or password:find("%c")
       or password:find("%s$") then
        return nil, "密码不能超过 64 字节，不能包含控制字符或以空白结尾。"
    end
    local cfg, raw = read_config()
    if not cfg then return nil, raw end
    -- The stored nic is authoritative; only a different submitted value is validated.
    local target_nic = cfg.nic or ""
    if nic ~= nil and nic ~= "" and nic ~= target_nic then
        if not valid_ifname(nic) then return nil, "网卡名不合法，只允许字母、数字与 _ . : -。" end
        if nic == "lo" then return nil, "不能选择回环接口 lo。" end
        if not stat_ok("/sys/class/net/" .. nic) then return nil, "系统中不存在接口 " .. nic .. "。" end
        target_nic = nic
    end
    if not valid_ifname(target_nic) then target_nic = "eth0" end
    local nic_changed = target_nic ~= (cfg.nic or "")
    if username ~= cfg.username and password == "" then
        return nil, "更换 NetID 时必须同时填写新账号的密码。"
    end
    if password == "" then password = cfg.password end
    if not password or password == "" then return nil, "请填写校园网密码。" end
    local lines = {}
    for line in raw:gmatch("([^\n]+)") do
        local key = line:match("^%s*([%w_-]+)=")
        if key ~= "username" and key ~= "password" and key ~= "nic" then lines[#lines + 1] = line end
    end
    lines[#lines + 1] = "username=" .. username
    lines[#lines + 1] = "password=" .. password
    lines[#lines + 1] = "nic=" .. target_nic
    if not atomic_write(conf .. ".web-backup", raw) then
        return nil, "备份配置失败，未修改认证配置。"
    end
    if not atomic_write(conf, table.concat(lines, "\n") .. "\n") then
        return nil, "保存失败，原认证配置保持不变。"
    end
    local ok = enabled and sys.init.enable(service) or nil
    if not enabled then ok = sys.init.disable(service) end
    if not ok then return nil, "账号配置已保存，但开机启动设置失败，请检查系统日志。" end
    if nic_changed then
        return true, "已保存，认证网卡改为 " .. target_nic .. "；重新认证后才会在新网卡上生效。"
    end
    return true, "已保存。账号密码将在下次启动或重新认证时生效。"
end

function M.action(action)
    local allowed = {start = true, stop = true, restart = true}
    if not allowed[action] then return nil, "不支持的操作。" end
    -- All service names and allowed actions are fixed, never shell form inputs.
    if not sys.init[action](service) then return nil, "服务操作失败，请在系统日志中查看 minieap。" end
    local messages = {
        start = "已提交启动请求，请稍后刷新状态。",
        stop = "认证已停止。",
        restart = "已提交重新认证请求，请稍后刷新状态。"
    }
    return true, messages[action]
end

function M.save_restart(username, password, enabled, nic)
    local ok, message = M.save(username, password, enabled, nic)
    if not ok then return nil, message end
    if not sys.init.restart(service) then
        return nil, "设置已保存，但重新认证请求失败。请查看日志或手动启动认证。"
    end
    return true, "设置已保存，并已提交重新认证请求。请观察最近认证日志。"
end

-- Fixed commands only; retain original log text, including diagnostics.
function M.open_logs(all)
    if not fs.access("/sbin/logread", "x") then return nil, "系统缺少 /sbin/logread。" end
    local command = "/sbin/logread -e '[Mm]ini[Ee][Aa][Pp]' 2>/dev/null"
    if not all then command = command .. " | tail -n 200" end
    local pipe = io.popen(command, "r")
    if not pipe then return nil, "读取认证日志失败。" end
    return pipe
end
function M.logs()
    local pipe, err = M.open_logs(false)
    if not pipe then return "", err end
    local lines = {}
    for line in pipe:lines() do
        lines[#lines + 1] = line
    end
    pipe:close()
    return table.concat(lines, "\n"), #lines == 0 and "暂无认证日志。" or nil
end

-- Session-bound, single-use tickets in RAM prevent retries/back-button replay.
-- A kernel lock serializes all mutations across uhttpd workers and releases on exit.
local tickets = "/tmp/minieap-sysu-luci"
local function valid_id(id)
    return type(id) == "string" and #id == 32 and id:match("^[a-f0-9]+$")
end
local function locked(fn)
    if not fs.stat(tickets) then fs.mkdir(tickets, "rwx------") end
    if not fs.chmod(tickets, "rwx------") then return nil, "无法创建临时操作目录。" end
    local lock = nx.open(tickets .. "/lock", nx.open_flags("wronly", "creat"), "rw-------")
    if not lock then return nil, "无法创建操作锁。" end
    if not lock:lock("tlock") then lock:close(); return nil, "另一个操作正在执行，请稍后刷新页面。" end
    local success, a, b = pcall(fn)
    lock:close()
    if not success then return nil, "操作发生异常，请刷新并检查系统日志；请勿连续点击重新认证。" end
    return a, b
end
local function read_ticket(id, session)
    if not valid_id(id) or type(session) ~= "string" or session == "" then return nil end
    local raw = fs.readfile(tickets .. "/" .. id)
    local item = raw and #raw < 8192 and json.parse(raw)
    if type(item) == "table" and item.session == session and type(item.created) == "number"
       and sys.uptime() - item.created >= 0 and sys.uptime() - item.created < 1800 then return item end
end
function M.ticket(session)
    return locked(function()
        local entries = {}
        for name in fs.dir(tickets) do
            if valid_id(name) then
                local path = tickets .. "/" .. name
                local raw = fs.readfile(path)
                local item = raw and json.parse(raw)
                if type(item) ~= "table" or type(item.created) ~= "number" or sys.uptime() - item.created >= 1800 then
                    fs.remove(path)
                else entries[#entries + 1] = {path = path, created = item.created} end
            end
        end
        table.sort(entries, function(a, b) return a.created < b.created end)
        for i = 1, #entries - 127 do fs.remove(entries[i].path) end
        local id = sys.uniqueid(16)
        if not valid_id(id) or not atomic_write(tickets .. "/" .. id,
            json.stringify({session = session, created = sys.uptime(), used = false})) then
            return nil, "无法生成操作凭证，请刷新页面。"
        end
        return id
    end)
end
function M.result(id, session)
    local item = read_ticket(id, session)
    if item and item.used then return item end
end
-- Consume the display notice, but keep the operation receipt for replay protection.
function M.consume_result(id, session)
    return locked(function()
        local item = read_ticket(id, session)
        if not item or not item.used or item.seen then return nil end
        item.seen = true
        if not atomic_write(tickets .. "/" .. id, json.stringify(item)) then return nil end
        return item
    end)
end
function M.submit(id, session, action, username, password, enabled, nic)
    return locked(function()
        local item = read_ticket(id, session)
        if not item then return nil, "页面已过期，请刷新后重新操作。" end
        if item.used then return item.ok, item.message end
        item.used, item.ok, item.message = true, false, "操作已接收，请查看状态和日志；重复提交不会再次执行。"
        local path = tickets .. "/" .. id
        if not atomic_write(path, json.stringify(item)) then return nil, "无法记录操作，请刷新后重试。" end
        local ok, message
        if action == "save" then ok, message = M.save(username, password, enabled, nic)
        elseif action == "save_restart" then ok, message = M.save_restart(username, password, enabled, nic)
        else ok, message = M.action(action) end
        item.ok, item.message = ok == true, message
        atomic_write(path, json.stringify(item))
        return item.ok, item.message
    end)
end

return M
