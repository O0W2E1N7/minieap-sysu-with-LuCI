# 至善园 MiniEAP LuCI 校园网认证页面

版本：1.5.2（本地测试版）。为已有的 `minieap-sysu` 服务提供网页管理，适用于中山大学东校园至善园的部署方式。
这是社区适配页面，并非锐捷、学校或 GL.iNet 官方插件。

v1.4.1 调整当前状态区域的排版：认证按钮间隔为 12px，按钮行与自动刷新行间隔为 20px，
刷新行内各项间隔为 20px；窄屏自动换行。认证及配置保存逻辑与 v1.4.0 相同。

## v1.5.2 本地测试

- v1.5.2 只统一版本标注：页面、安装提示与文档全部标为 1.5.2，功能与 v1.5.1 相同。

- 页面显示最近 200 条完整认证日志；删除账号密码和 DIAG 隐藏开关，不再截断单行。
- “下载全部认证日志”导出系统缓冲区内仍保留的全部 MiniEAP 日志，按块发送，不额外保存历史文件。
- 操作结果提示只显示一次，刷新整页后消失，可用右侧 × 手动关闭。
- 修正 `luci.util.pcdata()` 旧接口调用，改用 `luci.xml.pcdata()`。
- 保存说明为：“仅保存设置”需要手动重启认证。“保存并重新认证”立即应用设置。
- 连续连接计时及认证启动脚本保持 v1.5.0 的行为。

## 连续连接计时

- 增加本次连续连接时长：认证成功开始计时，保活和重复成功通知不重置，掉线、停止或重新认证结束本次计时。页面刷新后继续累计。
- 页面每秒更新时长，每 5 秒同步后端。计时基于 `/proc/uptime`，不受系统日期校准影响。
- 状态区直接显示“已认证”“正在连接校园网…”等状态；保存说明改为“仅保存设置需要手动重启认证”。

