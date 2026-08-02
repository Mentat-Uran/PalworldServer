# Palworld Local Server Console

## A controllable, backup-friendly Palworld server for your own computer

Palworld Local Server Console is a Windows-first local management tool for a Palworld dedicated server. It brings installation, startup, shutdown, saving, backups, diagnostics, and controlled runtime switching into one local console. Docker and Windows-native runtimes share a protected save boundary and are mutually exclusive. Management interfaces are loopback-only by default.

If you want to avoid a pile of conflicting launch scripts while still saving and backing up the world before an update or runtime switch, this project is designed for that workflow. It is not a hosted service, it does not rent a server for you, and it is not an official Pocketpair product.

Palworld, Pocketpair, community images, SteamCMD, Docker Desktop, WebView2, Sakura FRP, and other third-party services are governed by their respective owners and terms. The project code is released under the [MIT License](LICENSE). The primary Chinese guide is [README.md](README.md).

## Features

- Windows-native and Docker Desktop with WSL2 runtimes, with a strict single-runtime boundary.
- A protected shared save boundary with snapshots and backups before runtime switching.
- A local Web Console for status, world saves, backups, settings, logs, and diagnostics.
- REST for normal management operations. RCON is disabled by default and is only an explicitly enabled legacy compatibility path.
- Controlled startup, shutdown, saving, announcements, player management, backups, restore, runtime switching, and maintenance checks.
- `direct`, `community`, and `tunnel` networking modes, with optional UDP providers such as Sakura FRP.
- Local version checks, source validation, desktop builds, installer builds, and redacted support-bundle export.
- Private-by-default handling for passwords, saves, backups, logs, player data, tunnel tokens, and other sensitive data.

The project is for users who can follow documentation and handle Windows permissions and network configuration. Each project directory manages one server; multiple project directories can coexist on one host when they use distinct `PROJECT_INSTANCE_ID` and ports. It should not be marketed as a zero-knowledge, one-click hosting service.

## Five-minute start

This section is the complete beginner path. You do not need to open another beginner guide first. Run all commands from the extracted project root.

### 1. Prepare the computer

Windows-native hosting is the recommended first path because it does not require learning Docker. Review the requirements and safety boundaries below before starting.

1. Download the complete `PalworldServer-<version>-win-x64.zip` release asset from a trusted source and verify its matching `.sha256` file.
2. Extract it to a writable, ordinary directory rather than a protected system directory.
3. Confirm that the computer meets the requirements below.
4. For Windows-native hosting, prepare PowerShell and WebView2. For Docker hosting, install Docker Desktop and WSL2 as well.

The complete release asset contains the project scripts, Web Console, desktop host, first-run script, and documentation. It does not contain Palworld game files, SteamCMD, world saves, backups, or passwords. An MSI or desktop ZIP is primarily a desktop-host package and does not replace the complete project bundle.

### 2. Create the first configuration

The simplest option is to double-click `FIRST_RUN.bat` in the project root. It creates a Windows-native configuration by default. To create a Docker configuration, run `FIRST_RUN.bat docker` from a command prompt.

From the project root, run:

```powershell
.\scripts\bootstrap-first-run.ps1 -Runtime windows
```

Use `-Runtime docker` instead if Docker is your initial runtime. The script creates `.env`, generates a random administrator password, creates a password-free `project.json`, and deliberately does not print the password to the terminal.

Store the generated administrator password in a password manager immediately. `.env` is private and must not be uploaded to GitHub, an issue, a screenshot, or a public support bundle. If `.env` already exists, do not use `-Force` without first making and reviewing a backup.

### 3. Check the host

For Windows-native hosting:

```powershell
.\scripts\test-host-prerequisites.ps1 -Runtime windows
```

For Docker hosting:

```powershell
.\scripts\test-host-prerequisites.ps1 -Runtime docker
```

Fix missing Docker, WSL2, WebView2, disk, permission, or port requirements before continuing. The installer may require an elevated PowerShell for firewall operations.

### 4. Install the Palworld server files

For Windows-native hosting, run:

```text
install-windows-server.bat
```

Or run the PowerShell installer from an elevated project-root shell:

```powershell
.\scripts\install-win-server.ps1
```

