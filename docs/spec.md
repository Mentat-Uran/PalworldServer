# Palworld Dedicated Server on Docker + SakuraFrp 设计文档

- 日期：2026-07-27
- 目标：在 Windows 11 主机内通过 Docker（基于 WSL2 后端）部署 Palworld dedicated server，并通过 SakuraFrp 内网穿透让外网朋友接入。同机同时运行 Palworld 客户端。
- 在线人数上限：8 人（实际预期 6 人，留 2 人余量）

> 2026-07-28 审计说明：本文保留方案选择与设计背景；当前操作方法以根目录 `README.md` 为准。下列部署片段已按实际镜像变量和安全修复更新。

## 1. 背景与硬件

| 项 | 值 |
|---|---|
| 主机 CPU | AMD Ryzen 7 9700X（8 物理核 / 16 逻辑线程，Zen5） |
| 主机内存 | 48 GB |
| 操作系统 | Windows 11 专业版 24H2（Build 26200） |
| WSL 版本 | WSL2，已安装 `Ubuntu-24.04` 与 `docker-desktop` 发行版 |
| Docker | Docker Desktop（基于 WSL2 后端） |
| 已有 Palworld 客户端 | 是，位于 `d:\SteamLibrary\steamapps\common\Palworld` |
| 同时负载 | Palworld 客户端 + Docker 内 dedicated server + SakuraFrp Windows 启动器 |

资源核算（Docker 容器限 6 CPU / 8 GB 内存 + 4 GB swap）：
- WSL2 memory 上限 24 GB（用户日常也跑 MC 服务器，保留余量；WSL2 内存为上限非预留，不用则还回 Windows）
- WSL2 processors=6，容器上限与之一致
- Windows 端逻辑线程剩 10（16-6），日常峰值：系统 1-2 + 客户端 2-4 + SakuraFrp ≈0 = 5-6 线程，余量充足
- Docker 内 dedicated server 峰值约 3 逻辑线程 + 5 GB
- Docker Desktop 自身开销约 1-2 GB（daemon + containerd）

## 2. 方案选择

经对比四个候选方案：
- 方案 A：WSL2 + systemd（**备选 fallback**，详见附录 A）
- 方案 B：WSL2 + Docker + 社区镜像（**选定**）
- 方案 C：WSL2 + Docker + Pterodactyl（不推荐，对单服过度设计）
- 方案 D：主机 Windows 原生跑 dedicated server（不推荐，进程隔离弱）

选 B 的核心理由：
1. 自己玩 Palworld 时走 `127.0.0.1:8211`，不占 SakuraFrp 隧道带宽
2. 9700X + 48 GB 资源过剩，限容器后主机仍有富余
3. 社区镜像 `thijsvanloef/palworld-server-docker` 已封装 backup / auto-update / RCON / settings 等逻辑，比手写 systemd + bash 更省心
4. Docker 镜像化部署声明式、可复现，迁移到其他机器成本低
5. Docker Desktop 依赖 WSL2 后端，所以 Docker 不是 WSL2 的替代而是其上的一层抽象，资源开销增加 1-2 GB，但换来管理便利性

## 3. 整体架构

```
┌─────────────────────────────────────────────────────────┐
│  Windows 11 主机 (Ryzen 7 9700X / 48GB)                 │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Docker Desktop (WSL2 后端)                       │  │
│  │   ┌────────────────────────────────────────┐     │  │
│  │   │  palworld-server 容器                   │     │  │
│  │   │   - thijsvanloef/palworld-server-docker │     │  │
│  │   │   - SteamCMD + PalworldServer           │     │  │
│  │   │   - UDP 8211 暴露到主机 127.0.0.1        │     │  │
│  │   │   - 内置 cron 自动备份                   │     │  │
│  │   │   - 内置 RCON 管理                       │     │  │
│  │   │   - /palworld 挂载到 Windows 文件系统    │     │  │
│  │   └────────────────────────────────────────┘     │  │
│  └──────────────────────────────────────────────────┘  │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Windows 原生进程                                 │  │
│  │   - Palworld 客户端 (连 127.0.0.1:8211)          │  │
│  │   - SakuraFrp 启动器 (Windows 版)                │  │
│  │   - 启动/停止 bat 脚本                            │  │
│  └──────────────────────────────────────────────────┘  │
└──────────────────────────┬──────────────────────────────┘
                           │
                  ┌────────┴────────┐
                  │  SakuraFrp 隧道  │
                  │  (Windows 启动)  │
                  └────────┬─────────┘
                           │
                  公网朋友连 SakuraFrp 节点
```

