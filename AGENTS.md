# AGENTS.md — 在本仓库工作的规范

面向在此仓库继续工作的 agent（也适用于人类维护者）。**先读完第 1、3、6 节再动手。**

## 1. 项目是什么

中山大学东校园至善园的 802.1X 认证客户端 + LuCI 页面。仓库有两类产物，**不要混淆**：

| 产物 | 来源 | 是否随页面包发布 |
| --- | --- | --- |
| LuCI 页面包 `minieap-sysu-luci-vX.Y.Z.tar.gz` | `openwrt/luci-app-minieap-sysu/` 由 `build_bundle.py` 打包 | 是（唯一被打包的目录） |
| 认证程序二进制 `minieap-sysu-aarch64-vX.Y.Z` | 根目录 C 源码，用 Zig 交叉编译 | 否，作为 Release 单独附件 |

```
/
├── *.c *.h                    # 上游 minieap 源码 + 两处本地修复（见 §7）
├── Makefile, append.mk, config.mk
├── minieap_init_func.lds      # 模块注册表链接脚本（含 KEEP，见 §7）
├── README.md                  # 仓库说明（不打包）
├── AGENTS.md                  # 本文件
└── openwrt/luci-app-minieap-sysu/
    ├── README.md              # 页面使用文档（**会打包**）
    ├── install.sh             # 安装脚本（**会打包**）
    ├── build_bundle.py        # 打包脚本
    ├── root/                  # 实际安装到路由器的文件（**会打包**）
    ├── runtime/               # 首次部署示例（**会打包**）
    ├── tests/                 # 测试（不打包）
    └── dist/                  # 构建产物（gitignore，勿编辑、勿提交）
```

关键运行时组件：

- `root/usr/lib/lua/luci/controller|model|view` — 页面本身
- `root/usr/libexec/minieap-sysu-run` — procd 托管的守护脚本，从配置读 `nic=` 并等待链路
- `root/usr/libexec/minieap-sysu-monitor.lua` — 解析 minieap 输出，写 `state.json`

## 2. 环境准备

| 工具 | 用途 | 备注 |
| --- | --- | --- |
| WSL2 + Ubuntu | 跑 Lua / shell / Python 测试 | `test_runner.py` 需要 `/bin/sh`，`test_cache_cleanup.py` 需要 `/tmp` |
| Node.js | `test_page.js` | 无第三方依赖 |
| Python 3 | 打包与两个 Python 测试 | |
| Zig 0.14.1 | 编 aarch64 二进制；**也用来编 Lua 5.1 解释器** | 官网或已解压的 `zig.exe` |

本机常见位置：Zig 在 `%TEMP%\zig14\zig-x86_64-windows-0.14.1\zig.exe`，Lua 解释器在 `%TEMP%\lua-bin`（若已被清理，按 §5.2 重建）。

## 3. 硬性规则（违反会直接破坏发布一致性）

1. **页面包里只有** `install.sh`、`README.md`、`LICENSE`、`root/**`、`runtime/**`。改动其中任何文件都会改变包哈希，必须重建包并同步 Release。
2. **改根目录 C 代码必须重建 aarch64 二进制**并作为附件发布，否则源码与二进制不一致。
3. **所有文本文件用 LF 换行**。模板测试用 `%q` 生成 Lua 源码，裸 `\r` 会让字符串字面量报 "unfinished string"。Windows 上不要用 `Set-Content` 写 `index.htm`（会写 CRLF + BOM），改用 `[System.IO.File]::WriteAllText` + `UTF8Encoding($false)`。
4. **不要手工编辑或提交 `dist/`**，它由 `build_bundle.py` 生成且被 gitignore。
5. **发布标签一旦是正式版就不要移动**（见 §6.4）；仍在验证期的预发布可以移动。
6. 改动后必须让 §5 的五套测试全绿。

## 4. 代码规范

### Lua（LuCI 页面）

- 目标运行时是 **Lua 5.1**：不能用 `goto`、位运算、`table.pack`、`//` 整除等 5.2+ 特性。
- 数据访问用 `nixio.fs` / `nixio` / `luci.sys` / `luci.jsonc`，不要假设有 `io` 权限。
- 函数用 `返回 true, 消息` 或 `返回 nil, 错误` 的两段式，不要抛异常。
- 写入配置必须走 `atomic_write`（临时文件 + rename），权限 `rw-------`。
- 模板里所有动态文本必须过 `esc()`（`luci.xml.pcdata`），不要用已废弃的 `luci.util.pcdata`。
- 单次操作凭证、锁、进程间互斥的逻辑在 `model` 里，改动时保持"重复提交不重复执行"的语义。

### JavaScript（页面内联）

- **ES5 语法**，无第三方库，兼容老版 LuCI 浏览器环境。
- 所有新 DOM 查询都要判空（例如 `var x = el('foo'); if (x) {...}`），因为测试夹具是精简的假 DOM。
- 不要破坏轮询约定：`setTimeout(refresh, 5000)` 是测试断言的一部分（`test_page.js` 会检查 5000ms）。
- 状态更新用 `text(id, value)`（`textContent`），禁止 `innerHTML`。

