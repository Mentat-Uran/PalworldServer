# Web Console 设置与状态能力规范

更新时间：2026-07-28

## 1. 范围与真实来源

Web Console 当前提供 205 个可编辑设置，定义集中在
`scripts/settings-catalog.ps1`，前后端不再分别维护两份字段清单。

| 来源 | 数量 | 实际作用 |
|---|---:|---|
| `game` | 117 | 由固定摘要镜像的 `compile-settings.sh` 写入 `PalWorldSettings.ini` |
| `container` | 74 | 由镜像的启动、备份、更新、暂停、日志或 Discord 脚本读取 |
| `engine` | 14 | `DISABLE_GENERATE_ENGINE=false` 时由 `compile-engine.sh` 写入 `Engine.ini` |
| 合计 | 205 | 当前 amd64 主机可用的面板字段 |

`PLAYERS` 属于容器启动变量，同时映射到
`PalWorldSettings.ini` 的 `ServerPlayerMaxNum`。因此游戏配置覆盖数是
117 个 `game` 字段加 `PLAYERS`，共 118 项，与固定摘要镜像模板一致。

以下 7 个 Box64/ARM64 专用变量不会在当前 Ryzen 7 9700X 主机上显示：

- `ARM64_DEVICE`
- `BOX64_DYNAREC_BIGBLOCK`
- `BOX64_DYNAREC_FASTNAN`
- `BOX64_DYNAREC_FASTROUND`
- `BOX64_DYNAREC_SAFEFLAGS`
- `BOX64_DYNAREC_STRONGMEM`
- `BOX64_DYNAREC_X87DOUBLE`

它们不是被遗漏，而是当前平台不适用。操作系统内部变量（例如
`HOME`、`PATH`）也不是服务端设置，不进入面板。

## 2. 设置分组

| 分组 | 数量 | 说明 |
|---|---:|---|
| 基础与容量 | 6 | 名称、描述、玩家上限和密码 |
| 世界与难度 | 17 | 难度、随机化、时间、倍率和世界事件 |
| 战斗与 PvP | 15 | 伤害、死亡、硬核、PvP 与重生 |
| 玩家与生存 | 10 | 饥饿、耐力、回血和能力强化 |
| 帕鲁 | 6 | 帕鲁消耗、恢复和农场行为 |
| 物品与掉落 | 17 | 掉落、采集、重量、耐久和容器更新 |
| 据点与建筑 | 11 | 据点上限、工作帕鲁、建筑和显示 |
| 公会与多人 | 12 | 公会重置、会长转移和多人规则 |
| 功能与权限 | 10 | 快速旅行、Palbox、Mod 许可、语音和科技限制 |
| 连接与 API | 14 | 端口、社区列表、跨平台、REST 和 RCON |
| 备份与自动化 | 17 | 启动更新、备份、定时更新、重启和无人暂停 |
| 日志与通知 | 45 | 玩家日志、日志格式和 Discord 事件通知 |
| 容器与启动 | 10 | UID/GID、线程参数、安装渠道和低层启动选项 |
| Engine.ini 性能 | 14 | Tick、带宽、平滑帧率和固定帧率 |
| 其他高级项 | 1 | 镜像支持但不属于上述常用分类的字段 |

高级项默认折叠，但可以用“显示高级项”、分组选择或搜索直接找到；这不会
减少后端支持范围。

## 3. 字段帮助与资料来源

每个字段都显示三层信息：

- “作用”：说明设置实际控制什么。
- “怎么调”：说明开关、枚举值、倍率、上限、间隔、端口或文本格式；不把所有
  数值误写成“越大越好”。
- 来源链接：游戏项链接 Palworld 官方配置或 PvP 文档；容器自动化链接
  `thijsvanloef/palworld-server-docker` 文档；Engine.ini 链接镜像 Engine
  设置页。

官方配置没有描述社区容器自身的 cron、Discord、UID/GID 和下载器逻辑，
这些字段不会伪装成官方游戏参数。面板的帮助是当前固定镜像与官方
Palworld 1.0 文档的适配说明。

## 4. 写入语义

- GET `/api/settings` 返回完整 schema、有效值、显式 `.env` 键和只写项状态。
- 密码与 Webhook 的值永不回显；前端只知道“是否已经配置”。
- 只写字段留空且未操作时保持现值；“清除”按钮会明确写入空值。
- 只提交已修改字段。值与当前配置相同则后端不重写 `.env`，也不需要重启。
- 有实际变化时原子写入 `.env`，随后由用户确认的“保存并重启”重建容器。
- 缺少的字段显示固定镜像默认值；只有用户修改后才追加到 `.env`。
- `PORT` 和 `RCON_PORT` 同时驱动 Compose 的容器端口与宿主机发布端口。
  修改 `PORT` 后仍需人工同步 Windows 防火墙和 SakuraFrp。
- `PUBLIC_PORT` 只改变社区列表公布值，不改变实际监听端口。
- `ALLOW_CLIENT_MOD` 只控制游戏的客户端 Mod 许可，不安装任何 Mod，也不改变
  当前禁用且为空的 Mod 管理器。

