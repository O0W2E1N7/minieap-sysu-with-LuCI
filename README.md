# MiniEAP-SYSU

[updateing/minieap](https://github.com/updateing/minieap) 的 SYSU 适配版本。

## 这个 fork 做了什么

在 [undefined443/minieap-sysu](https://github.com/undefined443/minieap-sysu) 的基础上加了个 LuCI 页面，方便在路由器后台管理校园网认证，不用每次都在 SSH 敲命令。

版本沿革：v1.4.0 增加每 5 秒自动刷新、最近认证日志、保存并重新认证、更换账号时的新密码校验，以及前后端防重复提交；v1.4.1 调整状态区间距并支持窄屏换行；v1.5.1 增加本次连接计时、最近 200 条完整日志、全部日志下载和可关闭的一次性操作提示；v1.5.2 把状态摘要移到页首，日志默认折叠重复行，并改进提示条与提交反馈；v1.6.0 支持在页面选择认证网卡，运行时组件统一按配置里的 `nic=` 工作。

入口在 **服务 → 校园网认证**，页面功能：

- 填 NetID 和密码，启动/停止/重新认证；同一账号密码留空即保留原密码，更换账号必须填写新密码
- 看服务状态、校园网网口链路、WAN IPv4 地址与接口状态
- 显示本次连续连接时长：认证成功开始计时，掉线、停止或重新认证结束
- 设置开机自动认证
- 选择认证网卡：扫描接口后默认只列独立物理口，桥接、桥成员与无线接口需手动展开
- 查看最近 200 条完整认证日志（每 5 秒自动刷新），可一键下载全部认证日志；默认折叠连续重复的心跳行
- 操作结果只提示一次且可手动关闭；提交后防重复提交

页面读写的是已有的 `minieap-sysu` 配置和 procd 服务，跟 netifd 版的 `minieap` 包互不干扰。
本仓库在根提交导入上游认证程序源码后，先只改 `openwrt/` 下的页面；v1.5.2 起另含两处认证程序修复（见下文）。

页面、认证程序（v1.5.2 的两处 C 修复）与 v1.6.0 的网卡选择都已在 GL-MT3600BE
（GL.iNet 4.9.0 / OpenWrt 21.02-SNAPSHOT）实机验证；该设备只有一个可作认证口的物理网口，
多网口设备上的切换效果仍需自行验证。

👉 **安装和详细用法见 [openwrt/luci-app-minieap-sysu/README.md](openwrt/luci-app-minieap-sysu/README.md)**，现成安装包在 [Releases](https://github.com/O0W2E1N7/minieap-sysu-with-LuCI/releases)（页面包与可选的已修复认证程序二进制各带 SHA256）。

## 认证程序修复

本仓库在 `openwrt/` 之外还修了两个认证程序缺陷，源码见 `eap_state_machine.c` 与 `minieap_init_func.lds`：

- **失败重试定时器未取消**：一次认证失败会排一个 30 秒重试 alarm；若服务器在此期间主动重新认证并成功，这个 alarm 仍会触发，于是在已在线状态下再次发起认证，被服务端判为重复登录，形成“成功 → 掉线 → 重试 → 成功”的 30 秒循环。修复后认证成功会取消该 alarm，回调在已认证状态直接返回，并且同一时刻只保留一个待触发重试。
- **模块注册表被链接器回收**：`minieap_init_func.lds` 没有对 if_impl 与插件注册表使用 `KEEP()`，启用 `--gc-sections` 的工具链会把它们当垃圾回收，编出的程序启动即报“网络驱动插件启用失败”。

Releases 中提供按本仓库源码构建的 aarch64 静态二进制 `minieap-sysu-aarch64-v1.6.0`，替换 `/usr/sbin/minieap-sysu` 即生效，替换与回退步骤见该 Release 说明。该二进制已在 GL-MT3600BE 实机验证：重新认证只会出现一次失败，之后不再循环。

## Build

> 如果目的是在 OpenWrt 上使用 minieap 认证校园网，建议移步 [openwrt-minieap-sysu](https://github.com/undefined443/openwrt-minieap-sysu)（MiniEAP IPK 软件包）和 [luci-app-minieap](https://github.com/kongfl888/luci-app-minieap)（MiniEAP LuCI 插件），它们对 OpenWrt 提供了专门适配。

1. 根据路由器型号（model）查找对应的 CPU 平台：[OpenWrt Table of Hardware](https://toh.openwrt.org/)

2. 根据 CPU 平台选择对应的 SDK 镜像：

   - [openwrt/sdk](https://hub.docker.com/r/openwrt/sdk/tags)
   - [immortalwrt/sdk](https://hub.docker.com/r/immortalwrt/sdk/tags)

3. 用 SDK 内的交叉工具链构建。`IMAGE` 只在该 shell 内有效，所以下面几条命令要在同一个 shell 中执行；
   `CC=` 直接覆盖 `config.mk` 里的默认值，不必改文件：

   ```sh
   IMAGE="docker.io/immortalwrt/sdk:mediatek-filogic-24.10-SNAPSHOT"

   TOOLCHAIN=$(docker run --rm $IMAGE sh -c 'realpath $(find staging_dir -name "*openwrt-linux-gcc")')
   docker run -v "$(pwd):/minieap" -w /minieap -u root --rm $IMAGE \
     make CC="$TOOLCHAIN" STATIC_BUILD=true CFLAGS="-Os"
   ```

### 用 Zig 交叉编译（不需要 Docker）

Releases 里的 `minieap-sysu-aarch64-v1.6.0` 就是这样构建的。需要 Linux/macOS 或 WSL 主机，
因为 Makefile 只在 Linux 主机上加链接脚本 `-T minieap_init_func.lds`：

```sh
make -j2 CC="zig cc -target aarch64-linux-musl -mcpu=cortex_a53" CFLAGS="-Os" STATIC_BUILD=true
```

产物为静态链接的 `minieap`，可直接用于 musl 固件，不依赖路由器上的 libc 版本。
链接脚本里两处注册表已加 `KEEP()`，因此即使工具链默认启用 `--gc-sections` 也不会丢掉 if_impl 与插件注册表。

## Usage

```sh
./minieap -u <username> -p <password>
```