### Shell（runner / install.sh）

- BusyBox ash：不用 bashisms（无 `[[ ]]`、无数组、无 `local -r`）。
- 接口名从配置读取后必须校验：`case "$NIC" in ""|*[!A-Za-z0-9_.:-]*) NIC=eth0 ;; esac`。
- 路径拼接一律加引号。
- 退出清理走 `trap cleanup EXIT`，并清理会话目录里的 `output`、`state.json`、`nic`。

### C

- 只做最小修改，保持上游代码风格；不要重排、不要顺手重构。
- 改完必须按 §5.3 重建并从标签重编一次确认哈希稳定。

## 5. 测试

### 5.1 五套测试（全部要在改完后跑）

| 测试 | 命令 | 环境 |
| --- | --- | --- |
| 页面交互 | `node openwrt/luci-app-minieap-sysu/tests/test_page.js` | Windows/WSL 均可 |
| 模型/控制器/模板 | `lua51 tests/test_adapter.lua <app-dir>` | 需 Lua 5.1（见 5.2） |
| 状态记录 | `lua51 tests/test_monitor.lua <app-dir>` | 同上 |
| 守护脚本 | `python3 tests/test_runner.py` | **必须 Linux/WSL** |
| 缓存清理 | `python3 tests/test_cache_cleanup.py` | **必须 Linux/WSL** |

在 WSL 里跑 Lua 测试的完整形式：

```sh
cp -r /mnt/d/Documents/ChatGPT/折腾/minieap-sysu-fork/openwrt/luci-app-minieap-sysu /mnt/d/Temp/app-test
cd /mnt/d/Temp/app-test
/mnt/d/Temp/lua51 tests/test_adapter.lua /mnt/d/Temp/app-test
/mnt/d/Temp/lua51 tests/test_monitor.lua /mnt/d/Temp/app-test
python3 tests/test_runner.py
python3 tests/test_cache_cleanup.py
```

通过标准：每套输出一行 `PASS: ...`，退出码 0。

### 5.2 没有 Lua 5.1 时怎么办

`lua.org` 可能被网络挡掉，此时从 GitHub 官方镜像逐文件取源码：

```sh
curl -s https://api.github.com/repos/lua/lua/git/trees/v5.1?recursive=1   # 列出文件
# 逐个下载 raw.githubusercontent.com/lua/lua/v5.1/<文件> 到同一目录
```

然后用 Zig 编成 Linux 静态可执行文件：

```sh
zig cc -target x86_64-linux-musl -O2 -static -DLUA_USE_POSIX <除 ltests.c 外的 *.c> -o lua51 -lm
```

编好后复制到 `D:\Temp\lua51`，即可在 WSL 中调用。

### 5.3 构建产物

页面包：

```sh
cd openwrt/luci-app-minieap-sysu
python3 build_bundle.py          # 输出到 dist/，同时生成 .sha256
```

aarch64 二进制（与 Releases 中发布的完全一致）：

```sh
zig cc -target aarch64-linux-musl -mcpu=cortex_a53 -Os -static -Wall \
  -D_GNU_SOURCE -DENABLE_GBCONV \
  -Iinclude -I. -Iutil -Iif_impl -Iif_impl/sockraw -Ipacket_plugin \
  -Ipacket_plugin/printer -Ipacket_plugin/rjv3 -Ipacket_plugin/rjv3/rjv3_hashes \
  *.c util/*.c if_impl/if_impl.c if_impl/sockraw/*.c \
  packet_plugin/*.c packet_plugin/printer/*.c packet_plugin/rjv3/*.c \
  packet_plugin/rjv3/rjv3_hashes/*.c \
  -Wl,-T,minieap_init_func.lds -o minieap
```

**二进制必须校验**：`file` 应显示 ARM aarch64 静态链接；`.data.ifimpllist` 应为 8 字节、`.data.pktpluginlist` 为 16 字节（空表说明 `--gc-sections` 吃掉了注册表，见 §7）。

## 6. 发布流程

### 6.1 版本号位置（全部要改）

- `openwrt/luci-app-minieap-sysu/install.sh` — 安装完成提示
- `openwrt/luci-app-minieap-sysu/root/usr/lib/lua/luci/view/minieap_sysu/index.htm` — 页头描述
- `openwrt/luci-app-minieap-sysu/README.md` — 版本行、Release 链接、下载文件名、`/tmp/minieap-luci-vX.Y.Z` 路径
- `README.md` — 版本沿革

### 6.2 提交与打包

```sh
# 1. 改代码 + 跑全部测试
# 2. 重建包并记录哈希
python3 openwrt/luci-app-minieap-sysu/build_bundle.py
# 3. 提交
git add -A && git commit -m "..."
# 4. 打标签并推送（历史上 v1.4.0 / v1.5.1 / v1.5.2 / v1.6.0 都是轻量标签，保持一致）
git tag luci-vX.Y.Z
git push origin main luci-vX.Y.Z
```