核心组件：
1. **Docker Desktop**：基于 WSL2 后端运行容器
2. **palworld-server 容器**：使用固定摘要的 `thijsvanloef/palworld-server-docker` 社区镜像，通过环境变量配置游戏参数，通过 Docker Compose 声明式部署
3. **数据卷挂载**：容器内 `/palworld` 挂载到 Windows 本地路径（如 `C:\Services\PalworldServer\data`），方便直接查看存档、备份、mod
4. **Windows 端 SakuraFrp 启动器**：隧道目标 `127.0.0.1:8211`（容器端口已映射到主机 localhost）
5. **一键启动 bat**：双击即可拉起容器 + SakuraFrp 隧道

## 4. WSL2 / Docker Desktop 配置

### 4.1 `.wslconfig`（放在 `C:\Users\<用户名>\.wslconfig`）

```ini
[wsl2]
memory=24GB
processors=6
swap=32GB
swapFile=C:\\temp\\wsl-swap.vhdx
networkingMode=mirrored
firewall=false

[experimental]
hostAddressLoopback=true
dnsTunneling=true
autoProxy=true
```

要点：
- `memory=24GB`：WSL2 总内存上限（用户同机也跑 MC 服务器，保留余量；WSL2 内存为上限非预留，闲置时还回 Windows）
- `processors=6` / `swap=32GB`：WSL2 后端总 CPU 与 swap 上限，与容器 6 CPU 限制对齐
- `networkingMode=mirrored`：让容器端口直接映射到 Windows localhost，从而 Windows 端可 `127.0.0.1:8211` 直连
- `firewall=false`：避免 Windows Defender 阻断 mirrored 端口

修改后需 `wsl --shutdown` 重启 WSL2 实例生效。

### 4.2 Docker Desktop 设置

- Settings → Resources → WSL Integration：启用 `docker-desktop` 与 `Ubuntu-24.04`（如需在 Ubuntu shell 内用 docker 命令）
- Settings → Resources → Advanced：保持默认（已在 `.wslconfig` 限制）

### 4.3 不需要单独配 Ubuntu-24.04

虽然 `wsl -l -v` 显示有 `Ubuntu-24.04`，但 Docker 方案下不需要在这个发行版里装任何东西。Palworld server 跑在 `docker-desktop` 内的容器里。`Ubuntu-24.04` 可保留作为日常 Linux shell 用，但与服务器部署无关。

## 5. Palworld Dedicated Server 部署

### 5.1 目录与文件

| 路径 | 用途 |
|---|---|
| `C:\Services\PalworldServer\` | 服务器根目录 |
| `C:\Services\PalworldServer\docker-compose.yml` | 容器编排配置 |
| `C:\Services\PalworldServer\.env` | 环境变量（含密码，不入版本控制） |
| `C:\Services\PalworldServer\data\` | 容器内 `/palworld` 的挂载点，存档、配置、mod 都在这里 |
| `C:\Services\PalworldServer\data\backups\` | 容器自动备份输出目录 |

为什么放 `C:\Services\PalworldServer\`：
- C 盘空间充足（用户报告 1-2 TB 余量），无需担心占满
- 不放在 Palworld 客户端目录（`D:\SteamLibrary\steamapps\common\Palworld`）下，避免 Steam 验证/误删
- 路径无空格无中文，bat 脚本写起来不用引号包裹，避免引号 bug
- NTFS 直接挂载到容器，性能与 vhdx 相当
- 用 `Services` 子目录统管未来可能新增的其他服务，便于维护

### 5.2 镜像选择

使用 `thijsvanloef/palworld-server-docker`，部署时固定到已验证镜像摘要：
- GitHub: https://github.com/thijsvanloef/palworld-server-docker
- Docker Hub: `thijsvanloef/palworld-server-docker`
- 特性：
  - 自动备份（cron + rcon graceful save）
  - 自动更新（启动时检查 SteamCMD）
  - RCON 支持（管理命令远程执行）
  - 环境变量配置游戏参数
  - 多架构支持（amd64 / arm64）

镜像信任评估：第三方社区镜像，Dockerfile 公开可审计，但仍需固定摘要并在更新前审查发行说明。

### 5.3 `docker-compose.yml`

`C:\Services\PalworldServer\docker-compose.yml`：

```yaml
services:
  palworld-server:
    image: thijsvanloef/palworld-server-docker@sha256:401d3eb5c053bcd72949e1ede8c4e38be5e5ad66be7272ac37940706df0aeb2f
    container_name: palworld-server
    restart: unless-stopped
    stop_grace_period: 2m
    ports:
      - target: 8211        # 游戏端口 UDP
        published: 8211
        protocol: udp
      - target: 25575        # RCON 端口 TCP
        published: 25575
        host_ip: 127.0.0.1
        protocol: tcp
    env_file:
      - .env
    volumes:
      - ./data:/palworld/
    memswap_limit: 12G       # memory(8G) + swap(4G) 总和
    deploy:
      resources:
        limits:
          cpus: '6'
          memory: 8G
