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
    -- Never pass the stored password into the template or a response.
    local result = {
        username = cfg and cfg.username or "",
        nic = cfg and cfg.nic or "",
        configured = cfg and (cfg.username or "") ~= "" and (cfg.password or "") ~= "" or false,
        error = not cfg and err or nil,
        enabled = sys.init.enabled(service),
        running = false,
        carrier = (fs.readfile("/sys/class/net/eth0/carrier") or ""):match("^1") ~= nil,
        wan_up = false,
        address = ""
    }
    local ok, state = pcall(util.ubus, "service", "list", {name = service})
    if ok and state and state[service] then
        for _, instance in pairs(state[service].instances or {}) do
            if instance.running then result.running = true end
        end
    end
    local wok, wan = pcall(util.ubus, "network.interface.wan", "status", {})
    if wok and wan then
        result.wan_up = wan.up == true
        local addresses = wan["ipv4-address"] or {}
        result.address = addresses[1] and addresses[1].address or ""
    end
    return result
end

function M.save(username, password, enabled)
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
    if cfg.nic ~= "eth0" then return nil, "此页面适配 eth0，请先确认现有网卡配置。" end
    if username ~= cfg.username and password == "" then
        return nil, "更换 NetID 时必须同时填写新账号的密码。"
    end
    if password == "" then password = cfg.password end
    if not password or password == "" then return nil, "请填写校园网密码。" end
    local lines = {}
    for line in raw:gmatch("([^\n]+)") do
        local key = line:match("^%s*([%w_-]+)=")
        if key ~= "username" and key ~= "password" then lines[#lines + 1] = line end
    end
    lines[#lines + 1] = "username=" .. username
    lines[#lines + 1] = "password=" .. password
    if not atomic_write(conf .. ".web-backup", raw) then
        return nil, "备份配置失败，未修改认证配置。"
    end
    if not atomic_write(conf, table.concat(lines, "\n") .. "\n") then
        return nil, "保存失败，原认证配置保持不变。"
    end
    local ok = enabled and sys.init.enable(service) or nil
    if not enabled then ok = sys.init.disable(service) end
    if not ok then return nil, "账号配置已保存，但开机启动设置失败，请检查系统日志。" end
    return true, "已保存。账号密码将在下次启动或重新认证时生效。"
end

function M.action(action)
    local allowed = {start = true, stop = true, restart = true}
    if not allowed[action] then return nil, "不支持的操作。" end
    -- All service names and allowed actions are fixed, never shell form inputs.
    if not sys.init[action](service) then return nil, "服务操作失败，请在系统日志中查看 minieap。" end
    local messages = {
        start = "已提交启动请求，请稍后刷新状态。",
        stop = "已停止认证服务。服务器可能需要稍后才释放在线会话。",
        restart = "已提交重新认证请求，请稍后刷新状态。"
    }
    return true, messages[action]
end

function M.save_restart(username, password, enabled)
    local ok, message = M.save(username, password, enabled)
    if not ok then return nil, message end
    if not sys.init.restart(service) then
        return nil, "设置已保存，但重新认证请求失败。请查看日志或手动启动认证。"
    end
    return true, "设置已保存，并已提交重新认证请求。请观察最近认证日志。"
end

-- Read only this service's recent log lines. No form input enters the shell.
function M.logs()
    if not fs.access("/sbin/logread", "x") then
        return "", "系统缺少 /sbin/logread，无法读取认证日志。"
    end
    local secrets = {}
    for _, path in ipairs({conf, conf .. ".web-backup"}) do
        local raw = fs.readfile(path)
        if raw and #raw <= 16384 then
            for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
                local key, value = line:match("^%s*([%w_-]+)=(.*)$")
                if (key == "username" or key == "password") and value ~= "" then
                    secrets[#secrets + 1] = value:gsub("%s+$", "")
                end
            end
        end
    end
    table.sort(secrets, function(a, b) return #a > #b end)
    local pipe = io.popen("/sbin/logread -e '[Mm]ini[Ee][Aa][Pp]' 2>/dev/null | tail -n 60", "r")
    if not pipe then return "", "读取认证日志失败。" end
    local lines = {}
    for line in pipe:lines() do
        -- Omit raw diagnostic payloads; do not expose challenge/response dumps.
        if line:find("[Mm]ini[Ee][Aa][Pp]") then
            if line:find("DIAG", 1, true) or line:lower():find("hex=", 1, true) then
                line = "[诊断报文内容已隐藏]"
            else
                line = line:gsub("\27%[[%d;]*m", "")
                for _, value in ipairs(secrets) do
                    if value ~= "" then
                        line = line:gsub(value:gsub("(%W)", "%%%1"), function() return "[已隐藏]" end)
                    end
                end
                line = line:gsub("%c", " ")
            end
            -- Do not split a UTF-8 character at the output limit.
            local last = math.min(#line, 1024)
            while last > 0 and line:byte(last + 1) and line:byte(last + 1) >= 128
                  and line:byte(last + 1) < 192 do last = last - 1 end
            lines[#lines + 1] = line:sub(1, last)
            if #lines >= 60 then break end
        end
    end
    pipe:close()
    return table.concat(lines, "\n"), #lines == 0 and "暂无认证日志。仅显示系统日志中的 MiniEAP 记录，SSH 前台输出不一定包含在内。" or nil
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
function M.submit(id, session, action, username, password, enabled)
    return locked(function()
        local item = read_ticket(id, session)
        if not item then return nil, "页面已过期，请刷新后重新操作。" end
        if item.used then return item.ok, item.message end
        item.used, item.ok, item.message = true, false, "操作已接收，请查看状态和日志；重复提交不会再次执行。"
        local path = tickets .. "/" .. id
        if not atomic_write(path, json.stringify(item)) then return nil, "无法记录操作，请刷新后重试。" end
        local ok, message
        if action == "save" then ok, message = M.save(username, password, enabled)
        elseif action == "save_restart" then ok, message = M.save_restart(username, password, enabled)
        else ok, message = M.action(action) end
        item.ok, item.message = ok == true, message
        atomic_write(path, json.stringify(item))
        return item.ok, item.message
    end)
end

return M