### 6.3 Release

附件固定四个（命名必须带版本号）：

```
minieap-sysu-luci-vX.Y.Z.tar.gz          # 页面包
minieap-sysu-luci-vX.Y.Z.tar.gz.sha256   # 内容必须是 "<hash>  minieap-sysu-luci-vX.Y.Z.tar.gz"
minieap-sysu-aarch64-vX.Y.Z              # 二进制
minieap-sysu-aarch64-vX.Y.Z.sha256
```

发布说明必须包含：

1. 本版做了什么 + 适用范围
2. 安装/升级步骤（含 `sha256sum -c`）
3. **校验值**（两个哈希）
4. **源码链接**指向该标签对应的提交
5. 验证范围（哪些在实机验证过、哪些没有——不要夸大）
6. 若替代旧版，写明旧版已被替代

获取 API token（不打印到终端）。WSL / git-bash：

```sh
raw=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill)
tok=$(printf '%s\n' "$raw" | sed -n 's/^password=//p')
```

PowerShell（变量名区分大小写；避免把 token 打到输出里）：

```powershell
$raw = "protocol=https`nhost=github.com`n`n" | git credential fill 2>&1
$tok = (($raw | Select-String '^password=') -replace '^password=','').Trim()
```

### 6.4 预发布与转正

- 尚未实机验证的版本发 `prerelease: true`；验证通过后用 PATCH 改为 `prerelease: false` 并 `make_latest: "true"`。
- **预发布阶段**允许 `git tag -f` 移动标签、删除并重传附件；每次移动后必须同步发布说明里的哈希与源码链接。
- **正式版禁止移动标签**。要改就发新版本，并在旧版说明顶部加"已由 vX.Y.Z 替代"。
- 转正式后，旧版说明顶部标注替代关系，但**不要改动旧版附件**。

### 6.5 发布后自检（必须实际下载验证）

1. 下载两个附件，实测 SHA256 与正文一致
2. 解包检查：`install.sh`、`README.md`、页头的版本号一致
3. 标签 → 提交 与正文源码链接一致
4. 包内 `SHA256SUMS` 逐文件校验无误
5. 若改过 C：从标签重新编译一次，确认哈希与发布的二进制相同

## 7. 已知坑（都是真实踩过的）

1. **`--gc-sections` 吃掉模块注册表**：`minieap_init_func.lds` 里的 `KEEP()` 不能删。删掉后程序能启动，但报"网络驱动插件启用失败"。
2. **失败重试定时器导致 30 秒循环**：`eap_state_machine.c` 里保存重试 alarm 的 id，成功时取消；`restart_auth()` 在已认证状态要直接返回。改这里要重新验证"重新认证只失败一次"的行为。
3. **`nic=` 是唯一事实源**：页面状态、runner、monitor 都从配置读；不要再出现写死的 `eth0`（历史上四处硬编码，v1.6.0 才统一）。
4. **接口过滤四条件缺一不可**：物理（有 `device`）、非网桥（无 `bridge/`）、非桥成员（无 `master`）、非无线（无 `phy80211`）。漏一条会把 `apcli*`（`device` 存在）或 `eth1`（桥成员）放进来。
5. **LuCI 模块缓存**：改完页面不生效时执行 `rm -f /tmp/luci-modulecache/* /tmp/luci-indexcache*; /etc/init.d/uhttpd restart`。
6. **Windows 上的 PowerShell 陷阱**：单引号字符串里 `` `n `` 是字面量；`Set-Content` 会写 CRLF/BOM；变量名大小写不敏感（`$h` 与 `$H` 是同一个）；`git` 把 "repository moved" 写到 stderr，`$ErrorActionPreference='Stop'` 时会误判为失败。
7. **网络**：代理客户端关闭时 git 直连通常可用；代理开启时记得清空 `HTTPS_PROXY` 环境变量或显式设置。推送失败先测 `Test-NetConnection 127.0.0.1 7900`。

## 8. 提交前检查清单

- [ ] 五套测试全绿
- [ ] 版本号四处一致（install.sh / index.htm / 两份 README）
- [ ] 重建页面包，`SHA256SUMS` 自校验通过
- [ ] 改过 C → 重建 aarch64 二进制并核对
- [ ] 文本文件为 LF
- [ ] README 与实际行为一致（不要留过期描述）
- [ ] 发布说明含校验值与源码链接，且与实际下载一致

## 9. 上游与许可

- 认证程序来自 [undefined443/minieap-sysu](https://github.com/undefined443/minieap-sysu)（上游 [updateing/minieap](https://github.com/updateing/minieap)），C 部分遵循根目录 GPL-3.0。
- `openwrt/luci-app-minieap-sysu/` 下的 LuCI 适配代码与脚本为 MIT（见该目录 `LICENSE`）。
- 修改 C 代码时请在提交信息里说明原因与验证方式，便于回溯。