安装会更新并备份 `/usr/libexec/minieap-sysu-run`，新增 Lua 状态记录程序。安装不主动断开现有连接；
安装后点击一次“重新认证”，新启动脚本才开始记录计时。记录在内存临时目录中，网页关闭后仍继续记录。
v1.5.2 已随 [luci-v1.5.2](https://github.com/O0W2E1N7/minieap-sysu-with-LuCI/releases/tag/luci-v1.5.2) 发布（v1.5.1 已被其替代）。首次升级前的连接不补算时长。

## 功能与实测范围

- **LuCI → 服务 → 校园网认证**：保存 NetID/密码，同一账号密码留空时保留原值；更换账号必须填写新密码，前后端均校验。
- 启动、停止、重新认证，以及开机启动开关。
- 分别显示服务运行、eth0 网线连接、WAN IPv4 地址和 WAN 接口状态。
- 默认每 5 秒刷新状态及日志，可暂停或手动刷新；后台标签页暂停定时请求，不覆盖正在填写的账号、密码和开机启动选项。
- 显示最近 200 条 MiniEAP 系统日志；日志使用纯文本显示，保留原始账号密码和 DIAG 内容，并可下载全部认证日志。
- “仅保存设置”不重启服务；“保存并重新认证”在保存成功后提交重启请求。重启失败时明确提示设置已经保存。
- 提交后禁用按钮，服务端使用单次操作凭证和进程间锁，完成后跳转到 GET 页面；同一表单的重复请求不会重复执行认证操作。

实测设备为 GL-MT3600BE，GL.iNet 4.9.0 / OpenWrt 21.02-SNAPSHOT，ARM64，校园网口为 `eth0`。
校园网认证已在该环境成功，用户已确认旧版修正缓存后页面保存正常。v1.4.0 新增功能已通过
本地 Lua 5.1 模拟环境和 JavaScript 交互回归测试，尚未在该路由器实机验证；其他固件与
其他网卡组合仍需验证。v1.5.2 已通过本地逻辑及启动脚本测试，等待路由器实测。

此目录不会改写上游认证算法，也不提供预编译认证内核。LuCI 页面本身不依赖 CPU 架构，
但认证程序必须为设备架构和固件编译。需要旧版 Lua LuCI、`luci.jsonc`、nixio 和 `/sbin/logread`；
缺少兼容组件时，从本机固件软件源安装 `luci-compat`。GL.iNet 原厂后台可通过“系统 → 高级设置 → LuCI”进入页面。

## 与已有 MiniEAP 软件包的区别

页面管理以下固定路径，不是 netifd 的网络接口编辑器：

| 文件 | 用途 |
| --- | --- |
| `/usr/sbin/minieap-sysu` | 已部署的认证程序 |
| `/etc/minieap-sysu.conf` | 账号和认证配置 |
| `/etc/init.d/minieap-sysu` | procd 服务 |
| `/usr/libexec/minieap-sysu-run` | 等待 eth0 链路后启动认证 |

目前网卡固定为 `eth0`。其他设备请同时适配页面、配置和 runner，不能只在配置里改网卡。
如果已经使用这些路径并成功认证，直接安装页面即可。

## 安装页面

在电脑上检出本仓库后，用 Python 3 打包：

```sh
python3 openwrt/luci-app-minieap-sysu/build_bundle.py
```

输出到本目录的 `dist/minieap-sysu-luci.tar.gz`，旁边附 SHA256 文件。
Windows 上可以将 `python3` 换成可用的 `python`。上传到路由器：

```sh
scp -O openwrt/luci-app-minieap-sysu/dist/minieap-sysu-luci.tar.gz root@192.168.8.1:/tmp/
```

在路由器 SSH 中安装：

```sh
mkdir -p /tmp/minieap-luci-v1.5.2
tar -xzf /tmp/minieap-sysu-luci.tar.gz -C /tmp/minieap-luci-v1.5.2 &&
sh /tmp/minieap-luci-v1.5.2/install.sh
```

安装脚本校验包内文件，备份旧版页面与启动脚本，安装页面、连接状态记录模块和启动脚本，并清除 LuCI 临时编译缓存。
安装不会修改现有账号、重启认证、改动防火墙或 OpenClash。退出 LuCI 后重新登录。
`runtime/` 提供首次部署示例；安装脚本从 `root/` 安装新版 runner 和状态记录模块。

## 页面使用

1. 进入页面后自动刷新状态及日志，不需要反复刷新整个网页。取消勾选可暂停；切到后台标签页也会暂停定时请求。
2. 修改当前账号密码可直接保存；修改 NetID 时必须同时输入新账号的密码。此项校验只确认输入完整，账号密码是否正确由认证服务器判断。
3. 点击“保存并重新认证”后等待页面返回，再观察日志与实际联网情况。此操作会短暂中断有线校园网连接。
4. 操作完成后的页面可以安全刷新；双击或重发同一份表单不会再次执行。不同页面的新操作仍可正常提交。

表单操作凭证有效期为 30 分钟；超时、会话失效或出现其他操作正在执行的提示时，重新打开本页后再操作。
自动刷新失败会保留页面中已经填写的内容，并标明状态数据可能过期。未启用 JavaScript 时，
可手动重新打开页面查看状态，后端校验和防重复提交仍生效。

日志来自系统环形日志缓冲区，不持久化到闪存。前台 SSH 运行的输出不一定进入系统日志；
此时日志区显示为空。页面状态与连接时长来自本次认证程序的实时事件。
页面不截断单行，下载内容不受页面 200 条限制；已经从系统缓冲区滚出的记录无法恢复。

## 尚未配置服务时

先按仓库根目录说明，为设备编译并验证 MiniEAP 可执行文件。确认网卡确实是 `eth0`，
并停止其他认证客户端。下面操作只适用于首次部署，已有可用配置时不要覆盖。

将可执行文件传至 `/tmp/minieap`，将本目录的 `runtime/` 传至 `/tmp/minieap-runtime/`。
在路由器中执行：

```sh
mkdir -p /usr/libexec
cp /tmp/minieap /usr/sbin/minieap-sysu
chmod 755 /usr/sbin/minieap-sysu
cp /tmp/minieap-runtime/minieap-sysu.init /etc/init.d/minieap-sysu
cp /tmp/minieap-runtime/minieap-sysu-run /usr/libexec/minieap-sysu-run
chmod 755 /etc/init.d/minieap-sysu /usr/libexec/minieap-sysu-run
if [ ! -e /etc/minieap-sysu.conf ]; then
    (umask 077; cp /tmp/minieap-runtime/minieap-sysu.conf.example /etc/minieap-sysu.conf)
fi
```

然后安装页面，在页面填写自己的账号密码、保存并点击启动。根据实际结果开启开机认证。
该示例使用标准 EAP、`sockraw`，没有启用 `rjv3` 扩展；这对应此次至善园成功部署，
不代表所有校区或宿舍网口都采用相同参数。

## 密码保存与故障排查

- 写入使用临时文件加原子替换，权限为 `rw-------`；旧配置保存在
  `/etc/minieap-sysu.conf.web-backup`，同样只有 root 可读写。
- 已保存密码不会返回浏览器。输入限制防止换行注入，服务动作使用固定白名单，写操作检查
  登录会话与 CSRF token。配置及备份仍是路由器上的明文文件，需保护管理员访问权限。
- 单次操作凭证及结果保存在 `/tmp/minieap-sysu-luci/`，目录仅 root 可访问，最多保留 128 份
  凭证，重启后清空；凭证不存储表单中的账号密码。进程间锁避免并发写配置或并发发出服务动作。
- `bad argument #3 to 'open'`：旧版本把 POSIX 数字权限 `384` 直接传给 nixio；
  已改用明确的 `rw-------`。如果文件已更新但错误不变，清除 LuCI 编译缓存。
- LuCI 21.02 的模块缓存文件名为完整模块名的十六进制编码；修改源码、刷新网页或只重启
  uhttpd 可能仍加载旧缓存。修复后可执行：

  ```sh
  rm -f /tmp/luci-modulecache/* /tmp/luci-indexcache /tmp/luci-indexcache.*
  /etc/init.d/uhttpd restart
  ```

- 停止认证程序不保证服务器立刻释放在线会话。如提示账号同时在线数量超限，先让原有设备
  通过认证客户端主动下线，必要时通过校园网管理渠道清理残留会话。

## 开发验证

在 Linux / WSL、Lua 5.1、Python 3 和 Node.js 环境，从仓库根目录运行：

```sh
lua5.1 openwrt/luci-app-minieap-sysu/tests/test_adapter.lua openwrt/luci-app-minieap-sysu
lua5.1 openwrt/luci-app-minieap-sysu/tests/test_monitor.lua openwrt/luci-app-minieap-sysu
node openwrt/luci-app-minieap-sysu/tests/test_page.js
python3 openwrt/luci-app-minieap-sysu/tests/test_cache_cleanup.py
python3 openwrt/luci-app-minieap-sysu/tests/test_runner.py
sh -n openwrt/luci-app-minieap-sysu/install.sh
python3 openwrt/luci-app-minieap-sysu/build_bundle.py
```

测试覆盖模拟 LuCI 环境下的密码保留、更换账号校验、特殊字符、私有权限、原子写入失败、
保存后重启及失败提示、POST/CSRF、303 跳转、凭证过期/会话绑定/重复请求、锁冲突、完整日志导出、一次性提示、
模板转义、服务动作白名单，以及真实缓存文件命名方式的清理回归。
JavaScript 测试使用模拟 DOM/XHR，覆盖自动刷新不覆盖表单、标签页暂停、网络/登录失效、
纯文本日志、滚动位置、换账号校验、提交动作保留、重复点击和返回缓存页面。
这些测试不能替代不同路由器上的实机验证。测试凭据均为虚构字符串。

## 回退到安装前版本

安装输出会显示 `/root/minieap-luci-backup-时间-进程号` 目录。将该目录内原有页面文件和
`usr/libexec/minieap-sysu-run` 按相同路径复制回 `/`，清除下述 LuCI 缓存，再手动重新认证。
不要使用只覆盖页面的旧包代替启动脚本回退。新版两个 Lua 状态记录文件保留也不会被旧 runner 调用。

## 卸载页面

```sh
rm -f /usr/lib/lua/luci/controller/minieap_sysu.lua
rm -f /usr/lib/lua/luci/model/minieap_sysu.lua
rm -f /usr/lib/lua/luci/view/minieap_sysu/index.htm
rm -f /tmp/luci-modulecache/* /tmp/luci-indexcache /tmp/luci-indexcache.*
```

上述操作只移除页面，认证程序、服务和账号配置仍保留。

## 许可证

本目录新编写的 LuCI 适配代码及辅助脚本采用 [MIT](LICENSE)；上游 MiniEAP 保持仓库根目录
的 GPL-3.0 许可证及原作者声明。感谢 undefined443/minieap-sysu、updateing/minieap 和 LuCI 项目。
