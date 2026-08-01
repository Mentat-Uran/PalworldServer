# Palworld 官方服务器规范与本项目适配

> 状态：生效  
> 官方文档入口：<https://docs.palworldgame.com/>  
> 官网显示文档版本：`1.0.0`  
> 本次核验日期：2026-07-28  
> 当前游戏服务端版本：`v1.0.2.101103`（2026-07-31 本地 Docker/Windows 回归观测）

## 1. 目的与证据边界

本文把 Palworld 官方服务器指南转换为本项目可执行的部署、配置、运维、安全和变更规范。它不是官网全文副本，也不替代更新后的官方文档。

规则来源优先级：

1. Palworld 官方服务器指南。
2. Pocketpair 官方 Docker 仓库及官方发布说明。
3. 当前游戏服务端实际输出、REST API 和生成后的配置。
4. 社区镜像文档。
5. 本项目历史设计与经验记录。

当来源冲突时，必须记录冲突和适用版本，不得用社区镜像行为覆盖官方语义，也不得把“当前能运行”写成“符合官方推荐”。

官方文档描述的是 Pocketpair 的官方启动和操作方案，不排除社区容器通过适配层正确实现相同的服务端语义。当前项目继续使用已经部署、验证并固定镜像摘要的社区容器；与官方启动方式不同只表示存在实现差异，不自动构成错误，也不要求立即迁移。官方方案保留为排障基准和社区方案失效时的回退路径。

本文使用以下规范词：

- **必须**：安全、数据完整性或官方兼容性的硬性要求。
- **应当**：默认执行，只有记录充分理由后才可偏离。
- **可以**：按实际需求选择。
- **禁止**：当前项目中不得执行。

## 2. 官方文档覆盖范围

| 主题 | 官方页面 | 本项目用途 |
|---|---|---|
| 服务器类型 | <https://docs.palworldgame.com/getting-started/about-server/> | Dedicated / Community 选择与跨平台边界 |
| 硬件和部署方式 | <https://docs.palworldgame.com/getting-started/requirements/> | CPU、内存、SSD、网络和 Docker 风险 |
| Dedicated 部署 | <https://docs.palworldgame.com/getting-started/deploy-dedicated-server/> | SteamCMD App ID、Windows/Linux 启动方式 |
| Community 部署 | <https://docs.palworldgame.com/getting-started/deploy-community-server/> | `-publiclobby`、Hairpin NAT 限制 |
| 客户端连接 | <https://docs.palworldgame.com/getting-started/connect-server/> | IP:端口直连与服务器列表 |
| 启动参数 | <https://docs.palworldgame.com/settings-and-operation/arguments/> | 端口、人数、公开地址、日志和性能参数 |
| 配置参数 | <https://docs.palworldgame.com/settings-and-operation/configuration/> | `PalWorldSettings.ini` 路径和参数语义 |
| 管理命令 | <https://docs.palworldgame.com/settings-and-operation/commands/> | 游戏内管理、保存和停服 |
| 服务端 Mod | <https://docs.palworldgame.com/settings-and-operation/mod/> | Windows-only、Workshop 结构和更新规则 |
| PvP | <https://docs.palworldgame.com/settings-and-operation/pvp/> | 试验功能、启用条件和关联参数 |
| Technology ID | <https://docs.palworldgame.com/settings-and-operation/technologyids/> | `DenyTechnologyList` 的官方 ID 来源 |
| RCON | <https://docs.palworldgame.com/api/rcon/> | 弃用状态、局域网限制和兼容性问题 |
| REST API | <https://docs.palworldgame.com/category/rest-api/> | 本地管理接口、认证、端点与敏感数据 |
| 官方 Docker | <https://github.com/pocketpairjp/palworld-dedicated-server-docker> | 官方镜像、Compose 示例和更新流程 |

## 3. 部署基线

### 3.1 官方最低条件

官方当前给出的运行条件：

- CPU：4 核以上。
- 内存：16 GB；较大服务器推荐超过 32 GB。8 GB 可以启动，但更容易因内存不足崩溃。
- 网络：默认 UDP `8211`，可修改；传统公网部署需要路由器端口转发。
- 存储：推荐高性能 SSD；低性能存储可能造成存档损坏。
- 系统：Windows 64 位或 Linux 64 位。

