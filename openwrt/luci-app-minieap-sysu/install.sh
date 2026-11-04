#!/bin/sh
set -eu
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo '请以 root 执行。'; exit 1; }
[ -x /usr/sbin/minieap-sysu ] && [ -x /etc/init.d/minieap-sysu ] && [ -s /etc/minieap-sysu.conf ] || {
    echo '请先完成已有 MiniEAP 服务的安装。'; exit 1;
}
lua -e 'require("luci.dispatcher"); require("luci.template"); require("luci.sys"); require("luci.jsonc"); require("nixio.fs")' || {
    echo '缺少 LuCI Lua 组件。请先安装 luci-compat 后重试。'; exit 1;
}
sha256sum -c SHA256SUMS
backup="/root/minieap-luci-backup-$(date +%Y%m%d-%H%M%S)-$$"
for rel in usr/lib/lua/luci/controller/minieap_sysu.lua usr/lib/lua/luci/model/minieap_sysu.lua usr/lib/lua/luci/view/minieap_sysu/index.htm; do
    if [ -e "/$rel" ]; then
        mkdir -p "$backup/$(dirname "$rel")"
        cp -p "/$rel" "$backup/$rel"
    fi
    mkdir -p "/$(dirname "$rel")"
    cp "root/$rel" "/$rel"
    chmod 644 "/$rel"
done
# Only generated LuCI caches; no service/network restart and no credential edit.
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* /tmp/luci-modulecache/*
echo '已安装 v1.4.0：LuCI → 服务 → 校园网认证。请退出 LuCI 后重新登录。'
echo '现有账号、认证程序、网络配置和运行中的服务均未修改。'
if [ -d "$backup" ]; then echo "旧版页面备份在：$backup"; fi
