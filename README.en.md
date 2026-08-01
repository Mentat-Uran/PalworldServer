# Palworld Local Server Console

Palworld Local Server Console is a Windows-first, local-safe management tool
for Palworld dedicated servers. It supports mutually exclusive Docker
Desktop/WSL2 and Windows-native runtimes, a protected shared save boundary, a
loopback-only Web Console, backups, diagnostics, and controlled runtime
switching.

This is not an official Pocketpair product. Palworld, Pocketpair, community
images, SteamCMD, Docker Desktop, WebView2, and external tunnel providers are
owned and operated under their respective terms.

The primary project guide is the Chinese [`README.md`](README.md). This file
is the English guide. Source code is released under the [MIT License](LICENSE).

## Five-minute path

The complete release asset is named `PalworldServer-<version>-win-x64.zip`.
It contains the project scripts, Web Console, desktop host, bootstrap script,
and documentation, but never contains game files, SteamCMD, saves, backups, or
passwords.

1. Download the asset from a trusted source and verify its `.sha256` sidecar.
2. Extract it to a writable directory.
3. Run `FIRST_RUN.bat`, or from the project root run
   `scripts\bootstrap-first-run.ps1 -Runtime windows`. It creates `.env`, a
   random admin password, and a password-free `project.json`. The password is
   never printed; store it in a password manager.
4. Run `scripts\test-host-prerequisites.ps1 -Runtime windows`.
5. For Windows-native hosting, run `install-windows-server.bat`, then run
   `start-windows.bat` during an approved maintenance window.
6. For Docker hosting, install Docker Desktop with WSL2 and run
   `start-docker.bat` during an approved maintenance window.
7. Open the desktop host or the loopback Web Console. Docker and Windows-native
   server runtimes must never run at the same time.

Rerunning the installer performs file, SteamCMD validation, settings, save
junction, and firewall consistency checks. It does not skip security checks
merely because `PalServer.exe` already exists.

## Computer requirements

| Area | Minimum to start | Recommended |
|---|---|---|
| Operating system | Windows 10 22H2 or Windows 11, 64-bit | Windows 11, 64-bit |
| Memory | 8 GiB may start but is not a stability or recommendation claim | At least 16 GiB available memory |
| Disk | The installer preflight requires at least 8 GB free | Keep at least 30 GB for the OS, server updates, saves, and backups |
| Network | Access to SteamCMD and selected dependencies | Stable wired or high-quality Wi-Fi; public modes also need UDP reachability |
| Windows runtime | PowerShell 5.1+, WebView2 Runtime, administrator rights for firewall changes | PowerShell 7 and the current Evergreen WebView2 Runtime |
| Docker runtime | Docker Desktop, WSL2, Linux containers | A WSL2 memory and disk allocation that meets the server baseline |

“Can start” and “meets the recommended baseline” are different states. A host
below 16 GiB must not be described as meeting the recommended requirement.
Put optional Docker resource limits in the local, untracked
`docker-compose.override.yml`, not in the public Compose default.

## Network modes and ports

`NETWORK_MODE` has three mutually exclusive modes:

- `direct`: configure router port forwarding yourself and expose only the game
  UDP `PORT`.
- `community`: configure `COMMUNITY=true`, `PUBLIC_IP`, and `PUBLIC_PORT`;
  listing and cross-platform joining still require an external test.
- `tunnel`: select an explicit UDP provider. Only the game port is tunneled;
  the Web Console, REST, and RCON ports are never tunneled.

The default is `direct`. REST is the primary management channel and uses the
loopback `REST_API_PORT=8212`. RCON is disabled by default and must not be
exposed through a router, tunnel, or reverse proxy. The default game UDP port
is `8211` and the query port is `27015`; the local `.env` is authoritative.

The console distinguishes a running server process, a usable local port, a
running tunnel process, and an actual external player connection. The first
three do not prove the fourth.

### Sakura FRP

