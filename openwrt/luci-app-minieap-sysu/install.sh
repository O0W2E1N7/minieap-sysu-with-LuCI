#!/bin/sh
set -eu
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo '请以 root 执行。'; exit 1; }
[ -x /usr/sbin/minieap-sysu ] && [ -x /etc/init.d/minieap-sysu ] && [ -s /etc/minieap-sysu.conf ] || {
    echo '请先完成已有 MiniEAP 服务的安装。'; exit 1;
}
lua -e 'require("luci.dispatcher"); require("luci.template"); require("luci.sys"); require("luci.jsonc"); require("luci.xml"); require("nixio.fs")' || {
    echo '缺少 LuCI Lua 组件。请先安装 luci-compat 后重试。'; exit 1;
}
sha256sum -c SHA256SUMS
command -v mkfifo >/dev/null || { echo '缺少 mkfifo，未安装。'; exit 1; }
grep -q '/usr/libexec/minieap-sysu-run' /etc/init.d/minieap-sysu || {
    echo '现有服务未使用 minieap-sysu-run，请先适配启动路径。'; exit 1;
}
backup="/root/minieap-luci-backup-$(date +%Y%m%d-%H%M%S)-$$"
for rel in usr/lib/lua/luci/controller/minieap_sysu.lua usr/lib/lua/luci/model/minieap_sysu.lua usr/lib/lua/luci/view/minieap_sysu/index.htm usr/lib/lua/luci/model/minieap_session.lua usr/libexec/minieap-sysu-monitor.lua usr/libexec/minieap-sysu-run; do
    if [ -e "/$rel" ]; then
        mkdir -p "$backup/$(dirname "$rel")"
        cp -p "/$rel" "$backup/$rel"
    fi
    mkdir -p "/$(dirname "$rel")"
    cp "root/$rel" "/$rel"
    chmod 644 "/$rel"
    [ "$rel" != usr/libexec/minieap-sysu-run ] || chmod 755 "/$rel"
done
# Only generated LuCI caches; no service/network restart and no credential edit.
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* /tmp/luci-modulecache/*
echo '已安装 v1.5.2：LuCI → 服务 → 校园网认证。请退出 LuCI 后重新登录。'
echo '已更新计时启动脚本；现有连接保持运行。点击一次“重新认证”后开始记录连接时长。'
if [ -d "$backup" ]; then echo "旧版页面备份在：$backup"; fi