本项目主机为 8 核 16 线程、48 GB RAM 和 NVMe SSD，主机资源符合要求；但是容器内存上限只有 8 GB，低于官方公布的 16 GB。当前健康运行只能证明现有负载可用，不能证明达到官方容量基线。

### 3.2 Docker Desktop 和镜像选择

官方指南把 Docker Desktop 部署标为不推荐/弃用路径，原因是磁盘读写受限会提高存档损坏或故障风险。Pocketpair 已提供官方 Docker 镜像和 Compose 示例，但官方仓库仍不推荐在 Windows/macOS 的 Docker Desktop 上运行。

当前项目存在两个明确偏差：

1. 使用 Windows Docker Desktop + WSL2，并把项目目录下的 `data` 挂载到容器 `/palworld`。
2. 使用固定摘要的社区镜像 `thijsvanloef/palworld-server-docker`，不是 Pocketpair 官方镜像。

这两个差异属于已知并接受的项目决策，不代表当前部署错误，也不触发主动迁移。当前方案继续使用 NVMe 存储、双层备份、优雅停服、镜像摘要固定和健康检查控制风险。只有出现下列触发条件时，才转向官方方案进行迁移评估：

- 社区镜像停止维护，无法支持当前 Palworld 版本。
- Docker Desktop 或镜像导致可重复的启动、更新、性能或存档问题。
- 社区镜像行为无法与官方配置、REST、存档或 Mod 语义对齐。
- 修复社区方案的成本或风险高于迁移成本。
- 用户明确决定采用官方 Windows、SteamCMD 或官方 Docker 路径。

迁移前仍必须完成存档备份、恢复验证和回退方案。官方对 Docker Desktop 的风险提示继续保留，但它是监控和决策依据，不是当前部署失败的结论。

### 3.3 Dedicated 与 Community

- Dedicated server 使用 IP 地址和端口直连，不要求游戏客户端持续运行。
- Community server 本质上仍是 dedicated server，但会注册到游戏内服务器列表。
- Steam、Xbox / Microsoft Store、macOS 和 PS5 属于官方列出的跨平台范围。
- Xbox 和 PS5 玩家需要 Community server；仅配置 `CrossplayPlatforms` 不会让私有 Dedicated server 自动出现在其服务器列表。
- Community 模式使用 `-publiclobby`。
- 路由器不支持 Hairpin NAT 时，同一局域网内的玩家可能无法通过公网 Community 地址回连。

本项目当前 `COMMUNITY=false`，通过 `IP:端口` 直连和 SakuraFrp UDP 隧道使用。若以后需要 Xbox 或 PS5 玩家加入，必须单独评估 Community 模式、公开地址和隧道兼容性。

## 4. 安装、启动和更新规范

### 4.1 官方安装标识

SteamCMD 下载 Dedicated Server 使用 App ID `2394010`：

```text
steamcmd +login anonymous +app_update 2394010 validate +quit
```

Windows 原生入口为 `PalServer.exe`，Linux 原生入口为 `PalServer.sh`。

### 4.2 启动参数

官方列出的主要参数：

| 参数 | 语义 |
|---|---|
| `-port=8211` | 实际监听端口 |
| `-players=32` | 最大玩家数 |
| `-publiclobby` | 注册为 Community server |
| `-publicip=x.x.x.x` | Community server 对外公布的 IP |
| `-publicport=xxxx` | Community server 对外公布的端口，不改变实际监听端口 |
| `-logformat=text` | 日志格式，可为 Text 或 Json |
| `-NumberOfWorkerThreadsServer=X` | 配合旧多线程参数使用的工作线程数 |

对于 `-useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS`，官网明确提示在 v1.0 以后不设置反而可能提升性能。不得沿用旧经验无条件启用；任何调整必须进行相同玩家数、相同世界的前后对比。

### 4.3 更新

每次计划更新必须：

