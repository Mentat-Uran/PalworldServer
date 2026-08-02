# Palworld 本地服务器控制台

## 让自己的电脑成为一个可控、可备份、可恢复的 Palworld 专用服务器

这是一个面向 Windows 用户的本地服务器管理工具：把 Palworld 专用服务器的安装、启动、停止、保存、备份、诊断和受控切换集中到一个本地控制台中。它保护共享存档边界，让 Docker 和 Windows 原生运行时可以二选一使用，同时默认只允许本机访问管理接口。

如果你不想维护一堆互相冲突的启动脚本，又希望在更新或切换运行方式前先保存和备份世界，这个项目就是为这种场景设计的。它不是云托管服务，不会替你租用服务器，也不是 Pocketpair 官方产品。

Palworld、Pocketpair、社区镜像、SteamCMD、Docker Desktop、WebView2、Sakura FRP 和其他第三方服务分别由各自的权利人负责。本项目代码使用 [MIT License](LICENSE)。英文版见 [README.en.md](README.en.md)。

## 功能说明

- 支持 Windows 原生和 Docker Desktop 加 WSL2 两种运行方式；两者互斥，不允许同时运行两个服务端。
- 使用受保护的共享存档边界，切换运行方式前可以创建快照和备份。
- 提供默认只监听本机的网页控制台，用于查看状态、保存世界、创建备份、修改设置、查看日志和诊断问题。
- 正常管理操作使用 REST；RCON 默认关闭，仅作为明确开启的旧版本兼容方式，不是备份、保存或正常停服的依赖。
- 支持受控的启动、停止、保存、公告、玩家管理、备份、恢复、运行时切换和维护检查。
- 支持 `direct`、`community`、`tunnel` 三种网络模式，并可选接入 Sakura FRP 等 UDP 内网穿透服务。
- 提供版本一致性检查、源代码验证、桌面程序构建、安装包构建和脱敏支持包导出工具。
- 默认不记录或提交密码、存档、备份、日志、玩家资料、隧道令牌和其他私有数据。

项目适合愿意阅读说明、能够处理 Windows 权限和网络设置的用户。每个项目目录管理一个服务端；同一台电脑运行多个项目时，为每个项目设置不同的 `PROJECT_INSTANCE_ID` 和端口。不应被宣传成无需理解网络和系统权限的“一键开服”服务。

## 五分钟开始

下面的步骤已经是完整的新手路径，不需要先跳转到其他新手文档。所有命令都在解压后的项目根目录运行。

### 一、准备电脑

首次部署建议优先选择 Windows 原生方式，因为不需要先学习 Docker。无论选择哪种方式，都先看下面的配置需求和安全边界。

1. 从可信来源下载完整发行包 `PalworldServer-<版本>-win-x64.zip`，同时下载同名 `.sha256` 文件并校验哈希。
2. 把压缩包解压到有写入权限的普通目录，不要直接放进受保护的系统目录。
3. 确认电脑满足“电脑配置需求”一节中的基础条件。
4. Windows 原生方式准备 PowerShell 和 WebView2；Docker 方式另外安装 Docker Desktop 和 WSL2。

完整发行包包含项目脚本、网页控制台、桌面宿主、首次配置脚本和文档，但不包含 Palworld 游戏文件、SteamCMD、世界存档、备份或密码。MSI 和桌面压缩包主要用于安装或运行桌面宿主，不能替代完整项目包。

### 二、生成首次配置

最简单的方式是双击项目根目录中的 `FIRST_RUN.bat`。它默认生成 Windows 原生配置；如果准备使用 Docker，可以在命令提示符中运行 `FIRST_RUN.bat docker`。

在项目根目录运行：

```powershell
.\scripts\bootstrap-first-run.ps1 -Runtime windows
```

如果选择 Docker，把参数改成 `-Runtime docker`。脚本会：

- 根据 `.env.example` 创建本地 `.env`；
- 生成随机的管理员密码；
- 创建不包含密码的 `project.json`；
- 不把管理员密码打印到终端。