The installer downloads SteamCMD and Palworld Dedicated Server files. The first download may take time. Re-running it reuses existing files and still performs file checks, settings compilation, save-junction checks, and firewall consistency checks. The presence of `PalServer.exe` alone does not prove that every installation check passed.

Docker hosting does not require Palworld server files under `win-server`, but Docker Desktop must be running with WSL2 and Linux containers enabled.

### 5. Start exactly one runtime

During an approved maintenance window, start Windows-native hosting with:

```text
start-windows.bat
```

Start Docker hosting with:

```text
start-docker.bat
```

The launcher performs a protected runtime switch, then starts the configured tunnel provider, local Web Console, and log archiver. `TUNNEL_PROVIDER=none` is a safe no-op and does not start a third-party tunnel.

The Docker container and local runtime lock default to `PROJECT_INSTANCE_ID=palworld-server`. When deploying a second project directory on the same host, choose a different Docker-safe ID and non-conflicting game, REST, RCON, and Web Console ports.

Before the runtime switch, both launchers run a read-only host prerequisite gate. It checks the selected Docker/WSL2 or Windows-server path, disk and memory, and the configured tunnel executable; a failed gate leaves the runtime and Web Console untouched.

Docker and Windows-native hosting must never run at the same time. Before first use or a runtime switch, verify that no other runtime, Palworld process, or conflicting service owns the required ports.

### 6. Open the console and perform the first check

The launcher prints the local Web Console address. The desktop host can also open the project directory. On the first page, check the selected runtime, server process, local game port, REST management endpoint, save path, runtime state, and optional tunnel-provider state.

Before inviting players, save the world and create a backup. Then perform an external join test from a network outside the server's LAN. A running server process alone does not prove that Internet players can join.

## Computer requirements

“Can start” and “meets the recommended baseline” are different states. The minimum column only means that operation may be possible; it is not a claim of long-term multiplayer stability.

| Area | Minimum or baseline | Recommended |
|---|---|---|
| Operating system | Windows 10 22H2 or Windows 11, 64-bit | Windows 11, 64-bit |
| CPU | No single hard minimum; player count, mods, and world size matter | Four logical cores or more with headroom for the OS |
| Memory | 8 GiB may start but is not a stability or recommendation claim | At least 16 GiB available memory |
| Disk | Installer preflight requires at least 8 GB free | Keep at least 30 GB for the system, updates, saves, and backups |
| Network | Access to SteamCMD and selected dependencies | Stable wired or high-quality Wi-Fi; public modes also need UDP reachability |
| Windows runtime | PowerShell 5.1+, WebView2 Runtime, and administrator rights for firewall repair | PowerShell 7 and the current Evergreen WebView2 Runtime |
| Docker runtime | Docker Desktop, WSL2, and Linux containers | Sufficient WSL2 memory and disk allocation |
| Game server files | The first installation downloads about 5 GB of Palworld Dedicated Server files | Additional space for updates, temporary files, and backup growth |

A host below 16 GiB can be tested, but must not be described as meeting the recommended requirement. Put Docker CPU and memory limits in the local, untracked `docker-compose.override.yml`, not in the public default file.

## Network modes and ports

### `direct`: router forwarding

This is the default mode. Forward the game UDP port from your router to the server computer. Only the game port should be exposed. This mode does not require a third-party tunnel, but it requires router access and an ISP path that permits inbound UDP.

### `community`: community listing or public address

Use this mode only when you have deliberately configured the community parameters and public address. It generally requires `COMMUNITY=true`, `PUBLIC_IP`, and `PUBLIC_PORT`, plus version-specific query-port, password, and platform requirements. Appearing in a list does not prove that an external player can join; test from outside the LAN.

### `tunnel`: UDP tunneling

This mode maps the local game UDP port to a remote address and port assigned by a tunnel provider. It is useful when the home network cannot accept inbound connections. It must never be used to forward the Web Console, REST, or RCON management ports. A running tunnel process does not prove that an external player connected successfully.

The default game port is `PORT=8211` and the query port is `QUERY_PORT=27015`; the local `.env` is authoritative. The default REST management port is `REST_API_PORT=8212`. The default RCON port is `RCON_PORT=25575`, but RCON is disabled by default. The Web Console port is selected by the launcher and recorded in local runtime markers; use the address printed at startup.

