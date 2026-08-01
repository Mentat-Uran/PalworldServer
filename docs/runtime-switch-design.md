# Palworld Dedicated Server — 可切换运行时设计文档

- 日期：2026-07-28
- 状态：已实施；2026-07-31 完成本地 Docker→Windows→Docker 回归与 Windows tar 备份实测。远端隧道、多人稳定性和生产恢复仍不在此结论内。
- 上游文档：[README.md](../README.md)、[docs/architecture.md](architecture.md)、[AGENTS.md](../AGENTS.md)
- 目标：在保留现有 Docker 部署完整可用的前提下，新增 Windows 原生 dedicated server 启动方式，两种运行时共享同一套 Web UI、管理 API、配置源、ENV、备份/日志体系和同一份世界存档，任一时刻只能运行其中一种。Windows 方式需支持原生服务端启动/停止、REST、配置应用、日志、备份、状态监控与受控的官方 Mod 管理。

## 0. 方案选型与关键决策

### 0.1 已确认选型

- 架构方案：方案 C — Junction 实时共享 + 复制时无损快照
  - 实时共享：Docker 容器与 Windows 服务端通过 NTFS junction 指向同一份 `data\Pal\Saved\SaveGames\` 物理存档
  - 显式回退点：每次切换前后在 `data\switch-snapshots\` 创建快照，区别于日常 04:00 备份
- 磁盘占用控制：采用"分类快照 + 总量上限"策略（详见第 3.4 节），不依赖单纯份数保留
- 切换前后必须做 REST save；切换前快照视为切换动作的必备步骤
- 配置同源：Docker 与 Windows 的 INI 由同一编译器从同一 `.env` 生成，差异只在行结束符
- 互斥：`runtime.state` 是唯一互斥源，所有启动入口先读互斥锁

### 0.2 不变性约束（实施过程必须始终满足）

1. `data\Pal\Saved\SaveGames\` 在任意时刻只存在一份物理存档，由 junction 路由给当前 active runtime
2. 切换操作是原子的：要么完整完成 Docker→Windows 切换，要么完整回退到切换前状态
3. Docker 现有功能在 Docker active 时保持不变；Windows active 时 Docker 容器必须处于 exited 状态
4. `data\backups\` 与 `data\switch-snapshots\` 内容由本项目脚本独占写；外部工具只读
5. `.env` 与 `scripts\settings-catalog.ps1` 是配置唯一源；INI 永远派生自二者，不接受手工编辑
6. REST 是主管理 API；RCON 仅在 Windows 运行时启动且 REST 不可用时作为兼容回退

## 1. 总体架构与运行时抽象

### 1.1 双运行时抽象

引入 Runtime 概念作为 Docker 与 Windows 原生服务端的统一抽象：

| 概念 | 实现 |
|---|---|
| `runtime.state` | `data\runtime.state` 文件，原子写入，记录 `active=none\|docker\|windows`、PID、启动时间、版本 |
| `IRuntimeProvider` | PowerShell 接口约定（鸭子类型），两个实现：`docker-runtime.ps1`、`win-runtime.ps1` |
| 统一操作 | Start、Stop、Health、Save、Version、Players、Logs、Settings |
| 路由 | `settings-panel.ps1` 启动时读 `runtime.state`，按 `active` 字段路由到对应 runtime provider |

现有 API（`/api/state`、`/api/dashboard`、`/api/stop`、`/api/restart`、`/api/save`、`/api/logs`、`/api/rcon` 等）保持 URL 不变，内部实现按 runtime 切换。

### 1.2 目标目录结构

```text
<project-root>\
├── data\
│   ├── Pal\Saved\
│   │   ├── Config\
│   │   │   ├── LinuxServer\PalWorldSettings.ini   ← Docker 读取
│   │   │   ├── LinuxServer\Engine.ini             ← Docker 读取
│   │   │   └── WindowsServer\PalWorldSettings.ini ← Windows 读取（同源生成）
│   │   ├── SaveGames\0\<GUID>\                    ← 唯一物理存档
│   │   │   ├── Level.sav
│   │   │   ├── LevelMeta.sav
│   │   │   ├── Players\
│   │   │   └── backup\                            ← 服务端运行时自动备份
│   │   └── Logs\                                   ← 各自平台子目录
│   │       ├── docker\
│   │       └── windows\
│   ├── switch-snapshots\                           ← 切换快照（分类保留）
│   ├── backups\                                    ← 日常 04:00 备份
│   ├── diagnostics\                                ← incidents.jsonl、ini-compile.log、switch.log
│   ├── log-archive\                                 ← 北京时间自然日归档
│   ├── log-sources\
│   │   ├── game\
│   │   ├── panel\
│   │   └── windows-server\                          ← Windows 原生服务端日志源
│   └── runtime.state                                ← 当前运行时标记
├── win-server\                                       ← SteamCMD 安装
│   ├── PalServer.exe
│   ├── steam_appid.txt
│   ├── DefaultPalWorldSettings.ini
│   └── Pal\Saved\
│       ├── Config\WindowsServer\                    ← 真实配置目录
│       │   ├── PalWorldSettings.ini                 ← junction 或真实文件
│       │   └── Engine.ini
│       └── SaveGames  ←─── junction ───→ data\Pal\Saved\SaveGames
├── .env                                             ← 唯一配置源
├── scripts\
│   ├── compile-settings.ps1                         ← 统一 INI 编译器
│   ├── switch-runtime.ps1                           ← 切换+互斥+快照
│   ├── docker-runtime.ps1                           ← Docker provider
│   ├── win-runtime.ps1                              ← Windows provider
│   ├── install-win-server.ps1                       ← SteamCMD 安装器
│   ├── mod-manager.ps1                              ← 扩展支持 Windows 运行时
│   ├── settings-catalog.ps1                         ← 不变，仍是唯一 schema
│   ├── daily-log-collector.ps1                       ← 扩展支持 Windows 日志源
│   ├── normalize-env.ps1
│   └── verify-project.ps1                            ← 扩展双 INI 校验
└── ...
```

### 1.3 互斥机制

`runtime.state` 是唯一互斥源：

- `palworld.bat`、`switch-runtime.ps1`、所有 `/api/*` 写操作都先读 `runtime.state`
- 启动目标 runtime 前必须确认 `active=none` 或与目标一致
- 任何 Stop 成功后才把 `active=none`，然后才允许 Start 另一个
- 文件写入使用 `Set-Content -NoNewline` 加临时文件 + `Move-Item` 原子替换
- 进程级互斥：使用 `New-Object System.Threading.Mutex($false, 'Global\PalworldServerRuntime')` 作为额外保护，避免并发 API 调用产生 race

`runtime.state` 字段：

```json
{
  "active": "docker|windows|none",
  "pid": 12345,
  "startedAt": "2026-07-28T17:00:00+08:00",
  "version": "v1.0.1.100619",
  "switching": false,
  "lastSwitchAt": "2026-07-28T17:30:00+08:00",
  "lastSwitchFrom": "docker",
  "lastSwitchTo": "windows"
}
```

## 2. 配置同源编译与双 INI 生成

### 2.1 现状盘点

| 项 | 当前实现 |
|---|---|
| 配置源 | `.env`（唯一源） |
| Schema 源 | `scripts/settings-catalog.ps1`（205 项 = 117 game + 74 container + 14 engine） |
| Linux INI 生成器 | 容器镜像内置 `compile-settings.sh` / `compile-engine.sh`，启动时按 `.env` 写入 `data\Pal\Saved\Config\LinuxServer\PalWorldSettings.ini` |
| Windows INI 生成器 | **不存在**，需新增 |
| 校验路径 | `/api/settings` 反查 catalog；`LinuxServer\PalWorldSettings.ini` 作为运行时证据 |
| Web Console 写入 | 已实现 changed-only 原子写入 `.env`，依赖容器重建或下次启动应用 |

### 2.2 新增 `scripts/compile-settings.ps1`

项目自有的统一 INI 编译器，作为 Docker 镜像内置脚本的"镜像外镜像"。

```text
输入：.env  +  scripts/settings-catalog.ps1
输出：
  data\Pal\Saved\Config\LinuxServer\PalWorldSettings.ini   ← Docker 覆盖读取
  win-server\Pal\Saved\Config\WindowsServer\PalWorldSettings.ini  ← Windows 原生读取
  data\Pal\Saved\Config\LinuxServer\Engine.ini             ← DISABLE_GENERATE_ENGINE=false 时
  win-server\Pal\Saved\Config\WindowsServer\Engine.ini           ← 同上
  data\diagnostics\ini-compile.log                         ← 时间戳、字段数、写入路径
```

调用点：

1. `switch-runtime.ps1` 切换流程步骤 4（Stop 之后、Start 之前）
2. Web Console `/api/env` POST 成功后立即调用（异步，不阻塞响应）
3. `palworld.bat` 启动前的预检
4. 手动触发：`.\scripts\compile-settings.ps1 -Validate`

### 2.3 双 INI 差异矩阵

两份 INI 内容语义相同，只在以下三处不同：

| 维度 | Linux 版 | Windows 版 |
|---|---|---|
| 行结束符 | `\n` | `\r\n`（UE 在 Windows 下读取兼容 `\n`，但 `\r\n` 是规范） |
| 路径分隔符 | 不出现（PalWorldSettings.ini 字段值不使用路径） | 不出现 |
| `RCONEnabled` | 受 `RCON_ENABLED=true` 控制 | Windows 原生通过命令行 `-rcon -rpc -restapi` 启用，INI 内字段保持 `true` 即可 |

结论：两份 INI 可共用一份中间结构（PSObject），渲染两遍时只切换行结束符。

### 2.4 编译流程

```text
compile-settings.ps1
  ├─ 1. 加载 .env（按现有 /api/env 的解析逻辑）
  ├─ 2. 加载 settings-catalog.ps1 的 schema
  ├─ 3. 对每个 game 类字段：按 schema 的 iniKey + 类型/范围/默认值构造中间对象
  ├─ 4. 渲染为 PalWorldSettings.ini 文本（UE INI 语法：Option=(Key=Value,Key2=Value2)）
  ├─ 5. UTF-8 BOM 写 LinuxServer/PalWorldSettings.ini（\n）
  ├─ 6. UTF-8 BOM 写 WindowsServer/PalWorldSettings.ini（\r\n）
  ├─ 7. 处理 engine 类字段 → 写两份 Engine.ini（同上换行差异）
  ├─ 8. 写 data\diagnostics\ini-compile.log（时间戳、字段数、写入路径、SHA-256 摘要）
  └─ 9. -Validate 时：回读两份文件，比对关键字段与 .env 期望值
```

注意点：

- 容器镜像内置 `compile-settings.sh` 仍会在 Docker 启动时覆盖 LinuxServer 版本，结果幂等
- WindowsServer 目录不存在时编译前自动创建
- 不写 `Manifest.ini` / `GameUserSettings.ini` 等运行时自生成文件
- secret 字段（`ADMIN_PASSWORD`、`SERVER_PASSWORD`、webhook）以明文写入 INI 是 Palworld 服务端要求；INI 在 `data\` 下受 `.gitignore` 保护

### 2.5 与现有 Web Console 的关系

| 操作 | 现有行为 | 新增行为 |
|---|---|---|
| `/api/env` POST 成功 | 原子写 `.env`，依赖容器重建应用 | 原子写 `.env` 后立即调用 `compile-settings.ps1`，两份 INI 同步更新 |
| `/api/settings` GET | 读 catalog + `.env` | 不变 |
| `/api/state` GET | 直接读 Docker | 新增字段 `runtime`、`iniCompileStatus` |

### 2.6 校验与漂移检测

`scripts\verify-project.ps1` 新增检查项：

1. `.env` 中所有 game 类字段都已在两份 `PalWorldSettings.ini` 中体现
2. 两份 INI 的关键字段值相同（ServerPlayerMaxNum、CoopPlayerMaxNum、ExpRate、DayTimeSpeedRate、DeathPenalty、ServerName、AdminPassword、ServerPassword、Port、RCONEnabled）
3. INI 修改时间晚于 `.env` 修改时间（否则警告：配置已变更但 INI 未重新编译）

漂移修复：重跑 `compile-settings.ps1`，幂等覆盖。

### 2.7 SteamCMD 更新覆盖的边界情况

Windows 原生服务端通过 SteamCMD 更新时可能：

- 重置 `PalServer.exe` 同级目录的 `DefaultPalWorldSettings.ini`（不影响 `Saved\Config\WindowsServer\PalWorldSettings.ini`）
- 不会触碰 `Saved\SaveGames\`（存档安全）
- 不会触碰 junction（junction 在 `Saved\SaveGames` 层级，SteamCMD 不动 `Saved\` 子目录）

`switch-runtime.ps1` 在启动 Windows 前必须校验 `WindowsServer` 目录存在，若缺失则重新编译 INI。

## 3. Junction 与存档快照（含磁盘占用方案）

### 3.1 Junction 设计

#### 3.1.1 唯一物理存档位置

物理存档固定在：

```text
<project-root>\data\Pal\Saved\SaveGames\
```

Docker 容器直接通过 bind mount 看到该路径（容器内 `/palworld/Pal/Saved/SaveGames/`），无需额外 junction。

Windows 服务端需要 junction：

```text
<project-root>\win-server\Pal\Saved\SaveGames  ←─ junction ─→  <project-root>\data\Pal\Saved\SaveGames
```

#### 3.1.2 Junction 创建与修复

新增函数 `Assert-SaveGamesJunction`（位于 `win-runtime.ps1`），在 Windows runtime Start 之前调用：

```powershell
function Assert-SaveGamesJunction {
    $target = '<project-root>\data\Pal\Saved\SaveGames'
    $link   = '<project-root>\win-server\Pal\Saved\SaveGames'

    # 1. 确保物理存档目录存在
    if (-not (Test-Path $target)) {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
    }

    # 2. 检查 link 状态
    $item = Get-Item $link -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'Junction') {
        $resolved = (Resolve-Path $link).Path
        if ($resolved -eq $target) { return $true }  # 已正确
        # 指向错误目标，先删
        cmd /c rmdir "$link"  # junction 必须用 rmdir，不能用 del
    }
    elseif ($item) {
        # 存在但是真实目录或文件 — 不允许删除用户数据，报错
        throw "SaveGames junction 位置存在非 junction 项：$link"
    }

    # 3. 确保 win-server\Pal\Saved\ 存在
    $parent = Split-Path $link -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    # 4. 创建 junction
    cmd /c mklink /J "$link" "$target" | Out-Null
    return $?
}
```

#### 3.1.3 Junction 校验时机

- `switch-runtime.ps1 -To windows` Start 之前
- `win-runtime.ps1` 的 Start 内部首步
- `scripts/verify-project.ps1`
- Web Console `/api/dashboard` 在 `active=windows` 时返回 junction 状态字段

#### 3.1.4 Junction 失效场景与处理

| 场景 | 表现 | 处理 |
|---|---|---|
| 用户手动删 junction | `Test-Path $link` 返回 false | `Assert-SaveGamesJunction` 重建 |
| SteamCMD 重建 `win-server\` | junction 消失 | 同上 |
| 用户把 junction 改成真实目录 | `LinkType` 非 Junction | 抛错，要求人工确认是否合并存档 |
| Junction 指向错误目标 | `Resolve-Path` 不匹配 target | `rmdir` 旧 junction + 重建 |
| 物理存档目录被删 | `Test-Path $target` 返回 false | 报错并停止切换，等待从快照恢复 |

### 3.2 快照分类

| 类型 | 触发 | 内容 | 大小（典型） | 用途 |
|---|---|---|---|---|
| Full | 切换前后；Mod 变更；Palworld 服务端版本变更；用户手动 | `SaveGames\` + 两份 `PalWorldSettings.ini` + 两份 `Engine.ini` + `.env` + `runtime.state` | 5–50 MB | 完整回退点 |
| Light | 切换前后（常规） | 两份 `PalWorldSettings.ini` + 两份 `Engine.ini` + `.env` + `runtime.state` + `SaveGames` 目录树清单（文件名 + 大小 + SHA-256） | <100 KB | 配置回退 + 存档指纹比对 |

默认策略：**常规切换只做 Light 快照**，仅在以下条件下升级为 Full：

- 切换前后 `SaveGames` 目录树清单的 SHA-256 出现差异（说明有写入未完成）
- 切换发生在 Palworld 服务端版本变更之后（runtime.state 中 `version` 字段变化）
- Mod 清单发生变更
- 用户在 Web Console 勾选"切换前创建完整快照"
- 距离上次 Full 快照超过 24 小时

### 3.3 快照目录结构与命名

```text
data\switch-snapshots\
├── 20260728-173000-Light-pre-docker-to-windows.tar.gz
├── 20260728-173001-Light-post-windows-start.tar.gz
├── 20260728-180000-Full-pre-version-update.tar.gz
└── manifest.json
```

`manifest.json`：

```json
{
  "snapshots": [
    {
      "name": "20260728-173000-Light-pre-docker-to-windows.tar.gz",
      "type": "Light",
      "phase": "pre",
      "createdAt": "2026-07-28T17:30:00+08:00",
      "trigger": "switch",
      "from": "docker",
      "to": "windows",
      "sizeBytes": 8200,
      "savegamesFingerprint": "sha256:abc...",
      "iniFingerprint": "sha256:def..."
    }
  ],
  "retentionPolicy": {
    "maxFullCount": 3,
    "maxFullTotalBytes": 1073741824,
    "maxLightCount": 10,
    "minFullKeepHours": 24
  }
}
```

### 3.4 磁盘占用解决方案（分类 + 总量上限 + 自动转压）

采用三层控制：

1. **分类保留**：
   - Full 快照保留最近 3 份 **且** 总大小不超过 1 GB
   - Light 快照保留最近 10 份
   - 任意时刻确保至少 1 份 Full 快照存在（即使超过 24 小时）

2. **自动 LZMA 压缩**：所有快照默认使用 `tar.gz`（gzip level 6），Full 快照创建 1 小时后自动转 `tar.xz`（LZMA，level 9），可将 50 MB 存档压缩到 8–15 MB。转换通过 `switch-runtime.ps1` 的清理流程异步触发。

3. **总量预警**：`switch-snapshots\` 总大小超过 2 GB 时在 `data\diagnostics\incidents.jsonl` 写入 `WARN` 级别记录，Web Console 仪表盘显示警告，不阻塞切换。

清理算法（每次切换后执行）：

```text
1. 列出所有 Full 快照，按时间倒序
2. 若 count > maxFullCount(3) 且超出的最旧快照 age > minFullKeepHours(24)：删除最旧的
3. 若 totalBytes > maxFullTotalBytes(1GB)：删除最旧的 Full，直到 ≤ 1GB
4. 列出所有 Light 快照，按时间倒序，删除超过 maxLightCount(10) 的旧项
5. 若仍超 1GB，将最旧的 .tar.gz 转为 .tar.xz（异步）
```

### 3.5 快照校验

每次创建快照后立即做完整性校验：

- `tar -tzf <file>` 列出条目，校验条目数 ≥ 期望
- 计算文件 SHA-256，写入 `manifest.json`
- Light 快照额外记录 `SaveGames` 目录树指纹（递归 SHA-256），用于切换前后对比

### 3.6 快照恢复流程

新增 `scripts/restore-snapshot.ps1`：

```text
restore-snapshot.ps1 -Name <snapshot-name> [-Force]
  1. 读 runtime.state，若 active != none：拒绝（除非 -Force，会先调 Stop）
  2. 校验快照文件 SHA-256 与 manifest.json 一致
  3. 创建当前状态临时 Light 快照（防止误恢复）
  4. 解压快照到临时目录
  5. 备份当前 SaveGames 到 data\restore-backup\<timestamp>\
  6. 替换 SaveGames（Full 快照）或仅 INI/.env（Light 快照）
  7. 重跑 compile-settings.ps1（确保 INI 与 .env 一致）
  8. 写入 runtime.state active=none，等待用户手动启动目标 runtime
```

## 4. Windows 原生服务端管理

### 4.1 SteamCMD 安装

新增 `scripts/install-win-server.ps1`：

```text
install-win-server.ps1 [-Force]
  1. 检查 win-server\ 是否存在且包含 PalServer.exe
     - 若存在且 -Force 未指定：校验版本并退出
     - 若存在且 -Force：备份当前 win-server\Pal\Saved\Config\，删除 win-server\
  2. 下载 SteamCMD：https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip
  3. 解压到 <project-root>\steamcmd\
  4. 运行 steamcmd\steamcmd.exe：
       login anonymous
       force_install_dir <project-root>\win-server
       app_update 2394010 validate
       quit
  5. 等待下载完成（Palworld dedicated server 约 5 GB）
  6. 校验 win-server\PalServer.exe 存在
  7. 创建 win-server\Pal\Saved\Config\WindowsServer\ 目录
  8. 调用 compile-settings.ps1 生成 Windows INI
  9. 创建 SaveGames junction（Assert-SaveGamesJunction）
 10. 写入 win-server\version.txt（记录 Steam build id）
```

### 4.2 版本管理

- `win-server\version.txt`：Steam app build id，由 SteamCMD 写入
- `runtime.state` 的 `version` 字段：从 `win-server\version.txt` 或 `docker inspect` 读取
- 版本不一致时 Web Console 显示警告，不阻塞启动

### 4.3 PalServer.exe 启动参数

参考 Palworld 官方文档与 `win-server\PalServer.sh` 的 Linux 启动行：

```text
PalServer.exe -port=8211 -queryport=27015 -useperfthreads -NoAsyncLoadingThread -UseMultithreadForLoad -rcon -rpc -restapi
```

- `-port=8211`：游戏 UDP 端口，与 Docker 保持一致
- `-queryport=27015`：服务器查询端口（不对外暴露，仅本机）
- `-rcon -rpc -restapi`：启用 RCON 与 REST API，与 Docker 等价
- REST API 端口固定 8212（Windows 服务端硬编码，不接受参数）
- RCON 端口固定 25575（Windows 服务端硬编码）

**REST/RCON 绑定地址**：Windows 服务端默认绑定 `0.0.0.0`，与 Docker 不同。必须通过 Windows 防火墙规则限制为 `127.0.0.1`：

```powershell
# 阻断 8212/25575 的外部入站
New-NetFirewallRule -DisplayName "Palworld Block REST 8212 Public" `
  -Direction Inbound -Protocol TCP -LocalPort 8212 -RemoteAddress Internet -Action Block
New-NetFirewallRule -DisplayName "Palworld Block RCON 25575 Public" `
  -Direction Inbound -Protocol TCP -LocalPort 25575 -RemoteAddress Internet -Action Block
```

`install-win-server.ps1` 末尾自动创建上述规则。

### 4.4 Windows 服务端启动器 `win-runtime.ps1`

鸭子类型接口与 `docker-runtime.ps1` 一致：

```powershell
# 操作签名
function Start-Runtime  { ... }
function Stop-Runtime   { ... }
function Get-RuntimeHealth { ... }
function Invoke-RuntimeSave { ... }
function Get-RuntimeVersion { ... }
function Get-RuntimePlayers { ... }
function Get-RuntimeLogs   { ... }
function Get-RuntimeSettings { ... }
```

#### 4.4.1 Start

```text
1. Assert-SaveGamesJunction
2. 校验 win-server\PalServer.exe 存在
3. 校验 win-server\Pal\Saved\Config\WindowsServer\PalWorldSettings.ini 存在
4. 启动 PalServer.exe，使用 System.Diagnostics.Process
   - WorkingDirectory: win-server\
   - 重定向 stdout/stderr 到 data\log-sources\windows-server\<date>.log
   - 记录 PID 到 runtime.state
5. 等待 REST /health 接口响应（最多 120s，每 2s 轮询）
6. 健康后更新 runtime.state active=windows、pid、startedAt、version
```

#### 4.4.2 Stop

```text
1. 读 runtime.state 获取 PID
2. 调用 REST /stop（超时 30s）
3. 若 REST 失败：调用 RCON shutdown
4. 若 RCON 失败：Stop-Process -Id $pid -Force（最后手段）
5. 等待进程退出，最多 120s
6. 校验端口 8211/8212/25575 已释放
7. 更新 runtime.state active=none
```

#### 4.4.3 Health

调用 `http://127.0.0.1:8212/v1/api/health`，超时 5s。返回 `healthy` / `degraded` / `unreachable`。

#### 4.4.4 Save

优先 `POST http://127.0.0.1:8212/v1/api/save`，超时 30s；失败回退 RCON `Save` 命令。

#### 4.4.5 Players / Version / Settings / Logs

- Players：`GET /v1/api/players`
- Version：`GET /v1/api/info` 解析 `version` 字段
- Settings：`GET /v1/api/settings`
- Logs：读 `data\log-sources\windows-runtime\<date>.log` 的生命周期事件，并附带
  `data\log-sources\windows-server\<date>.log` 的引擎尽力输出；两类证据必须区分。

### 4.5 进程级故障保护

- 启动失败时清理残留进程：检查 PID 是否仍在运行，是则 Kill
- 启动后 5 秒内若进程已退出，读 stderr 日志，写入 `incidents.jsonl`
- 不提供独立的 `watch-win-server.ps1`。当前通过 `Get-WindowsRuntimeHealth`、
  Web Console、生命周期事件与切换恢复流程报告原生运行状态；自动重启仍避免以降低存档风险。

## 5. 切换流程 `switch-runtime.ps1` 规格

### 5.1 命令行接口

```text
switch-runtime.ps1 -To docker|windows [-Force] [-SkipSnapshot] [-FullSnapshot]
  -To         目标运行时（必填）
  -Force      目标与当前相同时仍执行
  -SkipSnapshot  跳过切换前快照（仅紧急使用，写 incident）
  -FullSnapshot  强制创建 Full 快照（覆盖 Light 默认）
```

退出码：

- 0：成功
- 1：参数错误
- 2：当前 runtime 与目标相同且未指定 -Force
- 3：当前 runtime 无法停止（Stop 超时）
- 4：目标 runtime 依赖缺失（Docker 未安装 / PalServer.exe 缺失）
- 5：Junction 校验失败
- 6：INI 编译失败
- 7：目标 runtime 启动失败
- 8：目标 runtime 健康检查超时
- 9：快照创建失败

### 5.2 完整流程（伪代码）

```powershell
param([Parameter(Mandatory)][ValidateSet('docker','windows')][string]$To,
      [switch]$Force, [switch]$SkipSnapshot, [switch]$FullSnapshot)

$ErrorActionPreference = 'Stop'
$state = Get-RuntimeState
$log   = Start-SwitchLog

# 步骤 1：互斥检查
Acquire-RuntimeMutex  # 全局 Mutex
try {
    # 步骤 2：同目标检查
    if ($state.active -eq $To -and -not $Force) {
        throw "当前已是 $To 运行时，未指定 -Force"
    }

    # 步骤 3：停止当前 runtime
    if ($state.active -ne 'none') {
        # 3a. REST save
        try { Invoke-RuntimeSave -Runtime $state.active -Timeout 30 }
        catch { Write-Warning "REST save 失败：$_"; 继续 }

        # 3b. 切换前快照
        if (-not $SkipSnapshot) {
            $snapType = if ($FullSnapshot) { 'Full' } elseif (Test-NeedsFullSnapshot) { 'Full' } else { 'Light' }
            New-SwitchSnapshot -Type $snapType -Phase pre -From $state.active -To $To
        } else {
            Write-Incident -Level WARN -Message "切换跳过快照（用户指定）"
        }

        # 3c. Stop
        $stopResult = Invoke-RuntimeStop -Runtime $state.active -Grace 120
        if (-not $stopResult.Success) {
            Write-Incident -Level ERROR -Message "停止 $($state.active) 超时"
            exit 3
        }

        # 3d. 端口校验
        if (-not (Test-PortsReleased)) {
            Write-Incident -Level ERROR -Message "端口未释放"
            exit 3
        }

        # 3e. 标记 none
        Update-RuntimeState -active none -pid $null -switching $true
    }

    # 步骤 4：校验目标依赖
    if (-not (Test-RuntimeDeps -Runtime $To)) {
        Write-Incident -Level ERROR -Message "$To 依赖缺失"
        exit 4
    }

    # 步骤 5：junction 校验（仅 windows）
    if ($To -eq 'windows') {
        try { Assert-SaveGamesJunction }
        catch { Write-Incident -Level ERROR -Message "Junction 失败：$_"; exit 5 }
    }

    # 步骤 6：重新编译 INI
    try {
        & .\scripts\compile-settings.ps1
    } catch {
        Write-Incident -Level ERROR -Message "INI 编译失败：$_"
        exit 6
    }

    # 步骤 7：启动目标 runtime
    try {
        Start-Runtime -Runtime $To
    } catch {
        Write-Incident -Level ERROR -Message "启动 $To 失败：$_"
        # 回退：尝试启动原 runtime
        Write-Warning "尝试回退到 $($state.active)"
        if ($state.active -ne 'none') {
            try { Start-Runtime -Runtime $state.active } catch { }
        }
        exit 7
    }

    # 步骤 8：等待健康
    $healthy = Wait-RuntimeHealth -Runtime $To -Timeout 120
    if (-not $healthy) {
        Write-Incident -Level ERROR -Message "$To 健康检查超时"
        # 不自动回退，留给用户决定
        exit 8
    }

    # 步骤 9：更新 state
    Update-RuntimeState -active $To -pid (Get-RuntimePid -Runtime $To) `
        -startedAt (Get-Date) -version (Get-RuntimeVersion -Runtime $To) `
        -switching $false -lastSwitchFrom $state.active -lastSwitchTo $To `
        -lastSwitchAt (Get-Date)

    # 步骤 10：切换后快照
    if (-not $SkipSnapshot) {
        $postType = if ($FullSnapshot) { 'Full' } else { 'Light' }
        New-SwitchSnapshot -Type $postType -Phase post -From $state.active -To $To
    }

    # 步骤 11：清理旧快照
    Invoke-SnapshotRetention

    Write-SwitchLog "切换完成：$($state.active) → $To"
    exit 0
}
finally {
    Release-RuntimeMutex
}
```

### 5.3 回退策略

切换失败时按退出码处理：

| 失败步骤 | 回退动作 |
|---|---|
| 步骤 3（Stop 失败） | 不动当前 runtime，记录 incident，等待人工介入 |
| 步骤 4（依赖缺失） | 当前 runtime 已 Stop，标记 active=none，等待用户安装依赖 |
| 步骤 5（Junction 失败） | 同上 |
| 步骤 6（INI 编译失败） | 同上，但当前 INI 仍可用（旧值），用户可手动启动旧 runtime |
| 步骤 7（Start 失败） | 尝试自动回退到切换前 runtime；失败则 active=none |
| 步骤 8（健康超时） | **不自动回退**，留给用户决定（可能服务端正在 SteamCMD 更新，需要更长时间） |

回退原则：

- 步骤 3–5 失败：当前 runtime 已停止，不重启，等待人工介入（避免数据丢失）
- 步骤 6–8 失败：尝试重启原 runtime，因为存档未被破坏
- 任何失败都创建一次 Light 快照（若尚未创建），保留现场

### 5.4 切换日志

写入 `data\diagnostics\switch.log`：

```text
[2026-07-28 17:30:00] BEGIN switch docker → windows
[2026-07-28 17:30:01]   REST /save returned 200 (1.2s)
[2026-07-28 17:30:02]   Snapshot created: 20260728-173000-Light-pre-docker-to-windows.tar.gz
[2026-07-28 17:30:03]   Stop docker: ok (8s)
[2026-07-28 17:30:04]   Ports released: 8211, 8212, 25575
[2026-07-28 17:30:05]   Deps windows: ok (PalServer.exe found)
[2026-07-28 17:30:06]   Junction ok
[2026-07-28 17:30:07]   INI compiled: 118 fields
[2026-07-28 17:30:08]   Start windows: PID 12345
[2026-07-28 17:32:10]   Health: healthy (122s)
[2026-07-28 17:32:11]   Post snapshot created
[2026-07-28 17:32:12] END switch ok
```

## 6. Web Console 改造

### 6.1 后端 `settings-panel.ps1` 改动

#### 6.1.1 启动流程改动

```text
原：直接启动 HttpListener，假设 Docker
新：
  1. 读 runtime.state
  2. 加载对应 runtime provider（docker-runtime.ps1 或 win-runtime.ps1）
  3. 启动 HttpListener，路由表新增 /api/runtime、/api/switch 等
```

#### 6.1.2 API 路由变更

| Endpoint | Method | 改动 |
|---|---|---|
| `/api/state` | GET | 内部实现按 runtime 切换；新增 `runtime`、`runtime switching`、`iniCompileStatus` 字段 |
| `/api/dashboard` | GET | 同上；新增 `junction` 状态（windows 时）、`switchSnapshots` 概要 |
| `/api/settings` | GET | 不变 |
| `/api/env` | GET | 不变 |
| `/api/env` | POST | 写 `.env` 后立即调用 `compile-settings.ps1` |
| `/api/restart` | POST | 调用当前 runtime provider 的 Stop + Start |
| `/api/stop` | POST | 调用当前 runtime provider 的 Stop |
| `/api/save` | POST | 调用当前 runtime provider 的 Save |
| `/api/logs` | GET | 按当前 runtime 读对应日志源 |
| `/api/logs/insights` | GET | 同上，规则不变 |
| `/api/rcon` | POST | 仅 active=windows 时可用（Docker 保留） |
| `/api/runtime` | GET | 返回 `runtime.state` 完整内容 |
| `/api/runtime/switch` | POST | 触发 `switch-runtime.ps1 -To <target>`，异步执行 |
| `/api/runtime/snapshot` | POST | 手动创建快照 |
| `/api/runtime/restore` | POST | 触发 `restore-snapshot.ps1 -Name <name>` |
| `/api/snapshots` | GET | 列出 `data\switch-snapshots\` 内容 |
| `/api/backups` | GET | 不变 |
| `/api/backup` | POST | 调用当前 runtime provider 的 backup（Docker 用容器内 backup；Windows 用 `tar` 直接打包） |
| `/api/mods` | GET | 扩展返回 Windows 运行时兼容性 |

#### 6.1.3 异步任务队列

`/api/runtime/switch` 与 `/api/runtime/restore` 是耗时操作（30s–5min），通过异步任务实现：

- POST 立即返回 `{ "taskId": "<guid>", "status": "running" }`
- 任务状态写入 `data\diagnostics\tasks\<taskId>.json`
- 客户端轮询 `/api/runtime/task?id=<guid>` 获取进度
- 任务完成后返回最终退出码与日志摘要

#### 6.1.4 Docker 不再硬编码

`settings-panel.ps1` 中所有 `docker compose ...` 命令都改为通过 `docker-runtime.ps1` 调用，便于切换：

```powershell
# 原
$proc = Start-Process docker -ArgumentList 'compose','ps' ...

# 新
$result = Invoke-RuntimeAction -Action 'ps'
```

### 6.2 前端 `web/index.html` 改动

#### 6.2.1 顶栏新增运行时指示器

```text
[当前运行时: Docker]  [切换 →] 弹窗选择 Docker / Windows
```

- 显示 active runtime、版本、PID、启动时间
- 切换按钮触发 `POST /api/runtime/switch`，显示进度
- 切换过程禁用所有写按钮（Stop / Restart / Save / Settings 保存）

#### 6.2.2 新增"运行时"面板（可选独立页或合并到概览）

显示：

- 当前 runtime 详情
- 切换历史（最近 10 次，从 `switch.log` 读取）
- 快照列表（最近 10 份，含类型、大小、时间、SHA-256）
- 手动创建快照按钮
- 恢复快照按钮（带确认对话框）
- Junction 状态（仅 windows active 时）

#### 6.2.3 概览页改动

- "Docker 状态"卡片改为"运行时状态"，按 active 显示对应字段
- CPU/内存卡片：Docker active 时用 `docker stats`；Windows active 时用 `Get-Process PalServer` + 工作集
- 端口监听卡片：实时检测 8211/8212/25575，与 runtime 匹配
- 隧道状态卡片：不变（SakuraFrp 与 runtime 无关）

#### 6.2.4 设置页改动

- 保存时显示"正在编译 INI..."进度
- 失败时显示编译日志摘要
- 顶部增加"配置漂移检测"指示：若 `.env` mtime > INI mtime 显示警告

#### 6.2.5 日志页改动

- 新增日志源切换：游戏（Docker 容器日志 / Windows 服务端日志）+ 面板 + SakuraFrp + 异常
- 切换 runtime 时日志源自动跟随

#### 6.2.6 Mod 页改动

- 兼容性状态从"仅 Docker 失败关闭"变为"按 active runtime 显示"
- Windows active 时启用 Sync 按钮（仍需 manifest 中哈希批准）

## 7. 受控官方 Mod 管理（Windows 运行时启用）

### 7.1 当前状态回顾

- `mods\manifest.json`：`managerEnabled=false`、`runtime=linux-docker`、`mods=[]`
- `Sync` 在 runtime 不是 `windows-dedicated` 时失败关闭
- 没有创建 `data\Mods\` 或 `data\mod-manager\` 目录

### 7.2 Windows 运行时启用后的变化

#### 7.2.1 manifest 字段扩展

```json
{
  "managerEnabled": false,
  "runtime": "windows-dedicated",
  "mods": [],
  "globalEnableMod": false,
  "modsRoot": "C:\\Services\\PalworldServer\\win-server\\Pal\\Mods",
  "workshopSourceRoot": "<本地 Steam Workshop 路径>",
  "palModSettingsPath": "C:\\Services\\PalworldServer\\win-server\\Pal\\Mods\\PalModSettings.ini"
}
```

- `managerEnabled` 仅在 Windows active 且 manifest 已配置至少一个 Mod 时自动设为 `true`；空清单在两种运行时下均保持 `false`
- `runtime` 字段自动随 `runtime.state` 更新

#### 7.2.2 启用流程

1. 用户在 Web Console 添加 Mod：填写 Workshop ID + PackageName
2. `mod-manager.ps1 -Action Validate`：检查 manifest 格式
3. 用户从本机 Steam 下载 Workshop 内容到 `<SteamLibrary>\steamapps\workshop\content\2394010\<WorkshopId>\`
4. `mod-manager.ps1 -Action Check`：
   - 读取源目录 `Info.json`
   - 校验 `IsServer=true`
   - 计算 `PackageName` 目录 SHA-256
   - 用户在 Web Console 看到 SHA-256，决定是否批准
5. 用户批准后写入 manifest `approvedHash` 字段
6. `mod-manager.ps1 -Action Sync`：
   - 备份当前 `win-server\Pal\Mods\`
   - 创建 `Mods\Workshop\<WorkshopId>\` 并复制文件
   - 写入 `Mods\PalModSettings.ini`：`bGlobalEnableMod=true` + `ActiveModList=<PackageName>`
   - 写入 incident `INFO` 级别
7. 重启 Windows runtime 使 Mod 生效

#### 7.2.3 失败关闭条件

- `managerEnabled=false` 时 Sync 拒绝
- `runtime` 不是 `windows-dedicated` 时 Sync 拒绝
- 任何源路径包含 reparse point 时拒绝
- SHA-256 不匹配时拒绝
- `Info.json` 缺失或 `IsServer != true` 时拒绝
- 依赖 Mod 未启用时拒绝

### 7.3 Mod 切换前快照

Mod 清单变更时（`mods\manifest.json` 的 `mods` 数组长度或哈希变化），`switch-runtime.ps1` 强制使用 Full 快照（不依赖 §3.2 的常规判断）。

### 7.4 Mod 禁用流程

用户禁用 Mod：

1. 从 manifest 移除该条目
2. `mod-manager.ps1 -Action Disable -Package <name>`：
   - 备份 `Mods\Workshop\<WorkshopId>\`
   - 删除目录
   - 更新 `PalModSettings.ini`
3. 重启 runtime

### 7.5 Mod 漂移检测

每次 Windows runtime Start 之前：

- 扫描 `win-server\Pal\Mods\Workshop\` 实际目录
- 与 manifest 中 `mods[].approvedHash` 比对
- 不一致时拒绝启动，写 incident `ERROR`

## 8. 备份、日志、状态监控统一

### 8.1 备份体系

| 类型 | 频率 | 实现 | 位置 |
|---|---|---|---|
| 日常备份 | 04:00 daily | Docker active: `docker compose exec palworld-server backup`；Windows active: `Invoke-WindowsRuntimeBackup` 先 REST save（仅本机 RCON 回退）再 tar SaveGames 与 Config | `data\backups\` |
| 切换快照 | 切换前后 | §3 描述 | `data\switch-snapshots\` |
| 启动前备份 | runtime Start 前 | Light 快照 | `data\switch-snapshots\` |
| 恢复前备份 | restore 前 | 完整 SaveGames 复制 | `data\restore-backup\` |

日常备份由 runtime provider 实现：

- `docker-runtime.ps1` 调用容器内置 backup 脚本（已有）
- `win-runtime.ps1` 实现（Windows 原生备份实测于 2026-07-31）：
  1. 调用 REST `/save`
  2. 等待 5s（落盘）
  3. `tar -czf data\backups\palworld-save-<timestamp>.tar.gz -C data\Pal\Saved SaveGames Config`
  4. 应用 `DELETE_OLD_BACKUPS=true` / `OLD_BACKUP_DAYS=5` 清理

### 8.2 日志体系

#### 8.2.1 日志源

| 源 | Docker active | Windows active |
|---|---|---|
| 游戏服务端 | `docker compose logs palworld-server` | `data\log-sources\windows-server\<date>.log` |
| Web Console | `data\log-sources\panel\<date>.log` | 同左 |
| SakuraFrp | frpc 日志（不变） | 同左 |
| Switch | `data\diagnostics\switch.log` | 同左 |
| Mod | `data\diagnostics\mod-manager.log` | 同左 |
| Incidents | `data\diagnostics\incidents.jsonl` | 同左 |

#### 8.2.2 Windows 服务端日志采集

`win-runtime.ps1` 将启动/停止生命周期事件写入
`data\log-sources\windows-runtime\<date>.log`。`PalServer.exe` 的 `-abslog` 目标为
`data\log-sources\windows-server\<date>.log`，但该引擎输出属于尽力采集；空文件或
缺少新行不能被解读为服务器未运行或日志已完整捕获。

`daily-log-collector.ps1` 扩展：

- 新增 `WINDOWS NATIVE RUNTIME` 生命周期区段和 `WINDOWS NATIVE ENGINE (BEST-EFFORT)`
  引擎区段；前者是本项目可验证事件，后者仅在引擎实际输出时出现。
- Docker 容器日志继续按原有方式归档，Windows 源不会覆盖 Docker 当日日志。

#### 8.2.3 日志归档保留

- `data\log-archive\YYYY-MM-DD.txt`：永久保留（与现状一致）
- `data\log-sources\game\*.log` 与 `data\log-sources\windows-server\*.log`：保留最近 14 天
- `data\diagnostics\*.log`：保留最近 30 天
- 清理由 `daily-log-collector.ps1` 启动时执行

### 8.3 状态监控

#### 8.3.1 仪表盘新增字段

```json
{
  "runtime": {
    "active": "docker",
    "switching": false,
    "version": "v1.0.1.100619",
    "pid": 12345,
    "startedAt": "2026-07-28T17:00:00+08:00"
  },
  "iniCompile": {
    "lastRun": "2026-07-28T17:30:00+08:00",
    "status": "ok",
    "driftDetected": false
  },
  "junction": {
    "exists": true,
    "target": "C:\\Services\\PalworldServer\\data\\Pal\\Saved\\SaveGames",
    "resolved": "C:\\Services\\PalworldServer\\data\\Pal\\Saved\\SaveGames",
    "ok": true
  },
  "snapshots": {
    "total": 8,
    "totalBytes": 524288000,
    "lastFull": "2026-07-28T17:30:00+08:00",
    "lastLight": "2026-07-28T18:00:00+08:00"
  }
}
```

#### 8.3.2 健康检查

`/api/state` 内部每 10 秒轮询一次当前 runtime 的 Health 接口，结果缓存。超过 3 次失败时：

- 写 incident `WARN`
- 仪表盘显示"运行时降级"
- 不自动重启（避免数据丢失）

#### 8.3.3 端口监听检测

新增端口检测函数 `Test-RuntimePorts`：

- UDP 8211：游戏端口，必须监听
- TCP 8212：REST API，必须监听且只绑定 127.0.0.1
- TCP 25575：RCON，必须监听且只绑定 127.0.0.1

Windows active 时额外校验防火墙规则存在：

```powershell
Get-NetFirewallRule -DisplayName "Palworld Block REST 8212 Public" |
  Select-Object Enabled, Action
```

### 8.4 incident 体系扩展

`incidents.jsonl` 新增类型：

- `switch-started` / `switch-completed` / `switch-failed`
- `snapshot-created` / `snapshot-failed` / `snapshot-retention`
- `ini-compiled` / `ini-compile-failed` / `ini-drift`
- `junction-failed` / `junction-recreated`
- `mod-sync` / `mod-rejected` / `mod-drift`
- `runtime-start-failed` / `runtime-health-failed`

所有 incident 字段保留 token/IP 脱敏规则。

## 9. 互斥、回退、灾难恢复

### 9.1 互斥锁实现

#### 9.1.1 文件锁 + 进程锁双层

```powershell
function Acquire-RuntimeMutex {
    param(
        [int]$TimeoutMs = 5000,
        [ValidateNotNullOrEmpty()][string]$MutexName = 'Global\PalworldServerRuntime'
    )
    $mutex = New-Object System.Threading.Mutex($false, $MutexName)
    if (-not $mutex.WaitOne($TimeoutMs)) {
        throw "无法获取 runtime 互斥锁（另一操作进行中）"
    }
    return $mutex
}
```

调用者必须用 `try/finally` 释放：

```powershell
$mutex = Acquire-RuntimeMutex
try {
    # critical section
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
```

#### 9.1.2 runtime.state 原子写入

```powershell
function Update-RuntimeState {
    param([hashtable]$Updates)
    $state = Get-RuntimeState
    foreach ($k in $Updates.Keys) { $state[$k] = $Updates[$k] }
    $json = $state | ConvertTo-Json -Compress
    $temp = "data\runtime.state.tmp"
    $final = "data\runtime.state"
    [System.IO.File]::WriteAllText("$PSScriptRoot\..\$temp", $json)
    Move-Item "$PSScriptRoot\..\$temp" "$PSScriptRoot\..\$final" -Force
}
```

### 9.2 回退路径

#### 9.2.1 自动回退

仅在切换流程步骤 7（Start 失败）触发：

1. 切换前 runtime 已停止
2. 新 runtime Start 失败
3. 自动尝试重启切换前 runtime
4. 若重启成功：runtime.state 回滚到切换前 active
5. 若重启失败：runtime.state active=none，等待人工

#### 9.2.2 手动回退

用户通过 Web Console 触发：

- 切换到任意 runtime（不限制必须切回原 runtime）
- 从快照恢复（restore-snapshot.ps1）

#### 9.2.3 灾难回退

当 runtime.state 损坏或丢失：

1. `verify-project.ps1` 检测到 runtime.state 不存在或 JSON 解析失败
2. 标记 active=unknown
3. Web Console 显示警告，禁止所有写操作
4. 用户运行 `scripts\recover-runtime-state.ps1`：
   - 检测 PalServer.exe 进程是否运行 → active=windows
   - 检测 docker 容器是否运行 → active=docker
   - 都没有 → active=none
5. 写入 runtime.state，恢复正常

### 9.3 存档损坏恢复

#### 9.3.1 检测

`Get-RuntimeHealth` 时额外校验：

- `SaveGames\0\<GUID>\Level.sav` 文件存在且 > 0 字节
- 最近一次自动备份（`SaveGames\0\<GUID>\backup\` 内最新一份）时间在 1 小时内
- 若运行时报告存档读取失败：标记 `corrupted=true`

#### 9.3.2 恢复

```text
1. Stop 当前 runtime（不调用 REST save，避免覆盖）
2. 创建当前损坏存档的 Light 快照（用于事后分析）
3. 从最近的 Full 快照恢复 SaveGames
4. 若没有 Full 快照：从 data\backups\<最近>.tar.gz 恢复
5. 若都没有：从 SaveGames\0\<GUID>\backup\<最近>\ 恢复（服务端自动备份）
6. 重启 runtime
7. 写 incident CRITICAL
```

### 9.4 SteamCMD 更新破坏 junction 的恢复

若 `verify-project.ps1` 或 `Assert-SaveGamesJunction` 检测到 junction 丢失：

1. 检查 `win-server\Pal\Saved\SaveGames\` 是否为真实目录且非空
   - 是：拒绝自动重建，要求人工确认（避免覆盖意外存在的真实存档）
2. 若为空目录或不存在：
   - `rmdir` 清理
   - 重新创建 junction
   - 写 incident `WARN`

## 10. 验证测试矩阵

### 10.1 单元测试

| 测试 | 命令 | 通过标准 |
|---|---|---|
| INI 编译幂等 | `compile-settings.ps1; compile-settings.ps1` | 两次输出 SHA-256 相同 |
| 双 INI 一致 | `compile-settings.ps1 -Validate` | 关键字段差异为 0 |
| Junction 重建 | 删 junction 后 `Assert-SaveGamesJunction` | junction 重新创建且 Resolve-Path 正确 |
| runtime.state 原子写 | 并发 10 个 `Update-RuntimeState` | 无损坏，最终值正确 |
| 互斥锁 | 并发调用 `Acquire-RuntimeMutex` | 仅 1 个成功，其余超时 |

### 10.2 集成测试

| 场景 | 步骤 | 通过标准 |
|---|---|---|
| Docker 启动 | `palworld.bat` | 容器 healthy、Web Console 可访问、REST 可用 |
| Windows 安装 | `install-win-server.ps1` | PalServer.exe 存在、junction 正确、INI 生成 |
| Windows 启动 | `switch-runtime.ps1 -To windows` | active=windows、REST /health 200、玩家可连 |
| 切换 Docker→Windows | `switch-runtime.ps1 -To windows` | 切换完成 ≤3min、快照创建、存档保留、玩家进度保留 |
| 切换 Windows→Docker | `switch-runtime.ps1 -To docker` | 同上 |
| 切换中互斥 | 切换运行时尝试启动另一 runtime | 被拒绝 |
| 切换前 REST save | 切换后比对玩家进度 | 进度一致 |
| 切换前快照 | 切换后比对 SaveGames 树 SHA-256 | 一致 |
| 配置漂移检测 | 手动改 `.env` 后 `verify-project.ps1` | 警告出现 |
| 配置编译 | Web Console 保存设置 | 两份 INI 同步更新 |
| Mod 同步 | manifest 中添加 Mod 后 Sync | Mod 文件复制、PalModSettings.ini 更新、重启后生效 |
| Mod 漂移 | 手动改 Workshop 目录后启动 | 拒绝启动 |
| 快照恢复 | `restore-snapshot.ps1 -Name <full>` | SaveGames 回到快照时刻 |
| 灾难恢复 | 删 runtime.state 后 `recover-runtime-state.ps1` | runtime.state 重建 |
| 存档损坏恢复 | 损坏 Level.sav 后启动 | 检测到损坏，从备份恢复 |

### 10.3 性能基线

| 指标 | 目标 |
|---|---|
| 切换 Docker→Windows 总时长 | ≤3 分钟 |
| 切换 Windows→Docker 总时长 | ≤3 分钟 |
| Light 快照创建 | ≤5 秒 |
| Full 快照创建 | ≤30 秒 |
| INI 编译 | ≤2 秒 |
| Junction 创建 | ≤1 秒 |
| Web Console 响应（active runtime 任意） | ≤500 ms |

### 10.4 验收测试（端到端）

1. 启动 Docker，玩家进入，建造若干结构
2. 切换到 Windows，玩家重新进入，验证建筑保留
3. 在 Windows runtime 修改设置（EXP_RATE 0.7→1.5）
4. 验证两份 INI 同步更新
5. 重启 Windows runtime，设置生效
6. 切换回 Docker，验证设置仍生效
7. 触发一次日常备份
8. 手动损坏 `Level.sav`，触发恢复流程
9. 添加一个 Mod（测试用），Sync，验证 Mod 生效
10. 全程 Web Console 可访问，日志完整归档

## 11. 实施步骤与里程碑

### 11.1 里程碑划分

| 里程碑 | 内容 | 验收标准 |
|---|---|---|
| M1: 基础设施 | runtime.state、Mutex、IRuntimeProvider 接口、docker-runtime.ps1 封装现有逻辑 | Docker 行为与改造前完全一致 |
| M2: INI 编译器 | compile-settings.ps1、双 INI 生成、verify-project.ps1 扩展、Web Console POST 后立即编译 | 两份 INI 内容一致、漂移检测工作 |
| M3: Windows 安装 | install-win-server.ps1、SteamCMD 下载、PalServer.exe 启动、防火墙规则 | Windows 服务端可独立启动、REST 可用 |
| M4: Junction | Assert-SaveGamesJunction、verify 校验、SteamCMD 更新后修复 | Junction 在各种破坏场景下能恢复 |
| M5: Windows runtime 完整 | win-runtime.ps1 全部操作、日志采集、daily-log-collector 扩展 | Windows active 时 Web Console 全功能可用 |
| M6: 快照系统 | Light/Full 快照、manifest.json、retention、restore-snapshot.ps1 | 切换前后快照创建、恢复流程工作 |
| M7: 切换流程 | switch-runtime.ps1 完整实现、回退路径、switch.log | 所有切换场景通过集成测试 |
| M8: Web Console 改造 | 运行时指示器、新 API、异步任务、概览/设置/日志/Mod 页改动 | 前后端通过 ui-smoke.cjs 回归 |
| M9: Mod 管理 | manifest 扩展、Check/Sync/Disable 适配 Windows、漂移检测 | Mod 同步与禁用完整流程通过 |
| M10: 灾难恢复 | recover-runtime-state.ps1、存档损坏检测与恢复、文档更新 | 所有灾难场景演练通过 |

### 11.2 实施顺序

严格按 M1→M10 顺序，每个里程碑完成后做集成测试再进入下一个。M1–M4 可在不停服情况下开发（不影响现有 Docker）。M5 开始需要在维护窗口内测试 Windows 启动。

### 11.3 文档同步

每个里程碑完成后更新：

- `README.md`：新增 Windows 启动方式、切换命令
- `AGENTS.md`：记录决策与状态
- `docs/architecture.md`：当前公开架构和安全边界
- `docs/runtime-switch-design.md`（本文件）：标注实施进度
- `docs/change-archive.md`：公开变更记录

### 11.3.1 实施进度（截至 2026-07-28）

| 里程碑 | 状态 | 备注 |
|---|---|---|
| M1: 基础设施 | ✅ 已完成 | `runtime-common.ps1`、`docker-runtime.ps1`、runtime.state/Mutex/事件日志 |
| M2: INI 编译器 | ✅ 已完成 | `compile-settings.ps1` 118 字段映射、`verify-project.ps1` 双 INI 校验 |
| M3: Windows 安装 | ✅ 已完成 | `install-win-server.ps1` SteamCMD 下载与配置 |
| M4: Junction | ✅ 已完成 | `Assert-SaveGamesJunction`、`Test-SaveGamesJunction`、verify 校验（Target 属性） |
| M5: Windows runtime 完整 | ✅ 已完成 | `win-runtime.ps1` 全部 Provider 方法、日志异步重定向 |
| M6: 快照系统 | ✅ 已完成 | Light/Full 快照、`manifest.json`、retention、`restore-snapshot.ps1` |
| M7: 切换流程 | ✅ 已完成 | `switch-runtime.ps1` 完整实现、回退路径、switch.log |
| M8: Web Console 改造 | ✅ 已完成 | 顶栏指示器、运行时面板、快照列表、Junction 卡、异步任务轮询、`Get-Dashboard` runtime-aware 路由 |
| M9: Mod 管理 | ✅ 已完成 | `Test-ModDrift`、`Sync-ModManifestRuntime`、`switch-runtime.ps1` 调用、verify 校验扩展 |
| M10: 灾难恢复 | ✅ 已完成 | `recover-runtime-state.ps1`、`Test-SaveGamesIntegrity`、verify 灾难恢复段（stuck switching、进程跨检、双 runtime 互斥、快照目录一致性） |
| 端到端演练 | ✅ 已完成 (2026-07-30) | Docker→Windows→Docker 双向切换 + 临时副本 restore 演练完成；三份证据 JSON 全部通过 verify-maintenance-evidence.ps1 校验 |

### 11.4 回滚策略

若实施过程中发现 Windows 方案不可行：

1. 不删除已开发的脚本（保留为参考）
2. `runtime.state` 强制写 `active=docker`
3. `palworld.bat` 改回只启动 Docker
4. Web Console 回退到改造前的 `settings-panel.ps1`（从 git 恢复）
5. 写 incident 记录失败原因
6. 不影响现有 Docker 服务端运行

## 12. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| Junction 被外部工具误删 | Windows 服务端读到空目录，可能写入新存档覆盖 | Start 前 `Assert-SaveGamesJunction`、`verify-project.ps1` 检测、incident 告警 |
| SteamCMD 更新重置 win-server | Junction 丢失、INI 丢失 | 启动前校验、自动重建 junction、自动重编译 INI |
| 两个 runtime 同时启动 | 端口冲突、存档竞争 | Mutex + runtime.state + 启动前端口检测 |
| 切换中 Web Console 重启 | runtime.state `switching=true` 卡住 | 启动时检测 `switching=true` 且超过 5 分钟 → 强制回退到 `switching=false` 并 incident |
| Windows 服务端绑定 0.0.0.0 暴露 RCON | 远程 RCON 控制风险 | install-win-server.ps1 自动创建防火墙 Block 规则、Web Console 校验规则存在 |
| INI 编译失败 | runtime 无法启动 | 编译失败不更新 INI（保留旧版）、Web Console 显示错误、不切换 active |
| 快照磁盘占用增长 | 磁盘满 | §3.4 三层控制：分类 + 总量上限 + LZMA 压缩 |
| Mod 包含恶意代码 | 服务端被入侵 | 仅本机 Steam Workshop 源、SHA-256 人工批准、`IsServer=true` 校验、不自动下载 |
| 切换前后版本不一致 | 存档读取失败 | runtime.state 记录 version、切换前比对、不一致时强制 Full 快照 + 警告 |
| restore-snapshot.ps1 误用 | 覆盖现有存档 | 强制 active=none、创建恢复前临时快照、确认对话框 |
| 并发 API 调用 | runtime.state 损坏 | Mutex + 原子文件写入 |
| Windows 服务端崩溃后自动重启循环 | 反复写入损坏存档 | 不自动重启、写 incident、等待人工 |
| Docker Desktop 在切换期间异常 | 切换卡死 | 切换超时机制、回退路径 |

## 13. 文件清单（新增 / 修改）

### 13.1 新增文件

| 路径 | 用途 |
|---|---|
| `scripts\compile-settings.ps1` | 统一 INI 编译器 |
| `scripts\switch-runtime.ps1` | 运行时切换 |
| `scripts\docker-runtime.ps1` | Docker provider |
| `scripts\win-runtime.ps1` | Windows provider |
| `scripts\install-win-server.ps1` | SteamCMD 安装器 |
| `scripts\restore-snapshot.ps1` | 快照恢复 |
| `scripts\recover-runtime-state.ps1` | runtime.state 灾难恢复 |
| `scripts\win-runtime.ps1` | Windows provider，包含 REST-first 的 Windows 日常备份 |
| `docs\runtime-switch-design.md` | 本文件 |

### 13.2 修改文件

| 路径 | 改动 |
|---|---|
| `palworld.bat` | 启动前读 runtime.state，按 active 启动对应 runtime |
| `settings-panel.ps1` | 路由层、新 API、运行时抽象 |
| `web\index.html` | 运行时指示器、新面板、API 适配 |
| `scripts\settings-catalog.ps1` | 不变（已是单一 schema） |
| `scripts\daily-log-collector.ps1` | 新增 windows-server 日志源 |
| `scripts\mod-manager.ps1` | 适配 Windows runtime、manifest 字段扩展 |
| `scripts\verify-project.ps1` | 新增双 INI 校验、junction 校验、runtime.state 校验 |
| `mods\manifest.json` | 字段扩展（managerEnabled、runtime 动态化） |
| `mods\manifest.schema.json` | 新字段约束 |
| `mods\README.md` | Windows 启用流程 |
| `docker-compose.yml` | 不变 |
| `.env.example` | 不变 |
| `README.md` | 新增 Windows 启动章节 |
| `AGENTS.md` | 记录运行时切换决策 |

### 13.3 不变文件（保持原样）

- `.env`（运行时数据，不入版本控制）
- `data\backups\` 内容
- `data\log-archive\` 内容
- `docker-compose.yml`（Docker 配置不变，只在 active=docker 时使用）

## 14. 开放问题（实施前需确认）

1. **SteamCMD 安装路径**：默认使用项目目录下的 `steamcmd\` 与 `win-server\`，是否需要可配置？
2. **Windows 防火墙规则命名**：建议 `Palworld Block REST 8212 Public` / `Palworld Block RCON 25575 Public`，是否与现有命名约定一致？
3. **Mod 默认 `managerEnabled`**：Docker active 时设 false，Windows active 时设 true。是否需要在 manifest.json 中保留 `userOverride` 字段，允许用户强制禁用？
4. **快照保留策略默认值**：Full 3 份 + 1GB / Light 10 份。是否需要 Web Console 设置页提供调整入口？
5. **Windows 服务端版本固定方式**：Docker 用 image digest 固定；Windows 是否需要通过 SteamCMD `app_update 2394010 -beta <branch>` 固定版本？默认行为是跟随最新。
6. **Palworld 客户端兼容性**：Docker 与 Windows 服务端版本可能不一致，是否需要在切换前强制校验客户端版本？
7. **首次 Windows 启动**：是否允许"冷启动"（无 Docker 状态参考），还是必须从 Docker 切换一次以验证存档兼容？

## 15. 附录：关键 PowerShell 函数签名

### 15.1 IRuntimeProvider 接口

```powershell
# 所有 provider 必须实现以下函数（命名约定：<Provider>Runtime<Action>）
function Start-DockerRuntime    { ... }
function Stop-DockerRuntime     { param([int]$Grace=120) ... }
function Get-DockerRuntimeHealth { ... }
function Invoke-DockerRuntimeSave { param([int]$Timeout=30) ... }
function Get-DockerRuntimeVersion { ... }
function Get-DockerRuntimePlayers { ... }
function Get-DockerRuntimeLogs    { param([int]$Lines=300) ... }
function Get-DockerRuntimeSettings { ... }
function Invoke-DockerRuntimeBackup { ... }

function Start-WindowsRuntime    { ... }
function Stop-WindowsRuntime     { param([int]$Grace=120) ... }
function Get-WindowsRuntimeHealth { ... }
function Invoke-WindowsRuntimeSave { param([int]$Timeout=30) ... }
function Get-WindowsRuntimeVersion { ... }
function Get-WindowsRuntimePlayers { ... }
function Get-WindowsRuntimeLogs    { param([int]$Lines=300) ... }
function Get-WindowsRuntimeSettings { ... }
function Invoke-WindowsRuntimeBackup { ... }
```

### 15.2 通用 runtime 路由

```powershell
function Invoke-RuntimeAction {
    param(
        [ValidateSet('Start','Stop','Health','Save','Version','Players','Logs','Settings','Backup')]
        [string]$Action,
        [int]$Timeout = 30,
        [int]$Lines = 300,
        [int]$Grace = 120
    )
    $state = Get-RuntimeState
    if ($state.active -eq 'none') { throw "无 active runtime" }
    $provider = if ($state.active -eq 'docker') { 'Docker' } else { 'Windows' }
    $fn = "Invoke-${provider}Runtime$Action" -replace 'Start$','Start' -replace 'Stop$','Stop'
    # 实际通过 Invoke-Expression 或 switch 调用具体函数
    ...
}
```

### 15.3 快照函数

```powershell
function New-SwitchSnapshot {
    param(
        [ValidateSet('Light','Full')][string]$Type,
        [ValidateSet('pre','post')][string]$Phase,
        [string]$From, [string]$To
    )
    # 创建 tar.gz，更新 manifest.json
}

function Invoke-SnapshotRetention {
    # 按 §3.4 策略清理
}

function Restore-Snapshot {
    param([string]$Name, [switch]$Force)
    # 按 §3.6 流程
}
```

### 15.4 runtime.state 函数

```powershell
function Get-RuntimeState {
    $path = 'data\runtime.state'
    if (-not (Test-Path $path)) {
        return @{ active='none'; switching=$false }
    }
    Get-Content $path -Raw | ConvertFrom-Json -AsHashtable
}

function Update-RuntimeState {
    param([hashtable]$Updates)
    # 原子写入
}

function Test-RuntimeSwitching {
    $state = Get-RuntimeState
    if ($state.switching -and $state.lastSwitchAt) {
        $elapsed = (Get-Date) - [datetime]$state.lastSwitchAt
        if ($elapsed.TotalMinutes -gt 5) {
            Write-Warning "切换状态卡住超过 5 分钟，强制重置"
            Update-RuntimeState @{ switching=$false }
            Write-Incident -Level WARN -Message "switching flag 卡住被重置"
            return $false
        }
        return $true
    }
    return $false
}
```

---

## 文档结束

本文件描述完整的设计，可作为新会话实施的依据。任何实施过程中的偏差应通过以下方式处理：

- 微小偏差（实现细节）：直接实施，记录到 change-archive.md
- 中等偏差（接口/字段）：更新本文件 + 提交 git
- 重大偏差（架构选择）：先回到设计讨论，确认后再实施