```

要点：
- `restart: unless-stopped`：容器崩溃自动重启，相当于 systemd 的 `Restart=on-failure`
- TCP 25575 只绑定 `127.0.0.1`；REST 8212 不映射到主机
- `cpus: '6'` / `memory: 8G` / `memswap_limit: 12G`：容器资源限制（8 GB 内存 + 4 GB swap），CPU 与 `.wslconfig` processors 一致
- 不映射 query 端口 27015：小服不需要服务器列表发现，靠 IP 直连即可

### 5.4 `.env` 文件

`C:\Services\PalworldServer\.env`：

```env
# === 基础配置 ===
TZ=Asia/Shanghai
PORT=8211
PLAYERS=8
SERVER_NAME=Palworld-Docker
SERVER_DESCRIPTION=Private Server
ADMIN_PASSWORD=CHANGE_ME_ADMIN_PWD
SERVER_PASSWORD=
PUBLIC_PORT=8211

# === 游戏参数 ===
COOP_PLAYER_MAX_NUM=8
EXP_RATE=2.0
DAYTIME_SPEEDRATE=0.5
NIGHTTIME_SPEEDRATE=1.0
DEATH_PENALTY=None

# === 自动更新 ===
UPDATE_ON_BOOT=true

# === 自动备份 ===
BACKUP_ENABLED=true
BACKUP_CRON_EXPRESSION=0 4 * * *
DELETE_OLD_BACKUPS=true
OLD_BACKUP_DAYS=5