## 5. 校验与依赖

后端是最终校验边界，浏览器约束只用于即时反馈。

- 拒绝清单外键、控制字符、非有限数字、非法布尔值和非法枚举。
- 端口必须在 1–65535；REST 与 RCON TCP 端口不能相同。
- `COOP_PLAYER_MAX_NUM` 不能大于 `PLAYERS`，两者最多为 32。
- Cron 表达式必须是 5 个字段。
- `CROSSPLAY_PLATFORMS` 必须使用 `(Steam,Xbox,PS5,Mac)` 这类镜像格式。
- `PUBLIC_IP` 必须为空或合法 IP。
- URL/Webhook 必须为空或绝对 HTTP(S) URL。
- 平滑帧率下限必须小于上限。
- 语音最大音量距离不能大于零音量距离。
- 开启 PvP 时，`IS_PVP`、`ENABLE_PLAYER_TO_PLAYER_DAMAGE` 和
  `ENABLE_DEFENSE_OTHER_GUILD_PLAYER` 必须同时为 true。
- 每公会据点最多 10、每据点工作帕鲁最多 50、帕鲁同步距离为 5000–15000；
  这些范围来自当前官方配置说明。
- 管理员密码至少 16 个字符。

依赖项会降低未生效字段的视觉权重，但仍允许预先配置。例如：

- Engine.ini 字段依赖 `DISABLE_GENERATE_ENGINE=false`。
- 语音距离依赖 `ENABLE_VOICE_CHAT=true`。
- 硬核死亡项依赖 `HARDCORE=true`。
- PvP 地图与击杀掉落项依赖 `IS_PVP=true`。
- 定时更新、重启、备份和自动暂停的子项依赖各自的总开关。

风险标签是操作提示，不代表设置不受支持。高风险或谨慎项包括强制在线重启、
UID/GID、端口、自动更新、测试版本、PvP/硬核和 Engine.ini 性能参数。

## 6. 仪表盘数据

`GET /api/dashboard` 每 8 秒最多重新采样一次，并组合以下只读来源：

- Docker：状态、健康检查、CPU、内存、PID、启动时间、重启次数、退出码、
  OOM 状态、镜像摘要和端口绑定。Windows 原生运行时改用本机进程和 REST，
  不把 Docker 容器数据伪装成 Windows 指标。
- SteamCMD 启动更新：当 `UPDATE_ON_BOOT=true` 时，从当前容器日志读取下载、
  校验、提交阶段及百分比/字节进度；完成状态仅证明本次容器启动已完成自动检查，
  不会把旧日志或运行中的服务器标记为“当前上游无需更新”。面板不主动触发检查、
  下载或重启。
- Palworld REST：版本、服务器名称、描述、World GUID、在线玩家、最大玩家、
  FPS、平均 FPS、帧时间、世界天数、据点数和服务端运行秒数。
- 本机文件：备份数量、最近备份、备份总大小、存档文件数、存档大小和最近写入。
- SakuraFrp：Docker UDP 发布或 Windows UDP、本机相关进程、frpc 到节点的
  已建立 TCP 控制连接、服务日志中的“隧道启动成功”、远程地址、最近数据连接
  错误和成功外部流量。网络 Cmdlet 在独立 2.5 秒受限探针中运行；探针没有完成时
  状态为“本地网络证据未观察到”，而不是把未知说成连接已断开。
- 诊断：当前运行时的日志严重级别汇总和异常记录状态。Docker 使用容器日志；
  Windows 使用明确标记的生命周期和尽力采集的引擎日志。
- 项目状态：Mod 管理器仍为预留、禁用、零安装。

Docker 的 CPU 百分比以单个逻辑 CPU 为 100%：容器限制为 6 CPU 时，原始上限
是 600%。仪表盘主数值保留原始值，进度条与“已用”百分比按
`原始 CPU% / 600%` 计算。例如 17.2% 约等于 0.172 个 CPU，也是 6 核配额的
约 2.9%，不能用 100% 作为六核容器的满载线。CPU 与内存卡片同时保留精确数值
和横向进度条，并增加同口径圆环；圆环不是另一套指标。

玩家表可显示名称、等级、Ping、ID、IP 和坐标，默认遮蔽标识与 IP。Web
Console 只注册 `localhost`、`127.0.0.1` 和 `[::1]` 的 HTTP 前缀，并在请求层再次
拒绝非回环来源；仍不得通过 SakuraFrp、反向代理或端口转发公开。
后端优先监听 8213；若被占用则按 8214、18213、18214–18233 的顺序回退，并将当前端口
写入 `.settings-panel.port` 供启动器和回归脚本读取。启动器仅在 API 已验证可达时才打开
浏览器，且会清理无对应面板进程的失效标记文件。

## 7. 日志解释与异常记录

- `GET /api/logs` 在 Docker 返回未翻译的容器日志；Windows 返回明确标记的
  生命周期事件和尽力采集的引擎输出，二者不混淆。
