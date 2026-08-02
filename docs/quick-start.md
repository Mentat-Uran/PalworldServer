# 新手上手指南

这份指南只解决两件事：把服务器跑起来，以及知道日常管理该点哪里。

## 先记住一句话

Palworld Server Toolkit 是一个运行在自己电脑上的服务器控制台。它把启动、停止、设置、保存、备份和运行时切换集中到一个本地面板里；它不是云托管服务，也不是 Pocketpair 官方产品，不会替你租服务器或自动开放公网端口。

它管理的是一个 PalworldServer 项目目录。这个目录里至少要有：

- `.env`：你的本机配置和管理员密码；
- `settings-panel.ps1`：本地控制台后端；
- `docker-compose.yml`：Docker 运行方式；
- `web\index.html`：控制台页面。

## 该下载哪个包

| 你想要的方式 | 下载 | 使用方法 |
|---|---|---|
| 安装到电脑、以后从开始菜单打开 | `PalworldServerConsole-*.msi` | 双击安装，安装后从开始菜单打开 |
| 不安装、不写入注册表，放 U 盘或当前目录使用 | `PalworldServerConsole-*.zip` | 解压后直接运行 `PalworldServerConsole.exe` |

两种包功能相同。MSI 只安装桌面控制台，不包含 Palworld 游戏文件、世界存档、Docker Desktop 或 WebView2 Runtime。

## 推荐的第一次部署路径：Windows 原生

如果你刚拿到一台没有 Docker 的 Windows 电脑，优先使用 Windows 原生方案：

1. 安装 Microsoft Edge WebView2 Runtime。
2. 准备一个固定的 PalworldServer 项目目录。没有 `.env` 时，复制 `.env.example` 为 `.env`，把 `ADMIN_PASSWORD` 改成至少 16 位的本机管理密码。
3. 双击项目根目录的 `install-windows-server.bat`。它会自动下载 SteamCMD 和约 5 GB 的 Palworld Dedicated Server 文件；窗口会显示进度，首次下载需要等待，不能保证瞬间完成。已有文件会复用，不需要每次重新下载。
4. 下载完成后，运行一次：

   ```powershell
   .\scripts\test-host-prerequisites.ps1 -Runtime windows
   ```

5. 双击 `start-windows.bat`。启动前会先检查 Windows 服务端、磁盘、内存、端口网络配置和已配置的隧道 Provider；检查失败时不会切换运行时或启动 Web Console。
6. 打开桌面应用。第一次启动点击左上角“选择服务器目录…”，选第 2 步的项目目录。以后应用会记住这个目录。
7. 在控制台首页先看“运行时状态”。日常操作建议按“保存世界 → 创建备份 → 再修改设置、重启或切换”的顺序。

Docker 是可选路径：安装 Docker Desktop 并启用 WSL2，复制并填写 `.env` 后运行 `start-docker.bat`。它会先检查 Docker/WSL2、磁盘、内存和 Provider；Docker 和 Windows 原生服务端不能同时运行。

## 日常只需要知道这几个位置

| 想做什么 | 去哪里 |
|---|---|
| 看服务器是否运行 | 首页的“运行时状态” |
| 改服务器设置 | “设置” → 修改字段 → “保存并重启” |
| 先保存当前世界 | 首页的“保存世界” |
| 创建可恢复的本地备份 | 首页的“创建备份”或“备份”页面 |
| 在 Docker 与 Windows 原生之间切换 | “运行时切换”页面；切换前会创建快照并要求确认 |
| 查看玩家、日志和故障线索 | “玩家”“日志”页面 |

## 最常见的提示怎么处理

- **找不到项目目录**：选择包含 `.env`、`settings-panel.ps1`、`docker-compose.yml` 和 `web\index.html` 的目录，不要选择只包含 MSI 或 ZIP 的下载目录。
- **下载没有开始**：确认项目路径没有特殊权限限制，保持 BAT 窗口打开；重新双击 `install-windows-server.bat` 会复用已下载的文件。
- **Docker 未运行**：只有选择 Docker 路径时才需要 Docker Desktop；Windows 原生路径不依赖 Docker。
- **找不到 `PalServer.exe`**：Windows 原生文件还没有下载完成；重新双击 `install-windows-server.bat`，不要直接运行 `start-windows.bat`。
- **WebView2 缺失**：安装 Microsoft Edge WebView2 Evergreen Runtime 后重新打开桌面应用。
- **健康状态未知**：这只表示当前面板无法在有限时间内确认游戏进程健康，不等于远程好友已经可以加入；先查看“日志”和“运行时状态”。

## 安全边界

Web Console 默认只监听本机回环地址。不要把 REST、RCON、Docker 或 Web Console 端口直接暴露到公网；隧道显示“已启动”也不等于外部玩家已经成功加入。停止、重启、切换、恢复和更新真实服务器前，先通知在线玩家并确认有可用备份。