1. 确认当前在线玩家并安排维护窗口。
2. 执行世界保存。
3. 创建独立、可识别时间和版本的备份。
4. 优雅停止服务端。
5. 更新服务端或镜像。
6. 启动并等待健康检查通过。
7. 核对 REST `info`、`settings`、`players`，执行一次 `save`。
8. 检查 UDP `8211`、本地管理端口和日志。
9. 在未完成恢复演练前保留升级前备份，不提前清理。

当前模板 `UPDATE_ON_BOOT=false`，不会默认在容器启动时更新游戏服务端文件。镜像摘要固定并不等于游戏版本固定；维护窗口内如需更新，必须先创建新备份。

## 5. 配置文件规范

### 5.1 正确配置位置

配置目录只会在服务器首次启动后生成。必须从 `DefaultPalWorldSettings.ini` 复制默认配置，然后编辑运行时文件：

- Windows：`Pal\Saved\Config\WindowsServer\PalWorldSettings.ini`
- Linux：`Pal\Saved\Config\LinuxServer\PalWorldSettings.ini`

编辑 `DefaultPalWorldSettings.ini` 本身不会生效。

本项目容器运行 Linux 服务端，实际配置位于：

```text
<project-root>\data\Pal\Saved\Config\LinuxServer\PalWorldSettings.ini
```

项目通过社区镜像的 `.env` 生成该文件。每次改动后必须检查生成后的 INI 或 REST `settings`，不能只根据 `.env` 认定配置已生效。

### 5.2 参数变更原则

- `AllowConnectPlatform` 在当前版本不可用，必须使用 `CrossplayPlatforms`。
- `AdminPassword` 和 `ServerPassword` 是敏感信息，不得写入文档、日志、截图或 API 响应。
- `PublicPort` 只表示 Community server 公布的端口，不会改变监听端口。
- 提高 `BaseCampMaxNumInGuild`、`BaseCampWorkerMaxNum`、`PalSpawnNumRate` 等参数会增加负载。
- `MaxBuildingLimitNum=0` 表示无限制；大量建筑可能增加服务器压力。
- 启用 `bIsUseBackupSaveData` 会增加磁盘负载。
- 保留或已弃用参数不得在缺少当前版本证据时启用。
- 重大平衡、PvP、Hardcore、随机化、跨平台或存档相关参数必须由用户明确决定。

### 5.3 两层备份不能混淆

官方 `bIsUseBackupSaveData=True` 会在世界存档目录建立内置备份，官方列出的保留节奏为：

- 每 30 秒 5 份。
- 每 10 分钟 6 份。
- 每小时 12 份。
- 每天 7 份。

本项目同时使用社区镜像每日 `04:00` 的 tar.gz 备份。这是两个不同系统：

- 游戏内置备份适合短时间回退。
- 容器定时归档适合独立文件保留。

任何“备份已验证”结论必须区分创建、完整性检查和真实恢复演练。目前只验证了创建，完整恢复仍待测试。

## 6. 管理命令规范

游戏内命令需要先在配置中设置 `AdminPassword`，再通过 `/AdminPassword <password>` 获取管理员权限。

| 风险等级 | 命令 | 项目规范 |
|---|---|---|
| 只读 | `/ShowPlayers`、`/Info` | 可用于诊断 |
| 低风险 | `/Broadcast`、`/Save` | 广播需确认内容；维护前必须保存 |
| 管理变更 | `/KickPlayer`、`/BanPlayer`、`/UnBanPlayer` | 必须使用已核对的用户 ID，并记录原因 |
| 玩家位置变更 | `/TeleportToPlayer`、`/TeleportToMe`、`/ToggleSpectate` | 仅在明确管理场景使用 |
| 停服 | `/Shutdown` | 必须先保存并通知玩家 |
| 强制停止 | `/DoExit` | 禁止作为正常停服方法，只能用于服务已失控且优雅方法失败的应急场景 |

本项目正常停服使用 `docker compose stop -t 120`，让容器执行优雅关闭；不得用任务管理器强杀、Docker kill 或 REST `/stop` 替代日常停服。

## 7. REST API 规范

官网当前列出的 REST API 版本为 `v0.2.0.0`，要求 `RESTAPIEnabled=True`，使用 HTTP Basic Authentication。

强制安全规则：

