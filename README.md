# MiniEAP-SYSU

[updateing/minieap](https://github.com/updateing/minieap) 的 SYSU 适配版本。

## 这个 fork 做了什么

在 [undefined443/minieap-sysu](https://github.com/undefined443/minieap-sysu) 的基础上加了个 LuCI 页面，方便在路由器后台管理校园网认证，不用每次都在 SSH 敲命令。

入口在 **服务 → 校园网认证**，页面功能：

- 填 NetID 和密码，启动/停止/重新认证
- 看服务状态、网线连接、WAN IP
- 设置开机自动认证
- 查最近的认证日志（自动刷新，5 秒一次）

页面读写的是已有的 `minieap-sysu` 配置和 procd 服务，跟 netifd 版的 `minieap` 包互不干扰。认证程序本身的 C 代码没有改动，跟上游一致。

目前只在 GL-MT3600BE（GL.iNet 4.9.0 / OpenWrt 21.02-SNAPSHOT）的至善园环境验证过。

👉 **安装和详细用法见 [openwrt/luci-app-minieap-sysu/README.md](openwrt/luci-app-minieap-sysu/README.md)**



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
