# MiniEAP-SYSU

[updateing/minieap](https://github.com/updateing/minieap) 的 SYSU 适配版本。

## 这个 fork 做了什么

在 [undefined443/minieap-sysu](https://github.com/undefined443/minieap-sysu) 的基础上加了个 LuCI 页面，方便在路由器后台管理校园网认证，不用每次都在 SSH 敲命令。

版本沿革：v1.4.0 增加每 5 秒自动刷新、最近认证日志、保存并重新认证、更换账号时的新密码校验，以及前后端防重复提交；v1.4.1 调整状态区间距并支持窄屏换行；v1.5.1 增加本次连接计时、最近 200 条完整日志、全部日志下载和可关闭的一次性操作提示。

入口在 **服务 → 校园网认证**，页面功能：

- 填 NetID 和密码，启动/停止/重新认证；同一账号密码留空即保留原密码，更换账号必须填写新密码
- 看服务状态、校园网网口链路、WAN IPv4 地址与接口状态
- 显示本次连续连接时长：认证成功开始计时，掉线、停止或重新认证结束
- 设置开机自动认证
- 查看最近 200 条完整认证日志（每 5 秒自动刷新），可一键下载全部认证日志
- 操作结果只提示一次且可手动关闭；提交后防重复提交

页面读写的是已有的 `minieap-sysu` 配置和 procd 服务，跟 netifd 版的 `minieap` 包互不干扰。
认证程序源码在根提交导入后未再修改，本仓库后续改动都在 `openwrt/luci-app-minieap-sysu/` 内。

目前只在 GL-MT3600BE（GL.iNet 4.9.0 / OpenWrt 21.02-SNAPSHOT）的至善园环境完成部署验证；
v1.4.0 起的新功能仅在本地模拟环境测试，尚未在该路由器实机验证。

👉 **安装和详细用法见 [openwrt/luci-app-minieap-sysu/README.md](openwrt/luci-app-minieap-sysu/README.md)**，现成安装包在 [Releases](https://github.com/O0W2E1N7/minieap-sysu-with-LuCI/releases)。

## Build

> 如果目的是在 OpenWrt 上使用 minieap 认证校园网，建议移步 [openwrt-minieap-sysu](https://github.com/undefined443/openwrt-minieap-sysu)（MiniEAP IPK 软件包）和 [luci-app-minieap](https://github.com/kongfl888/luci-app-minieap)（MiniEAP LuCI 插件），它们对 OpenWrt 提供了专门适配。

1. 根据路由器型号（model）查找对应的 CPU 平台：[OpenWrt Table of Hardware](https://toh.openwrt.org/)

2. 根据 CPU 平台选择对应的 SDK 镜像：

   - [openwrt/sdk](https://hub.docker.com/r/openwrt/sdk/tags)
   - [immortalwrt/sdk](https://hub.docker.com/r/immortalwrt/sdk/tags)

3. 配置 CC 路径并构建。`IMAGE` 只在该 shell 内有效，所以下面几条命令要在同一个 shell 中执行：

   ```sh
   IMAGE="docker.io/immortalwrt/sdk:mediatek-filogic-24.10-SNAPSHOT"

   TOOLCHAIN=$(docker run --rm $IMAGE sh -c 'realpath $(find staging_dir -name "*openwrt-linux-gcc")')
   sed -i "s|gcc|$TOOLCHAIN|" config.mk

   docker run -v "$(pwd):/minieap" -w /minieap -u root --rm $IMAGE make
   ```

## Usage

```sh
./minieap -u <username> -p <password>
```