- REST API 禁止直接发布到互联网。
- 只允许容器内部、宿主机 loopback 或可信 LAN 使用。
- 管理密码不得出现在 URL、日志或前端响应中。
- `/players` 含用户 ID、IP、位置和等级；`/game-data` 含世界角色、位置、公会和所有者信息，必须按敏感管理数据处理。
- 自动化必须设置超时、检查 HTTP 状态并限制响应大小。
- 修改类操作必须记录操作者、目标、结果和时间。

官方端点：

| 方法 | 路径 | 用途 | 风险 |
|---|---|---|---|
| GET | `/info` | 版本、服务器名、世界 GUID | 低 |
| GET | `/players` | 在线玩家、ID、IP、位置和状态 | 敏感 |
| GET | `/settings` | 当前服务器设置 | 中 |
| GET | `/metrics` | FPS、玩家数、帧时间、运行时间、基地数 | 低 |
| GET | `/game-data` | 世界角色和 PalBox 快照 | 高敏感、大响应 |
| POST | `/announce` | 全服广播 | 管理变更 |
| POST | `/kick` | 踢出用户 | 管理变更 |
| POST | `/ban` | 封禁用户 | 高风险 |
| POST | `/unban` | 解除封禁 | 高风险 |
| POST | `/save` | 保存世界 | 低风险、维护必需 |
| POST | `/shutdown` | 延时并通知后停服 | 高风险 |
| POST | `/stop` | 强制停止 | 应急专用 |

本项目把 REST 管理端口只绑定到宿主机回环地址；Web Console 和本机脚本使用 REST。新增功能必须优先使用 REST，不得新增 RCON 依赖。

## 8. RCON 规范

官方已经把 RCON 标记为 deprecated，并说明会在后续更新停止工作。官方同时指出：

- RCON 不应直接暴露到互联网，推荐只在 LAN 使用。
- 含中文、日文等多字节字符的玩家名可能被截断；需要这类字符时应使用 REST。

本项目暂时保留显式启用的 RCON 兼容终端，并只允许回环访问。默认配置关闭 RCON。规则：

- 新功能禁止以 RCON 为首选实现。
- REST 能完成的操作必须使用 REST。
- 不得通过 SakuraFrp、防火墙公网规则、反向代理或路由器映射公开 RCON。
- RCON 停止工作不应阻断保存、玩家查询、备份或优雅停服。

## 9. Mod 规范

官方当前只支持 Windows dedicated server 的服务端 Mod，并警告 Mod 可能造成崩溃或存档损坏。

启用条件：

1. 运行时必须是 Windows dedicated server。
2. `Info.json` 必须直接位于 Workshop 项目目录。
3. `PackageName` 来自 `Info.json`，不是文件夹名。
4. `InstallRules` 必须包含 `IsServer=true`。
5. 依赖 Mod 必须完整。
6. `Mods\PalModSettings.ini` 设置 `bGlobalEnableMod=true`，每个启用包使用独立的 `ActiveModList=`。
7. 修改后必须重启，由服务器根据 `InstallRules` 部署。

更新与移除：

- `Info.json` 中 `Version` 改变后，重启会卸载旧版本并重新部署。
- 禁用时从 `ActiveModList` 移除；需要时删除对应 Workshop 目录，再重启。
- `-NoMods` 可以强制禁用全部 Mod。

当前项目是 Linux Docker，因此 Mod 管理器必须保持 fail-closed。`bAllowClientMod=true` 只表示允许启用了客户端 Mod 的玩家加入，不代表服务器安装了 Mod；如果以后要求严格纯净客户端，应单独把该值改为 `false`。

## 10. PvP 与 Technology ID 规范

官方把 PvP 标为试验功能且不在支持范围内。启用 PvP 至少同时需要：

```text
bIsPvP=True
bEnablePlayerToPlayerDamage=True
bEnableDefenseOtherGuildPlayer=True
```

PvP 会改变伤害、基地防御、箱子访问、建筑距离、战斗状态、快速旅行和多项平衡行为。没有用户明确授权、升级前备份和多人测试时，禁止启用。

`DenyTechnologyList` 只能使用官网 Technology ID 页面中的标识。不得凭显示名称、旧版本列表或第三方帖子猜测 ID。

