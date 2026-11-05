# 至善园 MiniEAP LuCI 校园网认证页面

版本：1.6.0。为已有的 `minieap-sysu` 服务提供网页管理，适用于中山大学东校园至善园的部署方式。
这是社区适配页面，并非锐捷、学校或 GL.iNet 官方插件。

v1.4.1 调整当前状态区域的排版：认证按钮间隔为 12px，按钮行与自动刷新行间隔为 20px，
刷新行内各项间隔为 20px；窄屏自动换行。认证及配置保存逻辑与 v1.4.0 相同。

## v1.6.0 认证网卡选择

- 认证网卡改为下拉选择：扫描 `/sys/class/net`，默认只列“独立物理口”——存在 `device`、不是网桥、不是桥成员、不是无线接口；其余接口需勾选“显示全部接口”才可见。
- 每一项显示类型、链路与 IPv4；桥接、桥成员、无线接口会标注“可能不通”。
- 切换网卡后需要重新认证才生效；仅保存不会立即断网。
- 只保存未重启时，网络状态区会提示“已切换为 X，需重新认证后生效；当前仍在 Y 上认证”——启动脚本会把实际使用的接口记在会话目录里，页面据此区分“配置已改”和“已生效”。
- 配置文件里的 `nic=` 是唯一事实源：状态检测、启动脚本与状态记录程序都从它读取；缺少该行时回退 `eth0`。
- 启动脚本等待所选网卡的链路，并每 30 秒输出一条等待日志，不再静默阻塞。

## v1.5.2 页面交互改进

- 状态摘要卡片移到页首：认证状态、本次已连接时长、认证服务、开机启动四项并排显示，无需滚动即可确认结果。
- 操作提示独立成区：成功提示 6 秒后自动消失（鼠标悬停时暂停），并提供“查看日志”锚点；警告与错误提示保持常驻。
- 关闭按钮改为 32px 点击区，补 hover 与键盘焦点样式；提示渲染后清除地址栏里的一次性 result 参数。
- 提交时被点击的按钮显示“提交中…”；选择“保存并重新认证”后，页面显示“正在重新认证…”并以 2 秒间隔加速刷新，拿到后端状态后恢复正常节奏。
- 提交后保留原有滚动位置，不再跳回页首。
- 日志默认折叠连续重复行（心跳类消息），可取消勾选查看原始内容；下载内容不受折叠影响。

## v1.5.1 本地测试

- 页面显示最近 200 条完整认证日志；删除账号密码和 DIAG 隐藏开关，不再截断单行。
- “下载全部认证日志”导出系统缓冲区内仍保留的全部 MiniEAP 日志，按块发送，不额外保存历史文件。
- 操作结果提示只显示一次，刷新整页后消失，可用右侧 × 手动关闭。
- 修正 `luci.util.pcdata()` 旧接口调用，改用 `luci.xml.pcdata()`。
- 保存说明为：“仅保存设置”需要手动重启认证。“保存并重新认证”立即应用设置。

## 连续连接计时

- 增加本次连续连接时长：认证成功开始计时，保活和重复成功通知不重置，掉线、停止或重新认证结束本次计时。页面刷新后继续累计。
- 页面每秒更新时长，每 5 秒同步后端。计时基于 `/proc/uptime`，不受系统日期校准影响。
- 状态区直接显示“已认证”“正在连接校园网…”等状态；保存说明改为“仅保存设置需要手动重启认证”。