# === RCON ===
RCON_ENABLED=true
RCON_PORT=25575
REST_API_ENABLED=true
REST_API_PORT=8212
```

要点：
- `ADMIN_PASSWORD` 必须部署时替换为强密码；镜像使用它进行 RCON/REST 管理认证
- `UPDATE_ON_BOOT=true`：容器启动时跑 SteamCMD 检查更新（与方案 A 的 ExecStartPre 等价）
- `BACKUP_ENABLED=true` + cron：镜像内置 cron 备份，默认每天凌晨 4 点
- `DELETE_OLD_BACKUPS=true` + `OLD_BACKUP_DAYS=5`：删除超过 5 天的备份

### 5.5 第一次启动

```powershell
cd C:\Services\PalworldServer
docker compose up -d
# 首次会拉取镜像（约 2GB）并下载 Palworld server（约 5GB），耗时 10-30 分钟
docker compose logs -f
# 看到 "Setting breakpad minidump AppID" 或 "[Online]_reservation" 等字样表示 server 已就绪
```

### 5.6 备份策略调整

社区镜像默认按天数保留备份，用户要求"保留 5 份轮流"。

两个方案：

**方案 1：用镜像默认（按天保留）**
- 设 `DELETE_OLD_BACKUPS=true` 和 `OLD_BACKUP_DAYS=5`
- 实际效果：保留最近 5 天的备份（每天 1 份）
- 优点：开箱即用
- 缺点：如果某天没启动容器，那一天的备份缺失；如果一天内多次重启，可能多份

**方案 2：自定义备份脚本（轮转 5 份）**
- 在容器外（Windows 端）写一个 PowerShell 脚本，调用 `docker compose exec` 触发 RCON 保存 + 复制存档
- 保留最近 5 份 tar 包
- 优点：精确控制份数
- 缺点：需要自己维护脚本

**推荐方案 1**：小服按天保留 5 份已经够用，简单可靠。如果之后发现备份频率不够，再切方案 2。

`.env` 调整：
```env
DELETE_OLD_BACKUPS=true
OLD_BACKUP_DAYS=5
```

### 5.7 调整游戏参数

当前镜像支持通过 `.env` 生成 `PalWorldSettings.ini`。优先使用根目录 Web Console 或直接修改 `.env`，然后执行：

```powershell
docker compose up -d --force-recreate palworld-server
```

关键参数：
- `PLAYERS=8` / `COOP_PLAYER_MAX_NUM=8`：上限 8 人
- `EXP_RATE=2.0`：双倍经验
- `DEATH_PENALTY=None`：死亡无掉落
- `DAYTIME_SPEEDRATE=0.5`：白天持续时间约为默认的两倍
- 其余参数沿用官方默认，便于后续按需调整

不要使用 `MAX_PLAYERS`、`SERVER_SETTINGS_*`、`BACKUP_RETENTION_DAYS` 或 `RCON_PASSWORD`；这些曾导致界面显示已配置但生成 ini 仍采用默认值。

### 5.8 防火墙

Windows Defender 防火墙只需放行 UDP 8211 入站：

```powershell
# 管理员 PowerShell
New-NetFirewallRule -DisplayName "Palworld Server UDP 8211" `
  -Direction Inbound -Protocol UDP -LocalPort 8211 -Action Allow

# RCON 已由 Docker 绑定到 127.0.0.1，不创建 RCON 入站放行规则。
```

### 5.9 本地连通性测试

启动容器后，在 Windows 端：
1. 启动 Palworld 客户端
2. 多人游戏 → 添加服务器 → `127.0.0.1:8211`
3. 应能看到 `ServerName="Palworld-Docker"` 并进入

成功标志：能进游戏、能创建角色、能存档、重连后存档保留。

## 6. SakuraFrp 内网穿透

### 6.1 账号与节点

- 用户已有 SakuraFrp 免费账号
- 策略：先用免费节点跑通，体验不足再升级付费节点
- 节点选择标准：
  - 支持 UDP（Palworld dedicated server 走 UDP 8211）
  - 国内节点（朋友大多在国内）
  - 延迟 < 50 ms，带宽 ≥ 10 Mbps

免费节点注意事项：
- 部分免费节点不支持 UDP，需在 SakuraFrp 控制台筛选
- 免费节点可能有连接数限制（通常 1-3 个），8 人服足够
- 高峰期可能限速

### 6.2 Windows 启动器安装

1. 从 SakuraFrp 官网下载 Windows 启动器（`SakuraFrpLauncher.exe`）
2. 安装到默认路径或自定义路径
3. 启动后登录账号

### 6.3 隧道配置

在 SakuraFrp Web 控制台或启动器内新建隧道：

| 字段 | 值 |
|---|---|
| 隧道类型 | UDP |
| 本地 IP | `127.0.0.1` |
| 本地端口 | `8211` |
| 远程端口 | 自动分配或指定 |
| 节点 | 选支持 UDP 的国内免费节点 |

启动器启动隧道后，会得到一个公网访问地址 `<节点域名>:<远程端口>`，把这个地址发给朋友。

朋友在 Palworld 客户端添加服务器时填 `<节点域名>:<远程端口>` 即可加入。

注意：**不要穿透 RCON 端口 25575**，否则任何人都能用 RCON 控制你的服务器。

### 6.4 一键启动 bat 脚本

放在桌面，双击即可拉起容器 + SakuraFrp 隧道。

`start-palworld-server.bat`：

```bat
@echo off
chcp 65001 >nul
title Palworld Server Launcher

echo [1/3] 启动 Palworld Docker 容器...
cd /d C:\Services\PalworldServer
docker compose up -d

echo [2/3] 等待 server 就绪...
:wait
for /f "delims=" %%i in ('docker inspect -f "{{.State.Running}}" palworld-server 2^>nul') do set STATE=%%i
if /i not "%STATE%"=="true" (
    timeout /t 2 /nobreak >nul
    goto wait
)

echo [3/3] 启动 SakuraFrp 启动器...
start "" "C:\path\to\SakuraFrpLauncher.exe"

echo.
echo Palworld server 已启动。
echo 本机连接：127.0.0.1:8211
echo 朋友连接：见 SakuraFrp 启动器内的隧道地址
echo.
pause
```