Sakura FRP is supported as an explicit optional provider. The project does not
install, start, or stop any third-party tunnel by default. Read the official
documentation first:

- [Sakura FRP basics](https://doc.natfrp.com/basics.html)
- [frpc usage](https://doc.natfrp.com/frpc/usage.html)
- [frpc manual](https://doc.natfrp.com/frpc/manual)
- [UDP game troubleshooting](https://doc.natfrp.com/faq/network.html)
- [Official downloads](https://www.natfrp.com/tunnel/download)

Create a UDP tunnel to `127.0.0.1` and the local `.env` `PORT`. Then set
`NETWORK_MODE=tunnel`, `TUNNEL_PROVIDER=sakurafrp`, and make
`TUNNEL_LOCAL_PORT` equal `PORT`. Set `TUNNEL_EXECUTABLE` only if the project
should launch an already installed provider executable. Never put provider
tokens or private configuration in the README, issues, logs, or support
bundles. Never tunnel Web Console, REST, or RCON.

Provider readiness and a local UDP listener do not prove external access. Test
from a network that is not the same LAN and record the evidence separately.
Other providers are documented under `providers/`; the default is `none`.

## Safety and privacy

- Never commit `.env`, saves, backups, logs, runtime markers, SteamCMD,
  installed server files, tunnel credentials, webhook URLs, or player data.
- Keep the Web Console, REST, and RCON on loopback by default.
- Do not start, stop, restart, switch, restore, update, or rebuild a live
  runtime without an approved maintenance window and current preflight.
- Static checks, historical logs, process starts, tunnel registration, and a
  local listener do not prove external connectivity, recovery, or multiplayer
  stability.
- Use REST for saving, announcements, player management, and graceful
  shutdown. Legacy RCON is an explicitly enabled compatibility path only.

## Backups, updates, and restore

Save the world before creating a timestamped backup. Before an update, record
the current game-server build. A pinned container image digest does not pin the
Palworld game files, so do not treat `UPDATE_ON_BOOT` as a risk-free automatic
update. Prefer `UPDATE_ON_BOOT=false` and a maintenance-window workflow:
check, save, back up, update, health-check, verify save integrity, and retain a
rollback path.

Read the [maintenance runbook](docs/maintenance-window-runbook.md),
[compatibility contract](docs/compatibility.md), and
[save guidance](docs/getting-started/saves.md) before destructive operations.

## Local development and release

`version.json` is the single source of the project version. Use
`scripts\bump-version.ps1 -Version <major.minor.patch>` to update release
metadata, then run the local checks:

```powershell
.\scripts\test-version-consistency.ps1
.\scripts\verify-project.ps1 -SkipDocker
.\scripts\test-clean-checkout.ps1
.\scripts\test-desktop-host.ps1
.\scripts\test-desktop-installer.ps1
.\scripts\build-desktop-app.ps1 -SelfContained -Msi -Zip
```

Build the complete Windows bundle with:

```powershell
.\scripts\build-release-bundle.ps1 -DesktopPublishDir .\output\desktop-app\win-x64\Release
```

The maintainer completes local tests, builds, sensitive-file auditing, and
SHA-256 generation before pushing to GitHub and creating a Release in one
publication step. GitHub Actions is a secondary source-validation aid, not the
primary release proof.

## Support bundles

Generate a redacted bundle before opening a public issue:

```powershell
.\scripts\export-support-bundle.ps1
```

It contains versions, dependency versions, runtime type, port summaries,
validation results, error codes, and redacted logs. It excludes passwords,
webhooks, public or tunnel addresses, player IDs, saves, backups, the complete
`.env`, and raw command text.

## Documentation

- [Quick start](docs/quick-start.md)
- [Installation and first setup](docs/getting-started/install.md)
- [Networking](docs/getting-started/networking.md)
- [Daily operations](docs/user-guide/daily-operations.md)
- [Troubleshooting](docs/troubleshooting/README.md)
- [Architecture and evidence model](docs/architecture.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
