# Compatibility contract

Reviewed: 2026-07-31. This is a source and configuration compatibility contract,
not a claim that every listed combination has received a live-server test.

## Supported baseline

| Component | Supported range | Evidence boundary |
|---|---|---|
| Host OS | 64-bit Windows 11 with PowerShell 5.1 or later | Windows static CI validates source on `windows-latest`; it does not start a server. |
| Container path | Docker Desktop with WSL2 backend and Docker Compose v2 | Required by the selected Docker runtime. Docker Desktop releases are not broadly qualification-tested. |
| Windows-native path | 64-bit Windows 11 Palworld Dedicated Server installed by `scripts/install-win-server.ps1` | A local Docker→Windows→Docker Full-snapshot regression reached native REST health, settings, empty-player response, SaveGames junction, firewall gate, and return to Docker. It is not tunnel, multiplayer-stability, or destructive-restore acceptance. |
| Palworld dedicated server | Exact locally tested build: `v1.0.2.101103` | Docker and Windows native runtime both reported this version in the 2026-07-31 local regression. This is not a promise that later Palworld builds are compatible. Back up and review before every update. |
| Docker image | `thijsvanloef/palworld-server-docker@sha256:401d3eb5c053bcd72949e1ede8c4e38be5e5ad66be7272ac37940706df0aeb2f` only | Digest-pinned selected deployment; changing it requires a documented compatibility review and backup. |
| Node.js | 22.x for CI; 22–24 for local tooling | CI uses Node 22. The optional browser smoke locks `playwright-core` in `package-lock.json`, installs it with `npm ci`, and connects to an installed local Chrome. |
| Windows desktop host | Windows 11 x64; .NET 8 or self-contained x64 publish; Evergreen WebView2 Runtime | The host embeds only the local Web Console and uses its protected APIs for Docker/Windows controls. It does not add a remote listener or independently start a game runtime. |

## Explicitly unsupported or unqualified

- Docker Desktop on a non-WSL2 backend, non-Windows hosts, ARM64/Box64 settings,
  and public exposure of REST, RCON, Docker, or Web Console are not supported by
  this project contract.
- Linux Docker server Mods remain fail-closed. `bAllowClientMod` does not prove
  that server Mods are installed or supported.
- Xbox/PS5 connectivity is not asserted. The current deployment has
  `COMMUNITY=false`; listing a platform in a setting does not establish join
  compatibility.
- New game-server builds and new container-image digests are unqualified until
  they have a recorded pre-update backup, static validation, and approved runtime
  evidence.

## Upgrade evidence required

Before expanding any exact baseline above, record the source and target versions,
data scope, backup location, test steps, pass criteria, observed outcome, and
recovery path. `UPDATE_ON_BOOT=true` may update game files while the image digest
remains fixed, so the image digest alone cannot identify the server build.
