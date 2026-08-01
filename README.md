# Palworld 本地服务器控制台

这是一个 Windows 优先、默认本地安全的 Palworld 专用服务器管理工具。它支持 Docker Desktop/WSL2 和 Windows 原生两种互斥运行时，共享受保护的存档边界，并提供只监听回环地址的 Web Console、备份、诊断和受控运行时切换。

本项目不是 Pocketpair 官方产品。Palworld、Pocketpair、社区镜像、SteamCMD、Docker Desktop、WebView2 和第三方内网穿透服务分别由各自的权利人负责。

英文说明见 [English](README.en.md)。项目源代码遵循 [MIT License](LICENSE)。

## 五分钟开始

最省事的完整发行包是 `PalworldServer-<版本>-win-x64.zip`。它包含项目脚本、Web Console、桌面宿主、首次配置脚本和文档入口，但不包含 Palworld 游戏文件、SteamCMD、存档、备份或任何密码。

1. 在可信来源下载发行包并校验同名 `.sha256` 文件。
2. 解压到没有特殊权限限制的目录。
3. 双击 `FIRST_RUN.bat`，或在项目根目录运行：

   ```powershell
   .\scripts\bootstrap-first-run.ps1 -Runtime windows
   ```

   脚本会生成 `.env`、强随机管理员密码和不含密码的 `project.json`。密码不会打印到终端，请立即保存到密码管理器。
4. 运行主机检查：

   ```powershell
   .\scripts\test-host-prerequisites.ps1 -Runtime windows
   ```

5. Windows 原生方案双击 `install-windows-server.bat`，完成后在批准的维护窗口内双击 `start-windows.bat`。
6. Docker 方案先安装 Docker Desktop 和 WSL2，再在批准的维护窗口内双击 `start-docker.bat`。
7. 使用桌面宿主或浏览器打开本机 Web Console。Docker 和 Windows 原生服务端不能同时运行。

重复执行安装器会做校验、SteamCMD validate、配置编译、存档 Junction 和防火墙一致性检查，不会因为发现 `PalServer.exe` 就跳过安全检查。

## 电脑配置需求

| 项目 | 最低可启动条件 | 推荐条件 |
|---|---|---|
| 操作系统 | Windows 10 22H2 或 Windows 11 64 位 | Windows 11 64 位 |
| 内存 | 8 GB 可能启动，但不代表稳定或符合推荐基线 | 至少 16 GB 可用内存 |
| 磁盘 | 安装器预检至少需要 8 GB 可用空间 | 系统盘和数据盘预留 30 GB 以上，并为存档和备份留出增长空间 |
| 网络 | 能访问 SteamCMD 和所选镜像/依赖 | 稳定的有线或高质量 Wi-Fi；公网模式还需要 UDP 可达性 |
| Windows 原生依赖 | PowerShell 5.1 或更高、管理员权限用于防火墙、WebView2 Runtime | PowerShell 7、最新 WebView2 Evergreen Runtime |
| Docker 方案依赖 | Docker Desktop、WSL2、Linux 容器模式 | Docker Desktop 使用足够的 WSL2 内存和磁盘配额 |
| 游戏服务端 | 安装器会下载约 5 GB 的 Palworld Dedicated Server 文件 | 额外预留更新、临时文件和备份空间 |

“能够启动”和“符合推荐配置”是两个状态。低于 16 GB 的主机不应被宣传为满足推荐要求；资源限制应放在本机的 `docker-compose.override.yml`，不写入公共默认 Compose 文件。

## 网络模式和端口

`NETWORK_MODE` 有三个互斥模式：

- `direct`：用户自行配置路由器端口转发，只对外提供游戏 UDP 端口 `PORT`。
- `community`：需要完整配置 `COMMUNITY=true`、`PUBLIC_IP` 和 `PUBLIC_PORT`，是否能在列表中出现以及跨平台能否加入仍需从外部网络实测。
- `tunnel`：使用明确选择的 UDP provider，只转发游戏端口，不转发 Web Console、REST 或 RCON。

默认是 `direct`。管理接口默认是 REST 回环端口 `REST_API_PORT=8212`；RCON 默认关闭，且不应通过路由器、隧道或反向代理公开。游戏默认 UDP 端口是 `8211`，查询端口为 `27015`，实际以 `.env` 为准。

控制台会区分以下证据：服务端进程已启动、本机端口可用、隧道进程已启动、外部玩家实际连接。前两项不能单独证明外部玩家可以加入。

### Sakura FRP 内网穿透

本项目可以配合 Sakura FRP 使用，但默认不安装、不启动、不停止任何第三方隧道程序。推荐先阅读 Sakura FRP 官方文档：