请在首次配置后立即把管理员密码保存到密码管理器。`.env` 是私有文件，不能上传到 GitHub、Issue、截图或公开支持包。已有 `.env` 时不要直接使用 `-Force`，先备份并确认确实需要重新生成。

### 三、检查主机条件

Windows 原生方式运行：

```powershell
.\scripts\test-host-prerequisites.ps1 -Runtime windows
```

Docker 方式运行：

```powershell
.\scripts\test-host-prerequisites.ps1 -Runtime docker
```

如果检查报告缺少 Docker、WSL2、WebView2、磁盘空间、权限或端口条件，先修复报告中的问题。安装器涉及防火墙时可能需要管理员权限。

### 四、安装 Palworld 服务端文件

Windows 原生方式运行：

```text
install-windows-server.bat
```

也可以在项目根目录打开管理员 PowerShell 后执行：

```powershell
.\scripts\install-win-server.ps1
```

安装器会下载 SteamCMD 和 Palworld Dedicated Server 文件，首次下载可能需要较长时间。重复运行会复用已有文件，并继续执行文件检查、设置编译、存档 Junction 检查和防火墙一致性检查。看到 `PalServer.exe` 不代表所有安装检查都已经完成。

Docker 方式不需要把 Palworld 服务端文件安装到 `win-server`，但必须先启动 Docker Desktop，并启用 WSL2 和 Linux 容器模式。

### 五、启动唯一一个运行时

在批准的维护窗口内启动 Windows 原生方式：

```text
start-windows.bat
```

在批准的维护窗口内启动 Docker 方式：

```text
start-docker.bat
```

启动脚本会先执行受保护的运行时切换，再启动已配置的隧道 provider、网页控制台和日志归档。`TUNNEL_PROVIDER=none` 是安全的空操作，不会启动第三方隧道。

在运行时切换前，两个启动脚本都会先执行只读的主机前置检查：根据目标检查 Docker/WSL2 或 Windows 服务端、磁盘、内存和已配置的隧道可执行文件；检查失败时不会启动运行时或网页控制台。

Docker 和 Windows 原生服务端不能同时运行。首次使用或切换运行时前，先确认没有另一个运行时、另一个 Palworld 进程或占用相同端口的服务。

### 六、打开控制台并完成第一次检查

启动脚本会显示网页控制台的本机地址，也可以使用桌面宿主打开项目目录。控制台首页依次检查：

1. 运行时是否是你想使用的 Windows 原生或 Docker；
2. 服务端进程和本机游戏端口是否可用；
3. REST 管理接口是否可用；
4. 存档路径和运行时状态是否一致；
5. 隧道 provider 是否仅在你明确配置后启动。

第一次正式邀请玩家前，先执行“保存世界”和“创建备份”，并从不在同一局域网的网络进行一次外部加入测试。控制台显示服务端已启动，不能单独证明公网玩家一定可以加入。

## 电脑配置需求

“能够启动”和“符合推荐基线”是两个不同的状态。下面的最低条件只表示可能运行，不代表长时间多人稳定。

| 项目 | 最低或基础条件 | 推荐条件 |
|---|---|---|
| 操作系统 | Windows 10 22H2 或 Windows 11，64 位 | Windows 11，64 位 |
| 处理器 | 没有统一的硬性最低值，人数、模组和世界规模会影响需求 | 四个逻辑核心或以上，并保证系统还有余量 |
| 内存 | 8 GiB 可能启动，但不能视为稳定或推荐配置 | 至少 16 GiB 可用内存 |
| 磁盘 | 安装器预检至少需要 8 GB 可用空间 | 系统、服务端更新、存档和备份合计预留 30 GB 以上 |
| 网络 | 能访问 SteamCMD 和所选依赖 | 稳定的有线网络或高质量 Wi-Fi；公网方式还需要 UDP 可达 |
| Windows 原生依赖 | PowerShell 5.1 或更高、WebView2 Runtime；防火墙修复需要管理员权限 | PowerShell 7 和最新 WebView2 Evergreen Runtime |
| Docker 依赖 | Docker Desktop、WSL2、Linux 容器模式 | 为 WSL2 分配足够的内存和磁盘空间 |
| 游戏服务端文件 | 首次安装会下载约 5 GB 的 Palworld Dedicated Server 文件 | 额外预留更新、临时文件和备份增长空间 |