The Windows-native runtime defaults to `WINDOWS_REST_COMPATIBILITY_MODE=ini-only`, following the official INI configuration. `compat` is reserved for a later build-specific probe that proves the legacy `-restapi` switch works; the current local build did not open 8212 even with that switch.

Keep management ports local. Do not forward REST, RCON, the Web Console, Docker management interfaces, or any configuration containing credentials to the Internet.

## Sakura FRP tunnel tutorial

Sakura FRP is an optional provider. The project does not install, start, or stop third-party tunnel software by default. Sakura FRP nodes, versions, quotas, billing, client behavior, and network policies are controlled by its service.

Official resources:

- [Sakura FRP basics](https://doc.natfrp.com/basics.html)
- [frpc usage](https://doc.natfrp.com/frpc/usage.html)
- [frpc manual](https://doc.natfrp.com/frpc/manual)
- [UDP game troubleshooting](https://doc.natfrp.com/faq/network.html)
- [Official downloads](https://www.natfrp.com/tunnel/download)

Follow these steps:

1. Create a UDP tunnel in the Sakura FRP client or control panel.
2. Set the local address to `127.0.0.1` and the local port to the `.env` `PORT`. Do not use the Web Console or REST port.
3. Record the remote address and port assigned by Sakura FRP. Those are the values external players will use.
4. Set the following in the local `.env`:

   ```env
   NETWORK_MODE=tunnel
   TUNNEL_PROVIDER=sakurafrp
   TUNNEL_LOCAL_PORT=8211
   ```

   If `PORT` is changed, `TUNNEL_LOCAL_PORT` must match it exactly.
5. Set `TUNNEL_EXECUTABLE` and any required local arguments only if the project should launch an already installed Sakura FRP executable. Never put access tokens, full private configuration, or private node details in README files, issues, logs, screenshots, or support bundles.
6. Run `start-windows.bat` or `start-docker.bat`. The launcher manages only provider processes recorded by this project and does not use a global `taskkill /IM` command to terminate unrelated same-name processes.
7. Verify the local server process and `PORT` listener first. Then test from a network outside the LAN using Sakura FRP's remote address and port.

If players cannot connect, check the UDP protocol, local-port match, remote port, server listener, and provider or ISP UDP restrictions. Do not treat “tunnel started” as proof of external connectivity.

Other providers are documented under `providers/`. The default provider is `none`; `generic-process` can connect another explicitly configured launcher.

Provider choices are discovered from `providers/*/provider.json`, so adding a provider does not require editing the central tunnel script. Keep only public metadata in the manifest; keep tokens and launch arguments in the local `.env`.

## Daily operation

### Status evidence

The home page reports runtime, server process, local port, REST endpoint, logs, and tunnel-provider state. These are different evidence levels:

| Observed state | Proves | Does not prove |
|---|---|---|
| Server process exists | A local process started | Server health, Internet access, or multiplayer stability |
| Local game port listens | A local socket is available | Correct router or tunnel forwarding |
| Tunnel process runs | The provider process is running | Successful external player connection |
| An external player joins | This external test succeeded | Long-term stability or backup recovery |

### Save, backup, and settings

Use this order before a restart, update, or runtime switch:

1. Notify online players.
2. Save the world.
3. Create a timestamped backup.
4. Change settings, update, or switch runtimes.
5. Check REST, logs, save state, and player connectivity after startup.

Announcements, player management, graceful shutdown, and saving use REST first. If the current Windows build has no native REST listener, the local RCON compatibility fallback is used for saves and selected player operations only when `ENABLE_LEGACY_RCON=true`. If neither REST nor RCON can confirm a save, the switch workflow refuses to stop the active server rather than modifying the save boundary without confirmation.

### Switch runtimes

Before switching, confirm that no other maintenance task is active, players have been notified, a recent backup is usable, and the target runtime is installed. State files, mutexes, and snapshots prevent both runtimes from operating on the same save. After a successful switch, recheck the server, REST endpoint, local port, and external connectivity.

### Stop the server

Stopping, restarting, restoring, updating, and switching a live server affect players and saves. Perform them only during an approved maintenance window. The stop scripts manage only project-owned processes; if process identity does not match, preserve the process and report the anomaly instead of force-killing every same-name process.

## Backups, updates, and restore

Record the current Palworld server version before an update, save the world, and create a backup. `UPDATE_ON_BOOT=false` is the recommended default. A pinned container image digest does not permanently pin the Palworld game files.

Restore changes the save and must stop the runtime first. Complete path, save, backup-integrity, and runtime-identity checks before restoring. Validate locally after restoration before allowing external players to connect. The existence of a backup file or a successful restore command is not, by itself, complete recovery evidence.

## Common problems

- **Project directory not found:** choose the root that contains `.env`, `settings-panel.ps1`, `docker-compose.yml`, and `web\index.html`, not a folder containing only an MSI or desktop ZIP.
- **`PalServer.exe` not found:** the Windows-native files are not installed yet. Run `install-windows-server.bat` again instead of starting the runtime directly.
- **Docker is not running:** only Docker hosting requires Docker Desktop. Start it and confirm WSL2 and Linux containers are enabled.
- **WebView2 is missing:** install the Microsoft Edge WebView2 Evergreen Runtime and reopen the desktop host.
- **A port is occupied:** during a maintenance window, identify the owner, runtime identity, and configured port before changing anything. Do not kill an unknown process.
- **External players cannot join:** test outside the LAN and separately inspect the game port, router or Sakura FRP UDP mapping, remote address, and server logs.
- **Health is unknown:** the console could not confirm process health within its time limit. Combine logs and process evidence; do not equate it with either a stopped server or a successful remote connection.

## Safety and privacy boundaries

- `.env`, saves, backups, logs, runtime markers, SteamCMD, installed server files, tunnel credentials, webhooks, player data, and public addresses are private and must not be committed to GitHub.
- Keep the Web Console, REST, and RCON local by default. Remote access requires an explicit network design and risk review.
- Do not start, stop, restart, switch, restore, update, or rebuild a live runtime without an approved maintenance window and current preflight.
- Static checks, historical logs, process starts, tunnel registration, and local listeners do not independently prove external connectivity, multiplayer stability, or successful recovery.
- Generate and inspect a redacted support bundle before opening a public issue. It must not contain passwords, tokens, player identities, saves, backups, or a complete configuration.

## Local development, testing, and release

`version.json` is the single source of project versioning. Update it with:

```powershell
.\scripts\bump-version.ps1 -Version 0.2.1
```

Run local validation and builds:

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

Build and sign the complete Windows formal release locally:

```powershell
.\scripts\publish-local-release.ps1 -CertificateThumbprint '<40-character certificate thumbprint>'
```

Formal publication must complete local tests, builds, Windows Authenticode signing, signature verification, and SHA-256 generation. The script preflights the local certificate and `SignTool.exe`, creates the desktop and complete source-bundle artifacts, writes checksums and a release manifest, and never tags, pushes, or creates a GitHub Release. After human review, upload the local artifacts manually. GitHub Actions is limited to source validation and release-policy checks; it must not build, sign, upload, or publish formal artifacts. Live start/stop, switching, restore, external connectivity, and multiplayer stability require separate approved evidence.

## Redacted support bundles

Before opening a public issue, run:

```powershell
.\scripts\export-support-bundle.ps1
```

The bundle should contain versions, dependency versions, runtime type, port summaries, validation results, error codes, and redacted logs. It must exclude passwords, webhooks, public or tunnel addresses, player identities, saves, backups, the complete `.env`, and raw command text.

## Further reading

The beginner installation, startup, networking, and daily-operation instructions are included in this file. For deeper troubleshooting or development, see:

- [Maintenance-window runbook](docs/maintenance-window-runbook.md)
- [Compatibility contract](docs/compatibility.md)
- [Architecture and evidence model](docs/architecture.md)
- [Troubleshooting](docs/troubleshooting/README.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## License

The project code is released under the [MIT License](LICENSE). Palworld, community images, SteamCMD, Docker Desktop, WebView2, Sakura FRP, and other external services are subject to their own licenses, terms, and usage limits.
