module("luci.controller.minieap_sysu", package.seeall)

function index()
    local page = entry({"admin", "services", "minieap_sysu"}, call("action_index"), "校园网认证", 65)
    page.dependent = false
    page.sysauth = "root"
    page.sysauth_authenticator = "htmlauth"
    entry({"admin", "services", "minieap_sysu", "update"}, post("action_update")).leaf = true
    entry({"admin", "services", "minieap_sysu", "status"}, call("action_status")).leaf = true
end

local function render(message, error_message)
    local http = require "luci.http"
    local dispatcher = require "luci.dispatcher"
    local model = require "luci.model.minieap_sysu"
    local request_id, ticket_error = model.ticket(dispatcher.context.authtoken)
    local logs, logs_message = model.logs()
    http.header("Cache-Control", "no-store")
    require("luci.template").render("minieap_sysu/index", {
        state = model.status(),
        request_id = request_id,
        logs = logs,
        logs_message = logs_message,
        token = dispatcher.context.authtoken,
        message = message,
        error_message = error_message or ticket_error
    })
end

function action_index()
    local http = require "luci.http"
    local result = require("luci.model.minieap_sysu").result(http.formvalue("result"),
        require("luci.dispatcher").context.authtoken)
    if result then
        render(result.ok and result.message or nil, not result.ok and result.message or nil)
    else
        render(nil, http.formvalue("notice") == "retry" and "未能执行操作：页面凭证已过期或其他操作正在进行，请重新尝试。" or nil)
    end
end

function action_status()
    local http = require "luci.http"
    local model = require "luci.model.minieap_sysu"
    local state = model.status()
    state.username = nil
    local logs, logs_message = model.logs()
    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    http.write_json({state = state, logs = logs, logs_message = logs_message})
end

function action_update()
    local dispatcher = require "luci.dispatcher"
    if not dispatcher.test_post_security() then return end
    local http = require "luci.http"
    local model = require "luci.model.minieap_sysu"
    local action = http.formvalue("action")
    local id = http.formvalue("request_id")
    model.submit(id, dispatcher.context.authtoken, action, http.formvalue("username"),
        http.formvalue("password") or "", http.formvalue("enabled") == "1")
    local suffix = model.result(id, dispatcher.context.authtoken) and ("?result=" .. id) or "?notice=retry"
    -- POST/Redirect/GET prevents refresh from repeating a mutation.
    http.status(303, "See Other")
    http.header("Cache-Control", "no-store")
    http.header("Location", dispatcher.build_url("admin", "services", "minieap_sysu") .. suffix)
end