低于 16 GiB 的电脑可以尝试运行，但不应被描述为满足推荐要求。Docker 的 CPU、内存限制应放在本地且不提交的 `docker-compose.override.yml` 中，不要修改公共默认文件来适配某一台电脑。

## 三种网络模式和端口

### `direct`：路由器直连

这是默认模式。你在路由器上把游戏 UDP 端口转发到运行服务器的电脑，只让玩家访问游戏端口。它不需要第三方内网穿透，但要求你拥有路由器配置权限，并且运营商网络允许入站 UDP。

### `community`：社区列表或公共地址

这个模式用于你明确配置社区参数和公网地址的场景。通常需要设置 `COMMUNITY=true`、`PUBLIC_IP` 和 `PUBLIC_PORT`，还要根据实际服务端版本确认查询端口、密码和平台支持。出现在列表中不等于外网玩家已经能够加入，必须从外部网络实测。

### `tunnel`：UDP 内网穿透

这个模式把本机游戏 UDP 端口映射到穿透服务商分配的远程地址和端口，适合没有公网入站能力的家庭网络。它不应被用来转发网页控制台、REST 或 RCON 管理端口。隧道进程已启动，也不等于外部玩家已经成功连接。

默认游戏端口是 `PORT=8211`，查询端口是 `QUERY_PORT=27015`，实际以本地 `.env` 为准。REST 管理端口默认是 `REST_API_PORT=8212`，RCON 端口默认是 `RCON_PORT=25575`，但 RCON 默认关闭。网页控制台端口由启动脚本选择并写入本地运行标记，实际地址以启动输出为准。

Windows 原生运行时默认使用 `WINDOWS_REST_COMPATIBILITY_MODE=ini-only`，遵循官方 INI 配置。`compat` 仅用于后续验证确实识别旧版 `-restapi` 开关的服务端构建；当前本地构建即使传入该开关也没有监听 8212。

Docker 容器和本机运行时锁默认使用 `PROJECT_INSTANCE_ID=palworld-server`。如果同一台电脑部署第二个项目目录，必须改成另一个 Docker 安全名称，并同时选择不冲突的游戏、REST、RCON 和控制台端口。

管理端口必须保持本机访问。不要把 REST、RCON、网页控制台、Docker 管理接口或含有密码的配置转发到公网。

## Sakura FRP 内网穿透教程

本项目把 Sakura FRP 作为可选 provider，不会默认安装、启动或停止任何第三方隧道程序。Sakura FRP 的节点、版本、配额、计费、客户端行为和网络策略由其官方服务决定。

官方资料：