注意：
- 路径 `C:\path\to\SakuraFrpLauncher.exe` 需替换为实际安装路径
- `docker inspect` 检测容器运行状态，比端口探测可靠（Palworld 走 UDP，TCP 探测无效）
- 容器 "Running" 不等于 "server 就绪"，server 内部 SteamCMD 还在跑。实际可用还要看 `docker compose logs -f` 等待日志出现 "Started Server"

### 6.5 停止脚本

`stop-palworld-server.bat`：

```bat
@echo off
chcp 65001 >nul
title Palworld Server Stopper

echo [1/2] 关闭 SakuraFrp 启动器...
taskkill /IM SakuraFrpLauncher.exe /F 2>nul

echo [2/2] 停止 Palworld Docker 容器（会触发镜像内置优雅关闭）...
cd /d C:\Services\PalworldServer
docker compose stop -t 120 palworld-server

echo.
echo Palworld server 已停止。
echo.
pause
```

`docker compose stop -t 120 palworld-server` 会向容器发停止信号并最多等待 120 秒。修复前的默认 10 秒超时曾在 SteamCMD 校验期间产生退出码 137。

## 7. 闪退防范措施

汇总：

| 措施 | 实现位置 | 说明 |
|---|---|---|
| 容器自动重启 | `docker-compose.yml` 的 `restart: unless-stopped` | 容器崩溃自动重启 |
| 启动时自动更新 | `.env` 的 `UPDATE_ON_BOOT=true` | 保持 server 与客户端版本一致 |
| 优雅停止 | `stop_grace_period: 2m` | `docker compose stop -t 120` |
| 自动备份 | `.env` 的 `BACKUP_ENABLED=true` + cron | 每天凌晨 4 点自动备份 |
| 备份保留 5 天 | `DELETE_OLD_BACKUPS=true` + `OLD_BACKUP_DAYS=5` | 删除超过 5 天的备份 |
| 资源限制 | `docker-compose.yml` 的 `cpus/memory` + `.wslconfig` | 避免容器抢占主机资源 |
| 本机管理 | REST 优先，RCON 兼容 | Web Console 只监听 localhost |
| 日志观察 | `docker compose logs -f` | 实时查看 server 输出 |
| 镜像签名校验 | 部署时 `docker image inspect` 确认 digest | 防止供应链攻击（可选） |

崩溃兜底：镜像内置的 `restart: unless-stopped` 已覆盖大多数崩溃场景。容器重启后 SteamCMD 会再次跑更新检查（`UPDATE_ON_BOOT=true`），相当于自动恢复。

## 8. Mod 支持（架构预留）

当前不安装任何 Mod，但保留以后迁移运行时后可使用的受控管理层。

### 8.1 官方机制与当前边界

Palworld 1.0 的官方服务端 Mod 使用：

- 服务端可执行文件旁的 `Mods\Workshop\<WorkshopId>\Info.json`
- `Mods\PalModSettings.ini`
- `bGlobalEnableMod=true`
- 每个启用包一行 `ActiveModList=<PackageName>`

官方文档当前限定 Windows dedicated server。项目现有 `thijsvanloef/palworld-server-docker` 是 Linux 容器，因此不能把“目录存在”当成可用性证据，也不允许在当前运行时执行同步。

### 8.2 预留管理层

项目实现：

- `mods\manifest.json`：`managerEnabled=false`、`runtime=linux-docker`、空清单
- `mods\manifest.schema.json`：字段、路径片段、Workshop ID 与 SHA-256 约束
- `scripts\mod-manager.ps1`：Status / Validate / Hash / Check / Sync / Enable / Disable
- Web Console：只读状态、检查与受保护同步入口

管理器不会下载 Workshop 内容。未来只从本机 Steam Workshop 目录读取，并要求：