当前项目三项 PvP 开关均为 `false`，符合默认非 PvP 决策。

## 11. 网络与暴露面

允许的外部入口只有：

- Palworld 游戏流量：UDP `8211`。
- SakuraFrp：仅映射本机 `127.0.0.1:8211` 到远程 UDP 端口。

禁止公开：

- REST TCP `8212`。
- Web Console 的本机 TCP 监听端口（首选 `8213`，被占用时可能回退）。
- RCON TCP `25575`。
- Docker daemon、WSL 管理接口和任何备份目录。

SakuraFrp 的远程端口不是 Palworld 的本地监听端口，不能写入 `PORT`。主机本人继续连接 `127.0.0.1:8211`。

## 12. 变更与验证清单

### 配置变更前

- 确认官网文档版本、游戏版本和社区镜像版本。
- 区分官方参数名、镜像环境变量名和生成后的 INI 名。
- 保存世界并创建备份。
- 确认没有在线玩家，或通知维护时间。
- 记录变更前 REST `info` 和相关 `settings`。

### 变更后

- `docker compose config --quiet`
- `scripts\verify-project.ps1`
- 等待容器 `healthy`
- REST `info`、`players`、`settings`
- 执行 REST `save`
- 核对 UDP `8211`、RCON loopback 和未发布 REST
- 检查生成后的 `PalWorldSettings.ini`
- 查看错误、OOM、存档和备份日志

### 完成声明

以下情况不得宣称“已完成”：

- 只修改 `.env`，未检查生成后的 INI 或 REST。
- 只有备份文件，未验证内容或恢复。
- 容器为 running，但未达到 healthy。
- 隧道启动成功，但没有远程客户端连接证据。
- 配置中包含平台名，但没有该平台实际连接证据。

## 13. 当前项目符合性矩阵

| 官方要求或方向 | 当前状态 | 结论 |
|---|---|---|
| 4 核以上、16 GB 内存、SSD | 推荐主机 4 核以上、16 GB 内存和 SSD；具体上限由部署者决定 | 以实际部署配置和本地预检为准 |
| UDP 8211 | 已发布并供本机/SakuraFrp 使用 | 符合 |
| Docker Desktop 不推荐 | 当前正使用 Docker Desktop + NTFS bind mount | 已接受差异；出现实际问题时再评估迁移 |
| 官方 Docker 镜像 | 当前使用固定摘要且已验证的社区镜像 | 当前主方案；官方路径作为回退 |
| 正确运行时配置 | LinuxServer INI 已核对，REST 返回预期值 | 符合 |
| REST 不公网暴露 | 8212 仅绑定到宿主机回环地址 | 符合 |
| RCON deprecated 且不公网暴露 | 默认关闭，显式启用时只允许回环访问 | 暂时可接受，应继续去依赖 |
| Community 才支持 Xbox/PS5 加入 | 当前 `COMMUNITY=false` | Xbox/PS5 尚不可据配置宣称可用 |
| 更新前备份 | 有自动与手动备份；`UPDATE_ON_BOOT=false` | 维护窗口内仍需手动确认备份 |
| 服务端 Mod 仅 Windows | Linux Docker、管理器禁用、空清单 | 符合 fail-closed |
| 非 PvP 默认 | 三项 PvP 开关为 false | 符合 |
| 备份可恢复 | 已验证创建，未完成真实恢复 | 部分完成 |
| 严格纯净客户端 | 运行时 `bAllowClientMod=true` | 待用户决定，不等于已装服务端 Mod |

## 14. 待办决策

1. 继续监控社区镜像维护状态、Docker Desktop I/O、OOM、更新和存档完整性；只有满足迁移触发条件时才评估官方方案。
2. 评估把容器内存上限从 8 GB 提高到至少 12–16 GB，并用同负载验证。
3. 完成一次真实备份恢复演练。
4. 确认是否要求严格纯净客户端；若要求，设置 `bAllowClientMod=false`。
5. 若需要 Xbox/PS5 玩家，单独设计 Community server 和隧道方案。
6. 在 RCON 被移除前，把剩余兼容命令迁移到 REST 或明确删除。