安装会更新并备份 `/usr/libexec/minieap-sysu-run`，新增 Lua 状态记录程序。安装不主动断开现有连接；
安装后点击一次“重新认证”，新启动脚本才开始记录计时。记录在内存临时目录中，网页关闭后仍继续记录。
v1.6.0 已随 [luci-v1.6.0](https://github.com/O0W2E1N7/minieap-sysu-with-LuCI/releases/tag/luci-v1.6.0) 发布。首次升级前的连接不补算时长。

## 功能与实测范围

- **LuCI → 服务 → 校园网认证**：保存 NetID/密码，同一账号密码留空时保留原值；更换账号必须填写新密码，前后端均校验。
- 启动、停止、重新认证，以及开机启动开关。
- 分别显示服务运行、校园网网口链路、WAN IPv4 地址和 WAN 接口状态。
- 默认每 5 秒刷新状态及日志，可暂停或手动刷新；后台标签页暂停定时请求，不覆盖正在填写的账号、密码和开机启动选项。
- 显示最近 200 条 MiniEAP 系统日志；日志使用纯文本显示，保留原始账号密码和 DIAG 内容，并可下载全部认证日志；分享日志前请自行遮挡账号密码。
- “仅保存设置”不重启服务；“保存并重新认证”在保存成功后提交重启请求。重启失败时明确提示设置已经保存。
- 提交后禁用按钮，服务端使用单次操作凭证和进程间锁，完成后跳转到 GET 页面；同一表单的重复请求不会重复执行认证操作。

实测设备为 GL-MT3600BE，GL.iNet 4.9.0 / OpenWrt 21.02-SNAPSHOT，ARM64。
v1.5.2 的页面交互与认证程序修复均已在该设备实机验证：页面安装、状态摘要、日志折叠、
提示条与提交反馈正常；替换认证程序后重新认证只出现一次失败，之后未再出现 30 秒循环。
v1.4.0–v1.5.1 的功能只做过本地 Lua 5.1 与 JavaScript 回归测试。
v1.6.0 的网卡扫描、分组与切换提示也已在同一设备实机验证；该设备只有一个可用物理口，
切换到其他接口后的认证效果未验证，其他固件与网卡组合仍需自行验证。

此目录的安装包不会改写认证算法，也不包含预编译认证内核：LuCI 页面本身不依赖 CPU 架构，
但认证程序必须为设备架构和固件编译。需要旧版 Lua LuCI、`luci.jsonc`、nixio 和 `/sbin/logread`；
缺少兼容组件时，从本机固件软件源安装 `luci-compat`。GL.iNet 原厂后台可通过“系统 → 高级设置 → LuCI”进入页面。

## 认证程序修复（可选二进制）

本目录的安装包只含页面与脚本，不含认证程序。仓库在 v1.5.2 另修了两个认证程序缺陷——
失败重试定时器未取消导致的 30 秒循环、链接脚本缺少 `KEEP()` 导致的模块注册表被回收——
并在 Releases 提供按本仓库源码构建的 aarch64 静态二进制 `minieap-sysu-aarch64-v1.6.0`。

替换 `/usr/sbin/minieap-sysu` 前请先备份；停止服务后等待约 20 秒再启动，让交换机释放旧会话。
完整步骤、校验值与回退方式见 [luci-v1.6.0 发布说明](https://github.com/O0W2E1N7/minieap-sysu-with-LuCI/releases/tag/luci-v1.6.0)。
页面不需要这个二进制也能正常工作，它只修认证程序侧的问题。

## 与已有 MiniEAP 软件包的区别

页面管理以下固定路径，不是 netifd 的网络接口编辑器：

| 文件 | 用途 |
| --- | --- |
| `/usr/sbin/minieap-sysu` | 已部署的认证程序 |
| `/etc/minieap-sysu.conf` | 账号和认证配置 |
| `/etc/init.d/minieap-sysu` | procd 服务 |
| `/usr/libexec/minieap-sysu-run` | 等待所选网卡的链路后启动认证 |

v1.6.0 起可在页面直接选择认证网卡，配置、启动脚本与状态记录程序都以配置里的 `nic=` 为准；
缺少该行时回退 `eth0`。只有选择 `eth0` 之外的口时，才需要确认该固件下 raw socket 是否能从该口发出。
如果已经使用这些路径并成功认证，直接安装页面即可。

## 安装页面

两种方式任选其一：直接下载现成安装包，或从源码自行打包。现成包在
[Releases](https://github.com/O0W2E1N7/minieap-sysu-with-LuCI/releases)，下载
`minieap-sysu-luci-v1.6.0.tar.gz` 及其同名 `.sha256` 文件后，跳过打包步骤，直接看下文“上传到路由器”（把命令里的路径换成下载的文件名）。

从源码打包（Python 3）：

```sh
python3 openwrt/luci-app-minieap-sysu/build_bundle.py
```

输出到 `openwrt/luci-app-minieap-sysu/dist/minieap-sysu-luci.tar.gz`，旁边附同名 SHA256 文件。
Windows 上可以将 `python3` 换成可用的 `python`。

上传到路由器（连同 `.sha256` 一起传，便于校验）：

```sh
scp -O openwrt/luci-app-minieap-sysu/dist/minieap-sysu-luci.tar.gz \
       openwrt/luci-app-minieap-sysu/dist/minieap-sysu-luci.tar.gz.sha256 root@192.168.8.1:/tmp/
```

在路由器 SSH 中安装。先校验包的 SHA256，通过后再解压执行；从 Release 下载时文件名带版本号，
把下面的文件名换成实际下载的名字即可：

```sh
cd /tmp &&
sha256sum -c minieap-sysu-luci.tar.gz.sha256 &&
mkdir -p /tmp/minieap-luci-v1.6.0 &&
tar -xzf /tmp/minieap-sysu-luci.tar.gz -C /tmp/minieap-luci-v1.6.0 &&
sh /tmp/minieap-luci-v1.6.0/install.sh
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

## 常见问题

- **认证网卡列表里只有 `eth0`**：默认只列“独立物理口”——必须存在 `/sys/class/net/<名字>/device`、不在网桥中、不是桥成员、不是无线接口。其余接口要勾选“显示全部接口”才出现。实测这台 GL-MT3600BE 的 16 个接口里只有 `eth0` 符合，`eth1` 因桥接进 `br-lan` 被排除，`ra*`/`rai*`/`apcli*` 因无线被排除。
- **选了别的接口后认证失败**：桥接或无线接口发出的 EAPOL 通常不通。改回 `eth0` 再点“保存并重新认证”；只想恢复配置、不想立刻断网时用“仅保存设置”。
- **状态区提示“已切换为 X，需重新认证后生效”**：配置已改，但当前进程仍在旧接口上认证。点一次“保存并重新认证”，提示会自动消失。
- **列表里出现“（当前配置）”**：说明扫描结果里没找到配置中的网卡（可能已不存在或未通过筛选），页面直接回显配置值，避免把已有设置弄丢。

## 尚未配置服务时

先按仓库根目录说明，为设备编译并验证 MiniEAP 可执行文件——也可以直接使用 Releases 里
已修复的 `minieap-sysu-aarch64-v1.6.0`。确认网卡配置与上文说明一致，并停止其他认证客户端。
下面操作只适用于首次部署，已有可用配置时不要覆盖。

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
模板转义、服务动作白名单、接口扫描与网卡切换校验，以及真实缓存文件命名方式的清理回归。
JavaScript 测试使用模拟 DOM/XHR，覆盖自动刷新不覆盖表单、标签页暂停、网络/登录失效、
纯文本日志、滚动位置、换账号校验、提交动作保留、重复点击和返回缓存页面，以及提示自动消失与悬停暂停、
地址栏一次性参数清理、提交进度文案、滚动位置恢复、重认证加速轮询、日志折叠与还原。
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
安装脚本还会装入 `model/minieap_session.lua` 与 `usr/libexec/minieap-sysu-monitor.lua`，
并替换 `usr/libexec/minieap-sysu-run`；这些由“回退到安装前版本”一节的备份恢复，卸载页面时无需单独删除。

## 许可证

本目录新编写的 LuCI 适配代码及辅助脚本采用 [MIT](LICENSE)；上游 MiniEAP 保持仓库根目录
的 GPL-3.0 许可证及原作者声明。感谢 undefined443/minieap-sysu、updateing/minieap 和 LuCI 项目。