1. `Info.json` 直接位于源目录。
2. `PackageName` 与清单一致。
3. 安装规则包含 `IsServer=true`。
4. 目录 SHA-256 与人工批准值一致。
5. 依赖项均已在清单中启用。
6. 目标路径必须位于项目 `data\Mods\` 内，源目录不得含重解析点。

更新检测通过比较本机源目录和已同步目录的规范化 SHA-256 完成。每次内容变化都必须更新清单中的批准哈希；同步前备份已安装目录和 `PalModSettings.ini`。

### 8.3 当前禁用保证

- `Sync` 在管理器禁用或运行时不是 `windows-dedicated` 时失败关闭。
- 当前 `mods=[]`，不创建 `data\Mods\` 或 `data\mod-manager\`。
- 不预装 UE4SS、Mod loader、旧式 `Pal\Content\Paks\~mods` 或任何 Mod。
- 客户端 Mod 管理仍不在本项目范围。
- 未来启用前必须先迁移到官方支持的 Windows dedicated server，并重新做存档备份、客户端兼容和多人连接验证。

## 9. 测试计划

分阶段验证：

### 阶段 1：本地连通性
- `docker compose up -d` 启动容器
- Windows 客户端连 `127.0.0.1:8211`
- 验证：能进游戏、能创建角色、能存档、重连后存档保留

### 阶段 2：内网穿透
- 启动 SakuraFrp 隧道
- 朋友从外网连 SakuraFrp 节点地址
- 验证：朋友能进服、能互动、延迟可接受

### 阶段 3：稳定性
- 6 人同时在线 1 小时（实际预期峰值，上限 8 人）
- 观察 CPU、内存、网络占用（`docker stats`）
- 验证：无崩溃、无卡顿、无掉档

### 阶段 4：备份恢复
- 触发一次手动备份（`docker compose exec palworld-server backup`）
- 先把当前 `data\Pal\Saved\` 离线复制到独立位置
- 在维护窗口内按镜像 restore 流程恢复到临时/测试副本
- 验证：世界状态回到备份那一刻

### 阶段 5：崩溃恢复
- `docker compose kill` 强杀容器模拟崩溃
- 等待 `restart: unless-stopped` 自动拉起
- 验证：容器自动恢复，server 重新可连

## 10. 后续可选优化

不在第一阶段实施，预留扩展：

- **多服管理面板**：当前已有单服 Web Console；只有服务器数量增加时再评估 Pterodactyl / Pelican
- **Prometheus + Grafana 监控**：通过 cAdvisor 采集容器指标
- **路由器端口转发**：如果有公网 IP，可绕过 SakuraFrp
- **多隧道冗余**：付费节点作为主、免费节点作为备
- **Discord webhook 崩溃通知**：通过 Docker 事件触发
- **Mod 自动更新**：写脚本定期从 mod 仓库拉取更新
- **跨机迁移**：将 `C:\Services\PalworldServer\` 整目录打包，新机解压后 `docker compose up -d` 即可

## 11. 已知风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| Docker Desktop 在某些 Windows 更新后行为变化 | 容器无法启动 | 关注 Windows 与 Docker Desktop 更新日志 |
| WSL2 mirrored 模式与 Docker Desktop 端口发布冲突 | 端口暴露异常 | 改用默认 WSL 网络模式并保留普通 `ports` 映射 |
| SakuraFrp 免费节点限速或限 UDP | 朋友连接卡顿或无法连入 | 升级付费节点 |
| Palworld 更新破坏存档兼容 | 升级后世界无法加载 | `BACKUP_ENABLED=true` 兜底，必要时回滚 server 版本（`image: thijsvanloef/palworld-server-docker:<旧版本>`） |
| 同机游戏 CPU 单核争抢 | 游戏帧率下降 5-10% | 监控帧率，必要时降低 `cpus` 至 4 |
| 长时间运行内存碎片 | server 性能下降 | 定期 `docker compose restart` |
| 社区镜像维护者弃坑 | 镜像不再更新 | 切换到其他镜像（如 `jammsen/palworld-dedicated-server`）或切回方案 A |
| 第三方镜像供应链攻击 | 容器内运行恶意代码 | 镜像固定摘要；更新前审查发行说明与摘要；密码仅放 `.env` |

## 12. 不在范围内

以下不在本次设计范围：
- Palworld mod 安装与管理（架构预留见 §8，但不实施）
- 多服务器实例
- 跨地域节点部署
- 服务器管理面板（如 Pterodactyl）
- 自动化 CI/CD 部署

---

## 附录 A：备选方案 A（WSL2 + systemd）

如果方案 B（Docker）走不通，切回方案 A。以下是方案 A 的关键要点摘要，详细部署指南需另写 spec。

### A.1 架构

直接在 `Ubuntu-24.04` 发行版内安装 SteamCMD + Palworld server，用 systemd 管理生命周期。无 Docker 中间层。

### A.2 核心组件

| 路径 | 用途 |
|---|---|
| `/opt/steamcmd` | SteamCMD 安装目录 |
| `/opt/palworld-server` | Palworld dedicated server 安装目录 |
| `/opt/palworld-backups` | 存档备份目录 |
| `/etc/systemd/system/palworld-server.service` | systemd 主服务单元 |
| `/etc/systemd/system/palworld-server-fail.service` | 崩溃时触发的备份单元 |
| `/opt/palworld-server/update.sh` | SteamCMD 更新脚本 |
| `/opt/palworld-server/backup.sh` | 备份脚本（带重入保护） |

### A.3 关键 systemd 配置

```ini
[Unit]
Description=Palworld Dedicated Server
Wants=network-online.target
After=network-online.target
OnFailure=palworld-server-fail.service

