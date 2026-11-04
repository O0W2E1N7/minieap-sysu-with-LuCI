# MiniEAP-SYSU

[updateing/minieap](https://github.com/updateing/minieap) 的 SYSU 适配版本。

## 此 fork：至善园 LuCI 校园网认证页面

此 fork 在 [undefined443/minieap-sysu](https://github.com/undefined443/minieap-sysu)
基础上增加了适配 GL.iNet GL-MT3600BE 原厂固件的 LuCI 页面，入口为
**服务 → 校园网认证**。v1.4.0 增加每 5 秒自动刷新、最近认证日志、保存并重新认证、
更换账号时的新密码校验，以及前后端防重复提交。仍可修改 NetID/密码、启动/停止/重新认证、
设置开机启动，并查看服务、网线和 WAN IPv4 状态。认证程序的 C 源码保持上游版本。

页面适配既有的 `minieap-sysu` procd 服务和 `/etc/minieap-sysu.conf`，
不直接接管 netifd 版本的 `minieap` 软件包。已在 GL.iNet 4.9.0 / OpenWrt
21.02-SNAPSHOT 的至善园环境确认旧版页面保存可用；v1.4.0 新功能通过本地回归测试，
仍需实机验证。

**[安装说明、配置方法和故障排查](openwrt/luci-app-minieap-sysu/README.md)**

包含 `nixio.open` 文件权限与 LuCI 编译缓存的修复，以及对应回归测试。
本仓库提供源码、空白配置示例和通用服务脚本。

## Build

> 如果目的是在 OpenWrt 上使用 minieap 认证校园网，建议移步 [openwrt-minieap-sysu](https://github.com/undefined443/openwrt-minieap-sysu)（MiniEAP IPK 软件包）和 [luci-app-minieap](https://github.com/kongfl888/luci-app-minieap)（MiniEAP LuCI 插件），它们对 OpenWrt 提供了专门适配。

1. 根据路由器型号（model）查找对应的 CPU 平台：[OpenWrt Table of Hardware](https://toh.openwrt.org/)

2. 根据 CPU 平台选择对应的 SDK 镜像：

   - [openwrt/sdk](https://hub.docker.com/r/openwrt/sdk/tags)
   - [immortalwrt/sdk](https://hub.docker.com/r/immortalwrt/sdk/tags)

   ```sh
   IMAGE="docker.io/immortalwrt/sdk:mediatek-filogic-24.10-SNAPSHOT"
   ```

3. 配置 CC 路径：

   ```sh
   TOOLCHAIN=$(docker run --rm $IMAGE sh -c 'realpath $(find staging_dir -name "*openwrt-linux-gcc")')
   sed -i "s|gcc|$TOOLCHAIN|" config.mk
   ```

3. 构建：

   ```sh
   docker run -v "$(pwd):/minieap" -w /minieap -u root --rm $IMAGE make
   ```

## Usage

```sh
./minieap -u <username> -p <password>
```