- `GET /api/logs/insights` 返回原文、严重级别、规则代码和建议动作。
- `GET /api/incidents` 返回自动去重的错误/严重异常。
- `GET /api/log-archives` 返回按自然日生成的 TXT 列表和采集器状态。
- `POST /api/log-archives/refresh` 立即重建今天的归档。
- `GET /api/log-archives/download?name=YYYY-MM-DD.txt` 下载指定日期原始归档。
- 异常写入 `data/diagnostics/incidents.jsonl`；密码、令牌、Webhook 和 IPv4
  最后一段在持久化前遮盖。
- 解释属于本地规则分类，不是云端机器翻译。未知错误保留为“通用错误”，不会
  根据单行日志编造根因。

控制台还提供 12 个官方命令模板。单击模板只填入输入框，不直接执行；停止、
踢人、封禁和传送等操作仍需要用户明确发送。

每日归档由独立进程每 60 秒刷新，按 Asia/Shanghai 的 00:00–24:00 分文件，
汇总 Docker 游戏容器、Windows 生命周期、Windows 引擎尽力输出、Web Console 操作、
SakuraFrp 和事件档案。该进程同时轮询 REST `/players` 并维护本地在线时长，
Web Console 只读结果；REST 失败不会把原会话判作离线。历史文件不自动删除；
归档包含排障所需的原始标识和地址，因此只允许本机下载。

`GET /api/player-times` 仅返回显示名、累计时长、当前会话时长、在线状态、会话次数和
最后观察时间；稳定 ID 只在本机文件中以短 SHA-256 派生键保存，永不通过 API 或页面返回。
采集频率为 60 秒，因此这是聚合在线时长而不是精确的连接事件审计：两个采样点之间完成的
短暂连接无法被确认。离线结算会以该玩家最后一次确认在线的 `lastSeen` 样本封顶；采集器
中断后恢复时，未观测间隔不会被算作在线。控制台表头明确标为“已观测时长”，前端统一按秒、
分钟、小时和天显示，避免超过 24 小时后出现难读的纯小时数。

## 8. 状态判读

- `healthy`：Docker 健康检查通过。
- `starting`：容器已经启动但健康检查尚未通过，更新或首次启动时可能持续数分钟。
- REST 不可访问：仪表盘会保留 Docker 指标并显示警告，REST 管理能力不可用。
- `ready`：本地 UDP、进程、节点控制连接和“隧道启动成功”日志均存在，但还
  没有成功外部流量。
- `degraded`：隧道已启动，但启动之后出现且距当前不超过 15 分钟的数据连接
  错误。
- `network-unobserved`：受限本机网络探针未在时限内完成，因此 UDP 与控制连接
  状态未知；这不是“节点控制连接断开”的证据。
- 超过 15 分钟的错误继续保留在历史异常和事件档案中；只要本地 UDP、控制连接
  和代理就绪，旧错误不会永久占用实时警告栏。
- `verified`：前述证据通过，并且检测到成功外部数据连接；朋友实际进入仍是最
  强的端到端验收。
- RCON 标记为 deprecated：保留兼容终端，但新管理功能不得依赖它。

隧道细节和 2026-07-28 当前证据见
[`log-and-tunnel-diagnostics.md`](log-and-tunnel-diagnostics.md)。

## 9. 运行时切换防误触

当前活动运行时的切换按钮会显示“当前运行中”、以非操作状态呈现，并被禁用；
只有另一个蓝色目标按钮会请求切换。后端也会在创建后台任务前拒绝同目标请求，返回
HTTP `409` 和 `runtime-already-active`，因此绕过前端的本地请求不会额外创建快照、
停止服务或重启运行时。运行时切换进行时，前端和后端都会锁定快照与恢复写操作。

## 10. 回归验证

静态和运行时验证命令：

```powershell
.\scripts\verify-project.ps1

npm ci
npm run test:ui
```

`verify-project.ps1` 检查 PowerShell/JavaScript 语法、205 项 catalog、118 项游戏
映射、Compose 端口联动、Mod 空清单和 Docker Compose 配置。

`ui-smoke.cjs` 使用 `package.json` 声明的 `playwright-core` 与本机 Chrome 的 DevTools
接口，验证仪表盘加载、
五层隧道证据、CPU/内存圆环（Docker 为六核 600% 配额口径，Windows 为主机进程口径）、每日日志归档生成/下载、
205 个帮助块、密码不回显、搜索、
修改/撤销流程、日志解释、异常面板、12 个快捷命令，以及 390px 窄屏无横向
溢出。截图写入
`output/playwright/`，该目录属于本机诊断输出。Chrome 默认从常见 Windows 安装位置查找；
非标准位置可通过 `PALWORLD_UI_SMOKE_CHROME` 环境变量提供。每次测试使用独立的临时
DevTools 端口，避免误连到其他 Chrome 实例。测试会刷新本机隧道/归档证据，但不会执行
启动、停止、运行时切换、设置保存或游戏连接；它还会断言当前运行时按钮不可执行、
另一个目标保持可用，并检查运行时安全提示。