- [内网穿透基础知识](https://doc.natfrp.com/basics.html)
- [frpc 基本使用指南](https://doc.natfrp.com/frpc/usage.html)
- [frpc 用户手册](https://doc.natfrp.com/frpc/manual)
- [游戏 UDP 穿透常见问题](https://doc.natfrp.com/faq/network.html)
- [官方下载页面](https://www.natfrp.com/tunnel/download)

基本步骤：

1. 在 Sakura FRP 中创建 UDP 隧道。
2. 本地地址填写 `127.0.0.1`，本地端口填写 `.env` 中的 `PORT`，远程端口使用 Sakura FRP 分配的端口。
3. 在本地 `.env` 设置 `NETWORK_MODE=tunnel`、`TUNNEL_PROVIDER=sakurafrp`，并使 `TUNNEL_LOCAL_PORT` 与 `PORT` 相同。
4. 如果希望本项目尝试启动已安装的启动器，再设置 `TUNNEL_EXECUTABLE`；不要把令牌或完整配置写入 README、Issue、日志或支持包。
5. 只让 Sakura FRP 转发游戏 UDP；不要把 Web Console 的 `8213` 段、REST `8212` 或兼容 RCON 端口加入隧道。
6. 先确认本机游戏端口监听，再让不在同一局域网的玩家用 Sakura FRP 的远程地址和端口测试。控制台显示“隧道已启动”不等于外部连接成功。

Sakura FRP 的版本、节点、计费/配额、网络策略和客户端行为由其官方服务决定；本项目只管理显式记录的 provider PID，不会使用 `taskkill /IM` 终止系统中的同名进程。

其他 provider 使用 `providers/` 下的说明。默认 provider 是 `none`，可使用 `generic-process` 接入其他明确的启动程序。

## 安全边界

- `.env`、存档、备份、日志、运行时标记、SteamCMD、已安装服务端和隧道凭据都属于私有数据，不能提交到 GitHub。
- Web Console、REST 和 RCON 默认只绑定/允许本机管理；管理端口不应通过 Sakura FRP 或路由器公开。
- RCON 已进入兼容模式，正常保存、公告、玩家管理和优雅停服使用官方 REST API。
- 不要在没有维护窗口和当前预检的情况下启动、停止、重启、切换、恢复、更新或重建真实服务器。
- 静态检查、历史日志、进程启动、隧道注册或本机端口可用都不等于外网连通、多人稳定、备份恢复成功或生产验收。

## 备份、升级与恢复

先保存世界，再创建带时间的备份；升级前还要记录当前游戏服务端 build。镜像 digest 固定不等于 Palworld 游戏文件版本固定，因此不要把 `UPDATE_ON_BOOT` 当作无风险自动更新。推荐设置 `UPDATE_ON_BOOT=false`，在维护窗口中执行检查、备份、更新、健康检查和失败回滚。

恢复操作会改变存档，必须停止运行时并执行前置检查。请阅读 [维护窗口运行手册](docs/maintenance-window-runbook.md)、[兼容性说明](docs/compatibility.md) 和 [存档说明](docs/getting-started/saves.md)。

## 本地开发与发布

仓库使用 `version.json` 作为唯一源。升级版本时运行：

```powershell
.\scripts\bump-version.ps1 -Version 0.2.0
```

本地校验和构建：

```powershell
.\scripts\test-version-consistency.ps1
.\scripts\verify-project.ps1 -SkipDocker
.\scripts\test-clean-checkout.ps1
.\scripts\test-desktop-host.ps1
.\scripts\test-desktop-installer.ps1
.\scripts\build-desktop-app.ps1 -SelfContained -Msi -Zip
```

生成完整 Windows 发行包：

```powershell
.\scripts\build-release-bundle.ps1 -DesktopPublishDir .\output\desktop-app\win-x64\Release
```

发布前由维护者在本地完成测试、构建、敏感文件审计和 SHA-256 校验，再一次性推送 GitHub 并创建 Release。GitHub Actions 只做源代码辅助验证，不是本项目的主要发布证明。

## 支持包

提交公开 Issue 前优先生成脱敏支持包：

```powershell
.\scripts\export-support-bundle.ps1
```

支持包只应包含版本、依赖版本、运行时类型、端口摘要、校验结果、错误码和脱敏日志；它不会包含密码、Webhook、公网地址、隧道地址、玩家 ID、存档、备份、完整 `.env` 或原始命令。

## 文档入口

- [快速上手](docs/quick-start.md)
- [安装与首次配置](docs/getting-started/install.md)
- [网络模式](docs/getting-started/networking.md)
- [日常操作](docs/user-guide/daily-operations.md)
- [故障排查](docs/troubleshooting/README.md)
- [架构和证据模型](docs/architecture.md)
- [贡献指南](CONTRIBUTING.md)
- [安全政策](SECURITY.md)

## 许可证

项目代码使用 [MIT License](LICENSE)。游戏软件、社区镜像、第三方工具和外部服务分别适用其自身许可证和服务条款。
