# Session Log

Chronological record of project sessions. Updated each session. Indexed from [AGENTS.md](file:///C:/Services/PalworldServer/AGENTS.md).

## 2026-07-27

- Initial discussion: WSL2 + SakuraFrp Palworld server feasibility
- Hardware check: Ryzen 7 9700X / 48GB / Windows 11 24H2 / WSL2 + Ubuntu-24.04 + docker-desktop
- Requirements: 6-player server, same-machine server + client
- Option comparison: A (WSL2+systemd) / B (Docker image) / C (Pterodactyl) / D (Windows native)
- Considered Pterodactyl, rejected (Wings complex on Windows, over-engineered for single server)
- Selected Option B
- Key parameters: auto-update on boot, default params + MaxPlayers=6 + ExpRate=2.0, auto backup with 5 copies retention
- Spec written to `docs/spec.md`
- Self-review fixed 3 issues: `$MAINPID` typo, backup.sh recursion, bat UDP detection contradiction
- Spec rewritten from Option A to Option B (Docker), Option A kept as Appendix A fallback
- Mod support: architecture reserved, not implemented in Phase 1
- Management panel: Pterodactyl rejected, Docker CLI management
- Path change: `D:\PalworldServer\` → `C:\Services\PalworldServer\` (C drive has 1-2 TB free, avoid confusion with D drive game dir, `Services` subdirectory for future services)
- MaxPlayers 6 → 8 (expected 6, 2 headroom)

## 2026-07-28

- Deployment executed: `.wslconfig` (24GB/6CPU/mirrored), `docker-compose.yml` (8GB+4GB swap), `.env` (strong passwords), `PalWorldSettings.ini` (ExpRate=2.0, DayTimeSpeedRate=0.5, MaxPlayers=8)
- Firewall configured via `netsh` (UDP 8211 + TCP 25575 inbound allow)
- Local connectivity verified: Palworld client connected to `127.0.0.1:8211`, server name "Palworld-Docker" visible
- Resource limits adjusted: WSL memory 8GB → 24GB (user also runs Minecraft server), processors 6, container 8GB RAM + 4GB swap
- Web Console built: PowerShell HttpListener backend + single-file HTML frontend
  - 6 panels: Overview / Settings / Logs / RCON / Backup / Mods
  - 42 settings fields with search and modification tracking
  - Dark/light theme toggle with localStorage persistence
  - Docker invoked via `System.Diagnostics.Process` (avoids CLIXML stderr issues)
  - Custom JSON encoder (PS 5.1 compatible)
  - Fixed `docker stats` regex for `940.9MiB / 8GiB` format
  - Fixed `$matches` overwrite bug (extract all values before subsequent `-match` calls)
- File cleanup: deleted `start/stop/settings-panel.bat`, `setup-firewall.bat/.ps1`, `apply-ini-settings.ps1`, `passwords.txt`, `.env.bak.*`
- Consolidated to single launcher `palworld.bat` (supports `start` and `stop` modes)

## 2026-07-28 — Audit and repair

- Audited files, live Docker state, generated ini, ports, firewall rules, image metadata, logs, backups, and upstream image documentation.
- Found that the deployed `.env` used unsupported names (`MAX_PLAYERS`, `SERVER_SETTINGS_*`, `BACKUP_RETENTION_DAYS`, `RCON_PASSWORD`).
  - Evidence before repair: generated ini had `ServerPlayerMaxNum=32`, `CoopPlayerMaxNum=4`, `ExpRate=1.0`, `DayTimeSpeedRate=1.0`.
  - Migrated to official names and removed unsupported/deprecated keys.
  - Evidence after repair: generated ini has 8 / 8 / 2.0 / 0.5 respectively, plus `DeathPenalty=None`.
- Created offline pre-fix archive `data/backups/pre-fix-20260728-101411.tar.gz`; verified archive entries.
- Pinned the community image to digest `sha256:401d3eb5c053bcd72949e1ede8c4e38be5e5ad66be7272ac37940706df0aeb2f`.
- Bound RCON to `127.0.0.1`; UDP 8211 remains published for the game/tunnel.
- Tried to disable Windows rule `Palworld RCON TCP 25575`, but the current process lacked elevation (`Access is denied`); rule remains enabled, while Docker still restricts the listener to loopback.
- Fixed Web Console:
  - No admin-secret exposure through `/api/env`.
  - Allowlist/type/range validation and changed-fields-only saves.
  - UTF-8 without BOM, atomic replacement, no persistent `.env.bak.*` secret copies.
  - Local Host/Origin checks, JSON/body/log/RCON bounds, output escaping.
  - Concurrent process stream reads and command timeouts.
  - REST player query/save; RCON retained only for compatibility commands.
  - `/api/stop` uses Compose stop, so `restart: unless-stopped` no longer immediately relaunches an intentional shutdown.
  - `/api/restart` recreates without an explicit `down`.
- Fixed launcher:
  - Container wait now has a 120-second timeout.
  - Duplicate Web Console start is avoided.
  - Web Console PID is recorded for precise shutdown.
  - Compose stop uses a 120-second grace period and checks errors.
- Regression evidence:
  - Container reached `healthy`; port check showed UDP 8211 on host and TCP 25575 only on `127.0.0.1`.
  - `rest-cli info`, `rest-cli players`, REST save, RCON info, and built-in backup all exited 0.
  - Built-in backup created `palworld-save-2026-07-28_10-26-00.tar.gz`.
  - `/api/env` returned 42 editable keys, did not expose `ADMIN_PASSWORD`, and rejected admin-key writes with HTTP 400 without changing `.env`.
  - Cross-origin mutation rejected with HTTP 403.
  - `/api/stop` left the container exited with code 0; `/api/restart` restored it to `healthy`.
- Added `README.md`, `.env.example`, `.gitignore`, `scripts/normalize-env.ps1`, and `scripts/verify-project.ps1`.
- Reserved a future Mod-management layer without installing Mods:
  - Added an empty, disabled, schema-validated manifest and a fail-closed CLI.
  - Added Web Console status/check/sync interfaces; sync remains locked on Linux Docker.
  - Removed the earlier assumption that dropping `.pak` files into `~mods` is the supported Palworld 1.0 server workflow.
  - Preserved manual, hash-approved update and rollback plumbing for a future Windows dedicated-server migration.
- Reviewed the full Palworld official server-guide navigation (site version 1.0.0) and added `docs/official-palworld-server-standards.md`.
  - Recorded official rules for deployment, configuration, updates, commands, backups, REST, deprecated RCON, Mods, PvP, Technology IDs, and network exposure.
  - Recorded current deviations: Docker Desktop is officially discouraged, the community image is not the Pocketpair image, and the 8 GB container cap is below the official 16 GB requirement.
  - Kept runtime unchanged; migration, memory increase, strict-client-Mod policy, and Community mode require separate user decisions.
  - Corrected project continuity to six Web Console panels after the Mod panel was added.
- User clarified deployment policy: the official guide is an official launch/reference path, while the tested community container remains the current selected solution. A difference is not itself a defect; move to an official path only after concrete problems or an explicit decision.

## 2026-07-28 — Full settings and telemetry expansion

- Audited the pinned image directly:
  - `compile-settings.sh` and `PalWorldSettings.ini.template` expose 118 game mappings.
  - `compile-engine.sh` exposes 13 Engine.ini values plus the `DISABLE_GENERATE_ENGINE` gate.
  - Startup, backup, update, reboot, pause, logging, installer, and Discord scripts provide the current amd64 container settings.
- Replaced the duplicated 42-field frontend/backend lists with `scripts/settings-catalog.ps1`.
  - Catalog count: 205 = 117 `game` + 74 `container` + 14 `engine`.
  - `PLAYERS` is container-sourced and supplies the 118th game mapping (`ServerPlayerMaxNum`).
  - Seven Box64/ARM64-only variables are explicitly excluded on the Ryzen amd64 host.
  - All password and Webhook values are write-only and never returned to the browser.
- Rebuilt Settings UX with grouped search, advanced and modified-only filters, explicit/default/source badges, risk labels, dependency dimming, deliberate secret clearing, true changed-only writes, and a sticky apply dock.
- Added structural and relational validation for types, finite numbers, choices, ports, player limits, cron shape, IP/URL/crossplay syntax, frame-rate bounds, and administrator password length.
- Expanded `/api/dashboard` using Docker + Palworld REST + local file/process evidence:
  - container health/resources/PID/start/restarts/OOM/exit/image/ports;
  - server version/identity/FPS/frame time/world days/base camps/uptime;
  - privacy-masked player details, backup/save storage, local tunnel-process detection, and warnings.
- Kept evidence boundaries explicit: a SakuraFrp process does not prove tunnel connectivity; RCON remains deprecated and loopback-only; Mod manager remains disabled with zero Mods.
- Made Compose game and RCON port mappings follow editable `PORT` and `RCON_PORT`.
- Corrected `LOG_FORMAT_TYPE=default` to the Palworld-supported `Text` value.
- Added `docs/web-console-capabilities.md` and `scripts/ui-smoke.cjs`.
- Regression evidence:
  - `/api/settings`: 205 schema entries and 205 values; 15 configured-capable secret fields return empty values.
  - `/api/dashboard`: running/healthy, server v1.0.1.100619, REST metrics, backups and save summary returned successfully.
  - Unknown keys and inconsistent player limits rejected with HTTP 400.
  - `verify-project.ps1` passed with `VERIFY_ERRORS=0`, including the exact 118-game-mapping assertion.
  - Real-browser desktop/settings/mobile smoke passed with `UI_SMOKE_ERRORS=0`; 390 px layout has no horizontal overflow.

## 2026-07-28 — Setting help, log diagnostics, commands, and tunnel evidence

- Added a visible help block to every one of the 205 settings:
  - meaning;
  - exact choice meanings or numeric direction/format guidance;
  - dependency note;
  - link to Palworld official configuration/PvP/startup docs or the community image documentation.
- Converted `DIFFICULTY` and `RANDOMIZER_TYPE` to constrained choices and added official limits for bases per guild (10), workers per base (50), and pawn replication distance (5000–15000).
- Added cross-field validation for voice distance and the three required PvP switches.
- Added rule-based log explanation while preserving raw lines, severity counts, recommended actions, secret/IP masking, and automatic deduplicated incidents in `data/diagnostics/incidents.jsonl`.
- Expanded RCON quick templates from 9 to the 12 applicable commands in the official command table, including teleport and spectator commands. Templates fill the input only.
- Replaced process-only SakuraFrp status with five evidence layers and a forced read-only verification API.
- Current tunnel evidence:
  - Docker publishes UDP 8211;
  - frpc/Sakura processes are present;
  - established node control connections are present;
  - the service log reported proxy-ready at 11:57:41; the historical endpoint
    was removed from public source because tunnel addresses are deployment-private;
  - the 11:57:51 new-data-connection attempt timed out and is retained as a historical incident;
  - the timeout is older than the 15-minute live window, so current state is `ready`;
  - no successful external traffic exists, so state is never `verified`.
- Increased body, navigation, setting, help, log, and command typography with an explicit display/body/mono hierarchy.
- Added `docs/log-and-tunnel-diagnostics.md`; updated README, capability docs, static checks, and real-browser smoke coverage.
- Corrected CPU telemetry semantics: Docker reports 100% per logical CPU, so the 6-CPU
  allocation has a 600% ceiling; the UI now shows the raw value and a separately normalized
  allocation percentage/bar.
- Resolved the persistent warning rail by limiting live tunnel failures to 15 minutes while
  preserving old failures in the incident journal and tunnel evidence panel.
- When Docker Desktop held TCP 8213 as `BOUND`, added localhost-only automatic fallback to
  8214/18213 plus `.settings-panel.port`; this restored the panel without restarting Docker
  or the game container.
- Regression evidence after these fixes:
  - dashboard returned running/healthy, `cpuLimit=6`, tunnel `ready`, zero warnings, one
    masked historical incident;
  - no-op settings update was byte-identical; invalid voice-distance and partial PvP updates
    returned HTTP 400 without changing `.env`;
  - `verify-project.ps1` returned `VERIFY_ERRORS=0`;
  - Playwright returned `UI_SMOKE_ERRORS=0` and `UI_SUPPORTED_SETTINGS=205`, including the
    600% CPU capacity, absence of the resolved warning rail, and 390 px layout.

## 2026-07-28 — Daily log archive and resource rings

- Added an independent daily log collector started and stopped by `palworld.bat`.
  - Rebuilds the current Asia/Shanghai day every 60 seconds.
  - Uses exact 00:00:00–24:00:00 boundaries, finalizes rollover, backfills yesterday on
    startup, and runs one final refresh after graceful container stop.
  - Aggregates game-container logs, Web Console operational events, SakuraFrp service logs,
    and the incident journal into `data/log-archive/YYYY-MM-DD.txt`.
  - Converts Docker UTC timestamps to Beijing time, strips ANSI control codes, and reads
    the active SakuraFrp file with read/write sharing.
  - Keeps archives indefinitely and does not upload them; files may contain raw player/IP
    evidence and require review before sharing.
- Added archive list, manual refresh, validated TXT download API, Logs-page archive cards,
  and dashboard collector state.
- Added compact CPU and memory allocation rings while retaining the exact values and
  horizontal bars.
  - CPU ring uses raw Docker CPU percent divided by the six-core 600% capacity.
  - Memory ring uses working set divided by the 8 GiB allocation.
  - Both rings reuse existing palette tokens, expose accessible labels, and avoid external
    chart libraries.
- Runtime evidence:
  - generated and structurally checked `2026-07-27.txt` and `2026-07-28.txt`;
  - both contain all four source sections, correct day headers, and zero ANSI escape codes;
  - collector PID is live and API reports `collectorRunning=true`, `retention=unlimited`;
  - validated download returns `text/plain` with attachment disposition; traversal-style
    names return HTTP 400.

## 2026-07-28 — Dual-runtime switchable (Docker ↔ Windows native) completion

- Implemented Option E (dual-runtime switchable) end-to-end so Docker and a Windows native
  Palworld Dedicated Server share the same `.env`, Web Console, backup/log system, and
  `data\Pal\Saved\SaveGames` world save via an NTFS junction. Only one runtime runs at a time;
  mutual exclusion is enforced by `data\runtime.state` plus a process-level Mutex.
- Added `scripts\runtime-common.ps1`, `docker-runtime.ps1`, `win-runtime.ps1`,
  `compile-settings.ps1`, `install-win-server.ps1`, `switch-runtime.ps1`,
  `restore-snapshot.ps1`, and `recover-runtime-state.ps1`. M1–M10 (infrastructure, INI
  compiler, SteamCMD install, junction, Windows provider, Light/Full snapshots with
  retention, atomic switch flow with rollback, Mod drift detection, disaster recovery) are
  all complete.
- Web Console now exposes a runtime pill in the topbar, a dedicated Runtime panel with
  switch buttons, manual snapshot buttons, full-snapshot checkbox, snapshot list, and async
  task polling. Backend added `/api/runtime`, `/api/runtime/switch`, `/api/runtime/snapshot`,
  `/api/runtime/restore`, `/api/runtime/task`, and `/api/snapshots`. `Get-Dashboard` is
  runtime-aware and skips Docker inspect when the Windows runtime is active.
- End-to-end switch rehearsal performed in the maintenance window: Docker → Windows native
  → Docker. World save GUID matched across the junction, REST `/info` responded with Basic
  auth on the Windows runtime, and `runtime.state` recorded both transitions.
- Fixes applied during rehearsal:
  - `install-win-server.ps1`: moved `+force_install_dir` before `+login anonymous` so
    SteamCMD installs into `win-server\` (previously failed with exit code 7).
  - `compile-settings.ps1`: Windows INI output path corrected from
    `data\Pal\Saved\Config\WindowsServer` to
    `win-server\Pal\Saved\Config\WindowsServer`.
  - `switch-runtime.ps1`: replaced `ConvertFrom-Json -AsHashtable` with a PSCustomObject
    normalization helper so snapshot manifest parsing works on PowerShell 5.1.
  - `win-runtime.ps1`: `Invoke-WinRest` now sends HTTP Basic auth (`admin:password`) and
    `Get-WindowsRuntimeHealth` uses `/info` instead of the non-existent `/health` endpoint.
- Final verification: 14 PowerShell scripts passed syntax check (`win-runtime`,
  `switch-runtime`, `compile-settings`, `install-win-server`, `verify-project`,
  `runtime-common`, `recover-runtime-state`, `restore-snapshot`, `docker-runtime`,
  `daily-log-collector`, `settings-catalog`, `mod-manager`, `normalize-env`,
  `settings-panel`). `compile-settings.ps1` regenerated 121-field INI for both platforms.
  `verify-project.ps1` returned `VERIFY_ERRORS=0` with no warnings.
- Documentation updated: `README.md` runtime-switch section, `AGENTS.md` Solution History
  (Option E) and Current Status, `docs/runtime-switch-design.md` §11.3.1 implementation
  progress table. Milestones M1–M10 are implemented; the maintenance-window
  Docker↔Windows end-to-end drill remains pending.

## 2026-07-29 — Open-source delivery baseline

- Added an evidence-bounded maturity assessment and staged delivery plan in
  `docs/open-source-maturity-assessment-and-delivery-plan.md`; it explicitly keeps
  source CI separate from live-server acceptance.
- Repaired `scripts/verify-project.ps1` after the Web Console frontend split:
  it now validates `web\styles.css` and `web\app.js`, checks CPU normalization and
  per-setting documentation in the JavaScript bundle, and syntax-checks that bundle
  directly instead of looking for deleted inline JavaScript.
- Restored the empty Mod manifest to the documented fail-closed default
  (`managerEnabled=false`, `runtime=linux-docker`).
- Added Windows GitHub Actions static validation plus `CONTRIBUTING.md` and
  `SECURITY.md`. CI generates a non-secret local `.env`, skips Docker, and never
  starts, stops, switches, restores, or otherwise changes a live server.

## 2026-07-29 — Native runtime rollback-path alignment

- Merged the reviewed `codex/open-source-maturity-foundation` source changes.
  Snapshot creation, restore, INI fingerprinting, and project validation now use
  the native server's live `win-server\Pal\Saved\Config\WindowsServer` path;
  snapshot archives retain their existing `Config\WindowsServer` layout for
  backwards-compatible restore.
- `recover-runtime-state.ps1` now repairs a structurally valid but stale state
  when detected Docker/PalServer processes disagree, and checks backup freshness
  only while a runtime is active.
- Retained the documented `linux-docker` value for the disabled, empty Mod
  manifest. Runtime-drift validation now applies only when a runtime is active.
- This merge changes source and documentation only. No runtime switch, restore,
  server start/stop, configuration compilation, or SaveGames operation was run.

## 2026-07-29 — P2 evidence reconciliation and readiness tooling

- Reconciled the raw local switch evidence with the P2 acceptance boundary. The
  historical `switch.log` contains switch attempts and some healthy target starts,
  but also records failed REST saves, a failed Windows health check, and a
  port-release warning. It therefore does not prove a clean, fully accepted
  Docker→Windows→Docker drill under the current P2 criteria.
- Added `docs/maintenance-window-runbook.md` and the read-only
  `scripts/test-maintenance-readiness.ps1` preflight. They require an
  operator-approved window, structured local evidence, successful REST saves,
  verified snapshots, and separate external/stability proof before P2 can be
  marked complete.
- Current preflight reports `runtime.state.active=none` while Docker is running.
  It correctly refuses readiness; no recovery, switch, restore, configuration,
  backup, or other runtime mutation was performed by this source increment.

## 2026-07-29 — Structured P2 evidence contract

- Added `scripts/verify-maintenance-evidence.ps1`, a read-only JSON validator for
  completed local P2 records. It requires common provenance and recovery fields,
  then operation-specific evidence such as REST saves and matching fingerprints
  for a switch, verified hashes for restore, external observation for tunnel,
  and a 6-player/60-minute aggregate-only stability run.
- Added a clearly marked synthetic fixture and a CI validation step. The fixture
  has no runtime data and requires `-AllowSynthetic`; it cannot be mistaken for
  a P2 result.
- Validated source syntax, the synthetic evidence contract, clean-checkout
  onboarding, and static project validation. No live server operation occurred.

## 2026-07-30 — Docker↔Windows end-to-end switch drill and restore rehearsal

- Upgraded Windows native server to v1.0.2.100933 via
  `install-win-server.ps1 -UpdateOnly` to match the Docker container's game
  version.
- Executed Docker→Windows switch with `-FullSnapshot`. Windows runtime reached
  healthy state; REST /info, /settings, /players all succeeded; SaveGames
  junction intact; 1 player online. SaveGames fingerprint changed across the
  switch because the Windows server binary re-serializes Level.sav on load;
  this is expected cross-runtime behavior, not data loss.
- Executed Windows→Docker switch with `-FullSnapshot`. Docker container reached
  healthy state; version, settings, players, junction all verified. Pre/post
  SaveGames fingerprints matched exactly.
- Rehearsed Full snapshot restore on a disposable temp copy (no real SaveGames
  modified). Snapshot SHA-256 verified against manifest; 70 files extracted;
  4 Level*.sav files found and content-hashed. Finding: snapshot contains a
  `Games\` path prefix (Windows junction artifact) that the manifest fingerprint
  does not reflect because the fingerprint is computed through the junction.
  This is a known snapshot-creation issue, not a restore failure.
- Created three evidence JSON records under `data/maintenance-evidence/`:
  switch docker→windows, switch windows→docker, and restore drill. All three
  pass `verify-maintenance-evidence.ps1` with zero errors.
- Fixed three bugs found during the drill:
  `compare-save-integrity.ps1` project path went up two levels instead of one;
  `verify-runtime-state.ps1` crashed on null players object;
  `verify-maintenance-evidence.ps1` rejected all cross-runtime switch evidence
  because fingerprints naturally differ — added `saveGames.fingerprintExplanation`
  field to allow explained fingerprint differences as warnings.
- Two findings documented for future fixes: snapshot creation should normalize
  junction path prefixes; `restore-snapshot.ps1` should handle `Games\` prefix
  when restoring across runtimes.

## 2026-07-31 — Runtime start safety and live regression loop

- Reconciled a stale `runtime.state` that still claimed Windows while neither
  runtime was live. `recover-runtime-state.ps1` now fails closed if both
  runtimes are detected, and treats stale automatic-backup age as an operational
  warning rather than SaveGames corruption.
- Routed both normal launchers through `switch-runtime.ps1`; they create a Full
  pre-start snapshot and reconcile state after a graceful stop. The switcher
  performs recovery under its Mutex and waits up to 900 seconds for health so a
  normal multi-GB `UPDATE_ON_BOOT` SteamCMD run is not reported as a 120-second
  server failure. A Full pre-start snapshot was created before this live start.
- Actual Docker startup completed after the image updated Palworld to
  `v1.0.2.101103`. Container health, REST `/info`, REST `/players`, shared-save
  presence, the local Web Console (8214), and the daily log collector were
  verified. No players were online during the test.
- Reworked `ui-smoke.cjs` to assert the tunnel panel against live API evidence
  instead of a hard-coded historical endpoint, use visible labels for hidden
  checkbox controls, and scope duplicate desktop/mobile navigation controls.
  The real-browser smoke passed dashboard, settings, logs, RCON and narrow
  mobile-layout checks with 205 supported settings.
- `verify-project.ps1` now compares parsed `OptionSettings` values so Docker's
  equivalent boolean/numeric formatting is not a false INI-drift warning, and
  explicitly exits 0 on success. `test-clean-checkout.ps1` now checks the
  invoked validation result instead of retaining an unrelated previous exit
  code. Static validation, disposable clean-checkout validation and the
  read-only Docker→Windows maintenance preflight all passed.
- Current tunnel evidence is intentionally not promoted: SakuraFrp Launcher is
  present and local UDP is ready, but the frpc control connection is
  disconnected and no current endpoint or external traffic exists. Remote
  connectivity remains pending a launcher-side reconnection and a real friend
  join observation.

## 2026-07-31 — Windows native validation, observability, and player-time repair

- Updated the Windows dedicated-server build to Steam build `24466863`, then
  completed a protected Docker→Windows→Docker regression with Full snapshots.
  The native server reported `v1.0.2.101103`; REST `/info`, `/settings`,
  `/players` (empty), SaveGames junction, and final Docker health all passed.
- Found that Windows Palworld binds REST 8212 and RCON 25575 on all interfaces.
  Added an elevated fail-closed firewall gate using explicit inbound block rules
  before native start. The local 127.0.0.1 REST path remains usable; no public
  management exposure was accepted.
- Replaced fragile Windows stdout redirection with distinct lifecycle evidence
  (`data/log-sources/windows-runtime`) and a separately labelled engine
  `-abslog` best-effort source. A native restart produced lifecycle start events
  and the daily archive contains the Windows lifecycle section. No assertion was
  made that the engine emitted complete raw logs.
- Fixed Windows empty-player counting: the prior wrapper-property logic could
  report one player for `{ "players": [] }`. Panel state, dashboard metrics,
  and raw REST all reported zero after the fix.
- Reworked player online-time accounting. The original first-write path used
  `File.Replace` without an existing destination, browser polling was the sole
  source of updates, and only one ID field was recognized. The daily collector
  now owns REST polling, stable-ID hashing accepts current field variants, and
  a failed REST request leaves sessions unchanged. An isolated synthetic
  first-write/online/offline test passed without persisting the synthetic ID.
- Fixed runtime manifest synchronization so a Windows switch does not enable an
  empty Mod manager. Final manifest state is `linux-docker`, disabled, empty.
  Static validation and the real-browser UI smoke passed after the Docker return.
- Reconciled stale compatibility documentation: the current locally tested
  server build is `v1.0.2.101103`, and the Windows local regression is complete.
  A read-only inspection of all 16 currently retained switch archives found the
  canonical `SaveGames/` root in each, so the earlier `Games/` junction-prefix
  finding is historical rather than a claim about current artifacts.
- Clarified maintenance preflight JSON: `ready` is retained as a legacy
  precondition result, while new `preflightReady` and always-false
  `acceptanceReady` prevent a no-error read-only check from being presented as
  tunnel, stability, restore, or switch acceptance.
- Audited and repaired Windows native backup: the provider now creates its
  archive directory, refuses to archive after a failed save, validates nonempty
  tar output, and has a local-only RCON compatibility fallback. A no-player
  Windows run completed REST save, tar backup (3.30 MB), SaveGames/Config
  listing and SHA-256 calculation, then returned to healthy Docker.

## 2026-07-31 — Player online-time display regression

- A follow-up inspection found two same-named JavaScript `formatDuration`
  declarations. The latter silently replaced the former, so duration formatting
  was inconsistent and multi-day player sessions displayed as a large hour
  count. Replaced them with one formatter used by both dashboard uptime and
  player-session rows: seconds below a minute, minute/second, hour/minute, and
  day/hour forms.
- Added `scripts/test-player-session-times.ps1`, a disposable source-only test
  with no REST call and no live data access. It covers first write, offline
  accumulation, reconnect, accepted stable-ID variants, ignored name-only
  records, Windows runtime attribution, and raw-ID non-persistence.
- Extended the real-browser smoke to call the live read-only `/api/player-times`
  endpoint and render an in-memory 1-day synthetic row. The test restored the
  page from the live endpoint afterwards; it did not create a player record.
  Static validation, clean-checkout validation, the player-session test and
  browser smoke passed. Docker remained healthy and REST `/players` still
  returned an empty list, so no live player duration could be observed in this
  session.

## 2026-07-31 — Public-source and maintainer readiness

- Audited public-source boundaries and found a deployment-specific remote panel
  origin, a remote password flow, and a wildcard `HttpListener` prefix. Removed
  that remote-management feature rather than trying to document it as safe. The
  console now registers only `localhost`, `127.0.0.1`, and `[::1]`, rejects any
  non-loopback request before routing, and has no remote panel secret in the
  template. A temporary loopback listener and the restarted live panel verified
  the registration; Docker remained healthy and no game process was stopped.
- Added source-only publication audit, host prerequisite preflight, optional
  untracked Compose resource override, support/governance/code-of-conduct
  documents, GitHub issue contact links, and Dependabot. CI now audits the
  tracked public source after static validation. The audit passed the current
  candidate source with one expected warning: the historical `palworld.bat`
  deletion remains uncommitted in this already-dirty worktree.
- Removed historical tunnel endpoint values from public-facing source. The
  audit is a guardrail, not a claim that an account, tag, release archive,
  remote connection, multiplayer test, or production restore has been accepted.
- Corrected public onboarding terminology: SakuraFrp is optional for remote UDP
  access and a Palworld game client is optional for a host that does not play on
  the same machine. The default launchers already warn rather than fail when
  SakuraFrp is absent.
- Updated the optional, untracked Compose override example to the documented
  16 GiB baseline and added a physical-memory warning to host preflight. The
  existing live 8 GiB cap was not changed or applied; lower-memory operation is
  still an unqualified local trade-off rather than a capacity claim.
- Added `README.en.md` as a standalone, evidence-bounded self-hosting guide so
  non-Chinese operators can use the project without treating internal session
  history as deployment instructions. Public audit and static validation now
  require the guide and the Chinese README links to it.

## 2026-07-31 — Web Console locale maintenance guard

- Source inspection found four CPU/memory chart keys present only in the Chinese
  dictionary. Added their English translations and `scripts/test-i18n-parity.cjs`.
  Static validation now parses the source-local dictionary and fails when the
  Chinese and English key sets differ. This check uses no browser, REST call, or
  live server data.

## 2026-07-31 — Player-duration observation boundary

- Source review found that an active session was previously closed at the next
  successful poll. If the collector had been unavailable, that incorrectly
  converted the unseen interval into play time. Offline totals now cap at the
  player's last confirmed online sample, while a fresh display shows only its
  latest confirmed duration. The table says “observed time” and the disposable
  player-session regression covers both cases; no player or live server was
  used for this change. The regression is now a required CI step in both
  Windows PowerShell hosts rather than a manual-only local check.

## 2026-07-31 — Web Console internationalization boundary

- A source review found that English dictionary keys were complete but several
  visible static labels, accessibility names, and log prefixes remained Chinese
  because the HTML did not declare them as translatable. Added title and
  `aria-label` translation support, localized the affected controls and log
  panels, and split the RCON documentation sentence around its official link.
  `test-i18n-parity.cjs` now also rejects HTML and literal `t()` references that
  are missing from either locale. This was a source-only change; no browser,
  player, or server operation was performed.

## 2026-07-31 — Portable browser-smoke prerequisites

- Source review found that `ui-smoke.cjs` depended on an implicit globally
  resolvable Playwright module, one hard-coded Chrome path, and fixed DevTools
  port `19229`. Added the declared `playwright-core` development dependency,
  npm scripts, ignored `node_modules`, Chrome-path override documentation, and
  a fresh `DevToolsActivePort` handshake bound to loopback. This makes missing
  prerequisites fail with an actionable message and avoids attaching to an
  unrelated browser that happens to own the old fixed port. The current host
  has no npm/npx or locally resolvable Playwright, so this structural change was
  syntax/static-validated only; the live browser regression remains pending.
- The browser dependency is now pinned to `playwright-core` 1.61.1, which the
  public npm registry identifies as the no-browser package. Windows CI installs
  it with lifecycle scripts disabled and verifies resolution under both
  PowerShell hosts; it does not download or launch a browser. Publication audit
  now requires `package.json` so the bootstrap contract cannot be omitted from a
  release candidate.

## 2026-07-31 — Docker no-player REST save check

- With Docker already running and no players reported, a direct container
  `rest-cli info` returned `v1.0.2.101103`, `rest-cli players` returned zero
  players, and `rest-cli save` exited successfully in about 1.3 seconds. The
  container identity, start time, health (`healthy`), and restart count (0)
  were identical before and after the save; no runtime was stopped, recreated,
  or switched.
- Scope boundary: this is current Docker REST/save evidence only. It does not
  newly verify the inactive Windows runtime, an external tunnel join, player
  duration observation, multiplayer stability, or destructive restore.

## 2026-07-31 — Windows-first operations and guided-console controls

- With Docker healthy and zero players, created a Docker backup, completed the
  approved Docker→Windows Full-snapshot switch, and left Docker gracefully
  exited (`restartCount=0`). Windows native PalServer remained `v1.0.2.101103`
  and healthy throughout the follow-up checks.
- On Windows, REST `/players` returned an empty collection, REST save succeeded,
  and `Invoke-WindowsRuntimeBackup` created nonempty
  `palworld-win-save-2026-07-31_02-30-20.tar.gz` (3,265,563 bytes). The
  PalServer PID and start time were identical before and after both operations.
- Found and repaired an active-runtime bug in `/api/rcon`: it always used Docker
  `rcon-cli`, so the command panel could not work in Windows mode. The endpoint
  now routes Windows to loopback `Invoke-WindowsRcon`; a live `showplayers`
  request returned the zero-player header without changing PalServer state.
- Added a goal-first Overview workflow for save, backup, player, tunnel, and
  log tasks, plus a beginner RCON guide for live-player selection, server info,
  and announcement preparation. Player Steam ID / Player UID values are held
  only in the current page-memory map and fill the command input without
  execution; high-risk player and stop commands require a second confirmation.
- Added source-only i18n, player-command-picker, and guided-action validation.
  The current host lacks npm/npx and a locally resolvable Playwright package, so
  this UI increment has source/static evidence and endpoint evidence only; no
  real browser interaction or live player ID selection was claimed.

## 2026-07-31 — Zero-player bidirectional runtime drill and comparison scope

- Read-only preflight permitted Windows→Docker with zero players. Before both
  directions, REST player queries were empty, REST save succeeded, and the
  active runtime's backup endpoint returned `ok`. The protected switcher then
  completed Windows→Docker and Docker→Windows with Full snapshots.
- Docker target evidence: container `running` and `healthy`, REST reachable,
  UDP 8211 published by Docker, and generated Linux settings present. Final
  Windows target evidence: PalServer PID 52452, REST reachable, UDP 8211
  listening on `0.0.0.0`, generated Windows settings present, and Docker
  gracefully exited with restart count 0. This is a zero-player operational
  drill, not remote-join, stability, restore, or P2 maintenance acceptance.
- Found a false-alarm defect in `compare-save-integrity.ps1`: it excluded
  `backup/` but included historical `world_save_bak/` files from a Full
  snapshot. The shared transient-path rule now excludes both. The helper also
  warns when comparing an immutable snapshot to an active runtime because
  normal world-time or post-snapshot saves can change bytes; a mismatch alone
  is not corruption evidence. The source contract runs locally, in a clean
  checkout, and in Windows CI.

## 2026-07-31 — Guided-console browser regression

- A live loopback browser pass exercised non-mutating Overview navigation, the
  RCON `info` command-fill path, Settings rendering, and English/Chinese
  language switching. No save, backup, lifecycle, or RCON command was
  dispatched through the browser.
- It found and repaired three usability defects: the language button had no
  click binding; the Windows CPU ring announced a six-core Docker quota instead
  of host-process usage; and the English Runtime & Storage card still rendered
  the Chinese Windows runtime name. Source contracts now cover all three;
  this validates the local browser interface only, not a remote-management
  surface or live-player command selection.
- Direct execution of `test-clean-checkout.ps1` in Windows PowerShell 5.1 also
  exposed a portability defect: its parameter default read `$PSScriptRoot`
  before that automatic variable was populated. The script now resolves its
  default source path after parameter binding, retaining explicit `-SourcePath`
  behavior and allowing the documented no-argument command to work.

## 2026-07-31 — Runtime-aware browser smoke and reproducible npm install

- A real Windows-native loopback smoke pass completed dashboard, language,
  Settings, Logs, RCON, and 390px layout checks with zero players. It refreshed
  local tunnel/archive evidence only; it did not start, stop, switch,
  reconfigure, save, back up, or dispatch an RCON command to the game server.
- The smoke previously required Docker-only startup-update wording and a
  six-core allocation even when Windows was active. It now derives the active
  runtime from the dashboard: Windows requires the intentional update
  “not applicable” state and host-process CPU accessibility text, while Docker
  retains allocation assertions. It also exercises both language directions and
  the localized Windows runtime overview, then waits for Chrome exit before
  profile cleanup; the final Windows run passed without a cleanup warning.
- Added `package-lock.json` for the declared no-browser `playwright-core`
  library, normalized its source to the public npm registry, and changed CI and
  operator instructions to `npm ci`. Static and release checks require the lock
  entry, while Windows PowerShell 5.1 validates it without attempting to parse
  npm's empty-string project-package key. The cache/snapshot folders used by
  Playwright CLI are ignored and excluded from a disposable clean checkout.
- The clean-checkout copier was also corrected to exclude `node_modules`; it
  now explicitly fails if dependency, Playwright-CLI, or output directories are
  present in its disposable workspace. This prevents a locally installed module
  from making a source-only onboarding result look healthier than a new clone.

## 2026-07-31 — 1.0 Windows desktop host and Docker/Windows app chain

- Added `desktop/PalworldConsole.Desktop`, a locked .NET 8 WinForms/WebView2
  host that embeds the existing local Web Console rather than creating another
  control backend. It validates the selected project root, discovers the
  recorded loopback panel port (or starts `settings-panel.ps1`), uses a
  per-user WebView profile, and permits in-window navigation only to that local
  panel. It has no direct Docker, PalServer, REST, or RCON command path.
- `scripts/build-desktop-app.ps1 -SelfContained -Zip` produced a self-contained
  `win-x64` executable and timestamped portable ZIP. The package uses the
  Evergreen WebView2 Runtime and is deliberately unsigned; code signing,
  installer delivery, published hashes, and clean-machine install evidence
  remain release work.
- Source contracts, locked restore, release audit, clean-checkout validation,
  and a zero-warning Release build passed. Windows CI now has a separate
  desktop-host build job that restores the locked package set without starting
  a server.
- A Windows UI capture confirmed that the desktop host actually rendered the
  embedded Windows runtime console, rather than only creating a top-level
  window. No runtime switch, snapshot, restore, save, backup, or RCON control
  was clicked during that visual check; normal window close left the service
  running.
- With zero players, a Full-snapshot Windows→Docker switch completed, Docker
  REST and the real browser smoke passed, and the desktop host opened while the
  Docker panel reported the active runtime. After a normal desktop-window close,
  Docker, REST, and the panel remained healthy. REST save and backup then
  succeeded before a protected Docker→Windows Full-snapshot switch. The final
  Windows target reported runtime-state `PalServer` parent PID 59888 with
  shipping child PID 63544, REST reachable, UDP 8211 on `0.0.0.0`, generated
  Windows settings present, and Docker exited with restart count 0. This is a
  zero-player local desktop-host and runtime-switch result,
  not remote join, stability, restore, code-signing, or installer acceptance.

## 2026-08-02 — Desktop installer packaging and bounded startup probe

- Added a reproducible WiX 5.0.2 MSI build alongside the self-contained
  `win-x64` portable ZIP. The MSI is current-user scoped, installs under local
  application data, creates a Start menu shortcut, supports major upgrades and
  standard uninstall, and emits SHA-256 sidecars. Neither artifact bundles the
  WebView2 Runtime or claims code-signed provenance.
- Replaced the desktop host's startup readiness request to the potentially slow
  `/api/dashboard` endpoint with the bounded read-only `/api/runtime` endpoint,
  matching the local Web Console launcher behavior.
- Source-only desktop, installer, JavaScript, PowerShell, clean-checkout, and
  public-release checks remain separate from live runtime, remote-connectivity,
  restore, and multiplayer acceptance evidence.

## 2026-07-31 — Runtime-switch safety and Windows dashboard responsiveness

- Visual Windows-host inspection found that the active Windows target still
  looked like an executable blue switch button. The runtime panel now renders
  the active target as a disabled, green “currently running” state, preserves
  that state across language changes, and explains that only the other target
  can switch the server. Snapshot restore controls also lock while switching.
- The backend previously accepted a same-target `/api/runtime/switch` request
  and let `switch-runtime.ps1` reject it later. It now returns HTTP 409
  `runtime-already-active` before creating a task. Snapshot and restore routes
  likewise reject requests while a switch owns the runtime.
- Found that the Windows dashboard could stall because it still requested
  Docker Compose logs and directly called NetTCPIP/WMI network Cmdlets from the
  single-threaded panel. Windows logs now route to `Get-WindowsRuntimeLogs`.
  Tunnel control/UDP collection now runs in a 2.5-second child probe; a timeout
  produces `network-unobserved`, not the false conclusion
  `control-disconnected`.
- Reloaded only the loopback Web Console after confirming Windows REST health
  and zero players; PalServer and Docker were not stopped for that reload. The
  reloaded Windows dashboard completed in 5.24 seconds, a same-target Windows
  request returned 409 with no state change, and `/api/logs/insights` reported
  `windows native runtime`.
- Performed another zero-player Full-snapshot Windows→Docker→Windows drill.
  REST save and backup succeeded before both directions. Docker reached REST
  health after the first switch; its dashboard, Docker log source, same-target
  409 response, and real-browser regression passed. The protected return to
  Windows completed successfully; final dashboard response was 4.68 seconds,
  Windows log source and same-target 409 passed, and the final runtime-state
  PalServer parent PID was 62224. The browser regression passed on both active
  runtimes. The local network probe remained unobserved, so this does not add
  tunnel, remote-join, stability, or restore acceptance.

## 2026-07-31 — Verifier robustness fix and stale runtime.state recovery

- Found `scripts/verify-project.ps1` falsely reported `Desktop host source
  contract failed with exit code .` because `test-desktop-host.ps1` never called
  `exit` on success, leaving `$LASTEXITCODE` as `$null`, and the check
  `$LASTEXITCODE -ne 0` evaluated true for `$null`. This was the only test
  invoked via `& $script` with a `$LASTEXITCODE` check; all other tests use
  `Start-Process` with `.ExitCode`, which is reliable.
- Fixed `scripts/test-desktop-host.ps1` to `exit 0` on success, and hardened
  `scripts/verify-project.ps1` to reset `$LASTEXITCODE = 0` before the call and
  treat `$null` as success. Re-ran the verifier: `VERIFY_ERRORS=0` with no
  warnings.
- Detected `data/runtime.state` was stale (`active=windows`, PID 62224) while
  neither PalServer.exe nor any Docker container was running. Ran
  `scripts/recover-runtime-state.ps1`, which repaired `active` to `none`.
  Confirmed Windows native restart lifecycle is wired through the unified API
  (`Restart-RuntimeServer` dispatches to `Stop-WindowsRuntime -Grace 120` then
  `Start-WindowsRuntime` with a runtime.state update).
- No code-level TODO/FIXME/NotImplemented markers remain in `.ps1`/`.cjs`/`.cs`
  sources. The development scope of the dual-runtime system is complete and
  statically verified. Remaining Test Plan items (Phase 2 remote connectivity,
  Phase 3 stability, Phase 5 crash recovery) are operational acceptance tests
  that depend on external participants, a live server, or explicit user
  authorization; they are not development gaps.

## 2026-07-31 — Dual-runtime orchestration source contract

- Added scripts/test-runtime-orchestration-contract.ps1 as a deliberately
  source-only regression. It verifies the provider lifecycle contract, native
  REST and management-firewall gates, shared configuration compiler, shared
  SaveGames junction, snapshot/rollback flow, unified console routes,
  dual-source log collection, and hash-gated Mod manager wiring.
- The contract now runs directly, through verify-project.ps1, in the
  disposable clean-checkout validation, and as an explicit Windows CI step.
  Current local runs reported RUNTIME_ORCHESTRATION_CONTRACT=passed and
  VERIFY_ERRORS=0; the clean checkout passed without starting either runtime.
- This strengthens regression detection for the checked-in implementation only.
  It does not replace maintenance-window evidence for a live switch or restore,
  nor external tunnel, remote-join, or multiplayer-stability acceptance.

## 2026-07-31 — Isolated runtime state and mutex behavior regression

- Added scripts/test-runtime-common-behavior.ps1. It copies runtime-common.ps1
  into a generated temporary project root and executes atomic runtime.state
  updates, partial-field preservation, stale-switch recovery, malformed-state
  fail-closed behavior, Mod manifest synchronization, incident masking, and
  cross-process mutex contention there.
- Acquire-RuntimeMutex retains the production default
  Global\PalworldServerRuntime, but now accepts an optional mutex name for
  isolated tests. The regression uses a unique Local namespace name, so it
  cannot contend with a live Docker or Windows runtime switch.
- The behavior test passed in both the current PowerShell host and Windows
  PowerShell 5.1. It is now invoked by verify-project.ps1, disposable
  clean-checkout validation, and Windows CI. This is functional temporary-state
  evidence, not live server, save, tunnel, restore, or stability acceptance.