[Service]
Type=simple
User=palworld
Group=palworld
WorkingDirectory=/opt/palworld-server
ExecStartPre=/opt/palworld-server/update.sh
ExecStartPre=/opt/palworld-server/backup.sh
ExecStart=/opt/palworld-server/PalServer.sh -port=8211 -queryport=27015 -useperfthreads -NoAsyncLoadingThread -UseMultithreadForLoad
ExecStop=/bin/kill -SIGINT $MAINPID
ExecStopPost=/opt/palworld-server/backup.sh
Restart=on-failure
RestartSec=10
TimeoutStopSec=30
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
```

### A.4 备份脚本核心逻辑

```bash
#!/bin/bash
set -euo pipefail

BACKUP_DIR=/opt/palworld-backups
SAVE_DIR=/opt/palworld-server/Pal/Saved
KEEP=5
REENTRY_FLAG=/tmp/palworld-backup-running

if [ -f "$REENTRY_FLAG" ]; then exit 0; fi
touch "$REENTRY_FLAG"
trap 'rm -f "$REENTRY_FLAG"' EXIT

mkdir -p "$BACKUP_DIR"

# 备份由 systemd 在 ExecStartPre / ExecStopPost / OnFailure 三处调用
# 此时 server 已停止，直接 tar 即可

if [ ! -d "$SAVE_DIR" ]; then
  echo "Save directory does not exist yet, skipping backup."
  exit 0
fi

TIMESTAMP=$(date +%Y%m%d-%H%M)
ARCHIVE="$BACKUP_DIR/palworld-$TIMESTAMP.tar.gz"
tar -czf "$ARCHIVE" -C "$(dirname "$SAVE_DIR")" "$(basename "$SAVE_DIR")"

ls -t "$BACKUP_DIR"/palworld-*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f
```

### A.5 切换条件

何时从方案 B 切到方案 A：
- Docker Desktop 在 Windows 更新后异常，无法短期内修复
- 社区镜像 `thijsvanloef/palworld-server-docker` 维护者停止维护
- 镜像性能问题（如 vhdx IO 瓶颈严重影响 server 体验）
- 用户希望减少资源开销（Docker daemon 自身约 1-2 GB）

### A.6 迁移步骤（从方案 B 切到方案 A）

1. `docker compose stop` 停止方案 B
2. 复制 `C:\Services\PalworldServer\data\Pal\Saved\` 到 `/opt/palworld-server/Pal/Saved/`（通过 `\\wsl$\Ubuntu-24.04\` 或 `wsl cp`）
3. 在 Ubuntu-24.04 内按方案 A 部署（安装 SteamCMD、Palworld server、systemd 单元、脚本）
4. `systemctl start palworld-server` 启动
5. 验证本地连通性后切回 SakuraFrp 隧道

迁移成本：约 30-60 分钟，主要是文件复制与 systemd 配置。
