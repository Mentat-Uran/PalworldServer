# Palworld Server Toolkit

Palworld Server Toolkit is a Windows-oriented, local-first toolkit for operating a self-hosted Palworld dedicated server. It supports a Docker Desktop/WSL2 runtime and a Windows-native runtime that share one protected save layout, plus a local-only Web Console and maintenance scripts.

The project is an operations and safety toolkit, not an official Pocketpair product. Palworld, Pocketpair, community images, and external tunnel services remain the property and responsibility of their respective owners.

## What is included

- Docker Compose and Windows-native server startup paths.
- Runtime switching with state checks, mutex protection, snapshots, and restore-oriented diagnostics.
- A Web Console bound to loopback by default.
- Configuration validation, backups, log archiving, player-session aggregation, and maintenance-readiness checks.
- Optional Windows desktop host for the local Web Console, distributed as both a self-contained portable ZIP and a current-user MSI installer.
- One-click Windows-native server download and validation through `install-windows-server.bat`.

The repository documents source-level behavior and local validation boundaries. A clean checkout or passing static check does not prove Internet reachability, multiplayer stability, disaster recovery, tunnel availability, or production acceptance.

English guide: [English](README.en.md).

第一次使用请直接看[新手上手指南](docs/quick-start.md)。如果你只想了解它能做什么，可先看[社媒宣传文案](docs/social-media-copy.md)中的功能说明。

桌面应用的一句话用法：下载 MSI 或便携 ZIP → 打开应用并选择 PalworldServer 项目目录 → 在本地面板管理服务器。

Windows 原生首次部署的一句话用法：准备项目目录 → 双击 `install-windows-server.bat` → 双击 `start-windows.bat` → 打开桌面应用。

## Quick start

### 先选择使用方式

| 方式 | 适合谁 | 说明 |
|---|---|---|
| MSI 安装包 | 想从开始菜单打开 | 安装到当前用户目录，不需要管理员权限 |
| Portable ZIP | 想解压即用、放 U 盘或当前目录 | 不写入安装注册，不改变项目目录 |

两种包功能相同；它们只提供桌面控制台，不包含 Palworld 游戏文件、世界存档、Docker Desktop 或 WebView2 Runtime。最新包见 [GitHub Releases](https://github.com/Mentat-Uran/PalworldServer/releases/latest)。

### 推荐 Windows 原生路径

如果你拿到的是一台还没有 Docker 的 Windows 电脑，推荐先走 Windows 原生方案：

1. 安装 WebView2 Runtime。
2. 复制 `.env.example` 为 `.env`，把 `ADMIN_PASSWORD` 改成至少 16 位的本机管理密码。
3. 双击项目根目录的 `install-windows-server.bat`。它会下载 SteamCMD 和约 5 GB 的 Palworld Dedicated Server 文件；首次下载需要等待，窗口会显示进度，已有文件会复用。
4. 运行主机检查：

   ```powershell
   .\scripts\test-host-prerequisites.ps1 -Runtime windows
   ```

5. 双击 `start-windows.bat`，再打开桌面应用并选择项目目录。

Docker 是可选路径：安装带 WSL2 的 Docker Desktop 后使用 `start-docker.bat`。Docker 和 Windows 原生服务端不能同时运行。实际操作前请阅读 [`docs/quick-start.md`](docs/quick-start.md)、[`docs/clean-checkout-onboarding.md`](docs/clean-checkout-onboarding.md)、[`docs/compatibility.md`](docs/compatibility.md) 和 [`docs/maintenance-window-runbook.md`](docs/maintenance-window-runbook.md)。

To build the desktop packages locally, run `.\scripts\test-desktop-host.ps1`, `.\scripts\test-desktop-installer.ps1`, and `.\scripts\build-desktop-app.ps1 -SelfContained -Msi -Zip -Version 0.1.1`. The ZIP is portable; the MSI installs the desktop host under the current user's local application directory and adds a Start menu shortcut. Both require the Evergreen WebView2 Runtime.

## Safety and privacy

- Never commit `.env`, save games, backups, live logs, runtime markers, local output, SteamCMD files, installed server binaries, or personal diagnostics.
- Keep the Web Console and management ports on loopback unless an explicit, reviewed network policy says otherwise.
- Do not stop, restart, switch, restore, or rebuild a live server without an approved maintenance window and a current preflight.
- Treat snapshots and historical logs as evidence of files or past events, not as proof of a successful recovery or current external connectivity.
- Do not include passwords, webhook URLs, tunnel credentials, player identifiers, or private server addresses in issues or pull requests.

## Contributing

Read [`AGENTS.md`](AGENTS.md), [`CONTRIBUTING.md`](CONTRIBUTING.md), [`SECURITY.md`](SECURITY.md), and the relevant runbook before changing runtime behavior. Prefer read-only checks, preserve the current runtime identity, and report evidence boundaries honestly.

## License

Project code is released under the [MIT License](LICENSE). Game software, community container images, third-party tools, and external services are separately licensed.