- [内网穿透基础知识](https://doc.natfrp.com/basics.html)
- [frpc 基本使用指南](https://doc.natfrp.com/frpc/usage.html)
- [frpc 用户手册](https://doc.natfrp.com/frpc/manual)
- [游戏 UDP 穿透常见问题](https://doc.natfrp.com/faq/network.html)
- [官方下载页面](https://www.natfrp.com/tunnel/download)

按下面步骤配置：

1. 在 Sakura FRP 官方客户端或控制台中创建 UDP 隧道。
2. 隧道本地地址填写 `127.0.0.1`，本地端口填写 `.env` 中的 `PORT`，不要填写网页控制台或 REST 端口。
3. 记录 Sakura FRP 分配的远程地址和远程端口；这两个信息提供给外部玩家。
4. 在本地 `.env` 设置：

   ```env
   NETWORK_MODE=tunnel
   TUNNEL_PROVIDER=sakurafrp
   TUNNEL_LOCAL_PORT=8211
   ```

   如果你修改过 `PORT`，`TUNNEL_LOCAL_PORT` 必须与它完全一致。
5. 如果希望本项目尝试启动已经安装好的 Sakura FRP 程序，再填写 `TUNNEL_EXECUTABLE` 和必要的本地启动参数。不要把访问令牌、完整配置或私有节点信息写进 README、Issue、日志、截图或支持包。
6. 运行 `start-windows.bat` 或 `start-docker.bat`。脚本只会按项目记录的 provider 身份管理进程，不会用全局 `taskkill /IM` 终止电脑上的同名程序。
7. 先检查本机服务端进程和 `PORT` 监听，再让不在同一局域网的玩家使用 Sakura FRP 的远程地址和端口测试。

如果外部玩家无法加入，依次检查：隧道协议是否为 UDP、本地端口是否和 `PORT` 一致、远程端口是否填写正确、Palworld 服务端是否实际监听、运营商或节点是否限制 UDP。不要因为控制台显示“隧道已启动”就断定外网已经连通。

其他 provider 的说明在 `providers/` 目录中。默认 provider 是 `none`，也可以使用 `generic-process` 接入其他明确的启动程序。

Provider 选项由 `providers/*/provider.json` 自动发现，不需要修改中央隧道脚本；新增 provider 时只应把公开元数据放入清单，令牌和启动参数留在本机 `.env`。

## 日常使用

### 查看状态

首页可以查看运行时、服务端进程、本机端口、REST 管理接口、日志和隧道 provider 状态。请把这些状态理解为不同层次的证据：

| 看到的状态 | 能证明什么 | 不能证明什么 |
|---|---|---|
| 服务端进程存在 | 本机进程已启动 | 服务端健康、外网可加入、多人稳定 |
| 本机游戏端口监听 | 本机端口可用 | 路由器或隧道已正确转发 |
| 隧道进程运行 | provider 进程已运行 | 外部玩家已成功连接 |
| 外部玩家实际加入 | 这次外部连接成功 | 长时间稳定或备份恢复成功 |

### 保存、备份和修改设置

建议形成固定顺序：

1. 通知在线玩家；
2. 保存世界；
3. 创建带时间的备份；
4. 修改设置、更新或切换运行时；
5. 启动后检查 REST、日志、存档和玩家连接。

公告、玩家管理、优雅停服和保存优先使用 REST。当前 Windows 构建如果没有原生 REST 监听，只有在你明确设置 `ENABLE_LEGACY_RCON=true` 时才会用本机 RCON 兼容回退处理保存和部分玩家操作；REST 与 RCON 都不可用时，切换流程会拒绝停止当前服务器，避免没有确认保存就动存档。

### 切换 Docker 和 Windows 原生

在“运行时切换”前确认：没有其他维护任务、在线玩家已经收到通知、最新备份可用、目标运行时依赖已经安装。项目会使用状态文件、互斥锁和快照阻止两个运行时同时操作同一份存档。切换成功后仍要重新检查服务端、REST、本机端口和外部连接。

### 停止服务器

停止、重启、恢复、更新和切换真实服务器都会影响玩家和存档。只在已批准的维护窗口中执行。项目停止脚本只应管理本项目记录的进程；如果进程身份不匹配，应优先保留并报告异常，不要强行结束系统中的同名程序。

## 备份、更新和恢复

更新前记录当前 Palworld 服务端版本，保存世界并创建备份。`UPDATE_ON_BOOT=false` 是推荐默认值；容器镜像摘要固定，不代表 Palworld 游戏文件版本永远不变。

恢复会修改存档，必须先停止运行时，并完成路径、存档、备份完整性和运行时身份检查。恢复完成后先在本机检查，再决定是否允许外部玩家加入。不要把“备份文件存在”或“恢复命令返回成功”当成完整恢复验收。

## 常见问题

- **找不到项目目录**：选择同时包含 `.env`、`settings-panel.ps1`、`docker-compose.yml` 和 `web\index.html` 的项目根目录，不要选择只包含 MSI 或桌面压缩包的目录。
- **找不到 `PalServer.exe`**：Windows 原生文件还没有安装完成，重新运行 `install-windows-server.bat`，不要直接运行启动脚本。
- **Docker 未运行**：只有 Docker 方式需要 Docker Desktop；打开 Docker Desktop，确认 WSL2 和 Linux 容器模式已启用。
- **WebView2 缺失**：安装 Microsoft Edge WebView2 Evergreen Runtime 后重新打开桌面宿主。
- **端口被占用**：先在维护窗口中确认占用者、运行时身份和配置端口，不要直接杀掉未知进程。
- **外部玩家无法加入**：从不在同一局域网的网络测试；分别检查游戏端口、路由器或 Sakura FRP 的 UDP 映射、远程地址和服务端日志。
- **健康状态未知**：表示控制台暂时无法在有限时间内确认游戏进程健康，不等于服务器一定停止，也不等于远程好友可以加入，应结合日志和进程状态判断。

## 安全和隐私边界

- `.env`、存档、备份、日志、运行时标记、SteamCMD、已安装服务端、隧道凭据、Webhook、玩家资料和公网地址都属于私有数据，不能提交到 GitHub。
- 网页控制台、REST 和 RCON 默认只允许本机管理；远程访问必须经过明确的网络设计和风险评估。
- 不要在没有维护窗口和当前预检的情况下启动、停止、重启、切换、恢复、更新或重建真实服务器。
- 静态检查、历史日志、进程启动、隧道注册和本机端口可用，都不能单独证明外网连通、多人稳定或备份恢复成功。
- 提交公开 Issue 前优先生成脱敏支持包，确认其中没有密码、令牌、玩家身份、存档、备份或完整配置。

## 本地开发、测试和发布

仓库使用 `version.json` 作为唯一版本源。升级版本时运行：

```powershell
.\scripts\bump-version.ps1 -Version 0.2.1
```

本地源代码检查和构建：

```powershell
.\scripts\test-version-consistency.ps1
.\scripts\test-release-policy.ps1
.\scripts\test-first-run-bat.ps1
.\scripts\test-powershell-encoding.ps1
.\scripts\verify-project.ps1 -SkipDocker
.\scripts\test-clean-checkout.ps1
.\scripts\test-desktop-host.ps1
.\scripts\test-desktop-installer.ps1
.\scripts\build-desktop-app.ps1 -SelfContained -Msi -Zip
```

生成并签名完整 Windows 正式发行包：

```powershell
.\scripts\publish-local-release.ps1 -CertificateThumbprint '<40 位证书指纹>'
```

正式发布必须在本地完成测试、构建、Windows Authenticode 签名、签名校验和 SHA-256 校验。上面的脚本会在本地预检证书和 `SignTool.exe`，生成桌面程序、完整源代码包、校验文件和发布清单；它不会打 tag、推送或创建 GitHub Release。完成人工复核后，再手动上传到 GitHub Release。GitHub Actions 只做源代码验证和发布策略检查，不构建、签名、上传或发布正式产物。真实服务器启停、切换、恢复、外网连接和多人稳定性测试必须单独取得维护窗口和证据，不能用静态检查替代。

## 脱敏支持包

提交公开问题前运行：

```powershell
.\scripts\export-support-bundle.ps1
```

支持包应只包含版本、依赖版本、运行时类型、端口摘要、校验结果、错误码和脱敏日志。它不应包含密码、Webhook、公网地址、隧道地址、玩家身份、存档、备份、完整 `.env` 或原始命令文本。

## 深入资料

新手安装、启动、网络和日常操作已经写在本文件中。需要深入排错或参与开发时，再阅读：

- [维护窗口运行手册](docs/maintenance-window-runbook.md)
- [兼容性说明](docs/compatibility.md)
- [架构和证据模型](docs/architecture.md)
- [故障排查](docs/troubleshooting/README.md)
- [贡献指南](CONTRIBUTING.md)
- [安全政策](SECURITY.md)

## 许可证

项目代码使用 [MIT License](LICENSE)。Palworld 游戏软件、社区镜像、SteamCMD、Docker Desktop、WebView2、Sakura FRP 和其他外部服务分别适用其自身的许可证、服务条款和使用限制。
