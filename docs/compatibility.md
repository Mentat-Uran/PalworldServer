# Compatibility contract

Reviewed: 2026-08-02. This is a source and configuration compatibility contract,
not a claim that every listed combination has received a live-server test.

## Supported baseline

| Component | Supported range | Evidence boundary |
|---|---|---|
| Host OS | 64-bit Windows 11 with PowerShell 5.1 or later | Windows static CI validates source on `windows-latest`; it does not start a server. |
| Container path | Docker Desktop with WSL2 backend and Docker Compose v2 | Required by the selected Docker runtime. Docker Desktop releases are not broadly qualification-tested. |
| Windows-native path | 64-bit Windows 11 Palworld Dedicated Server installed by `scripts/install-win-server.ps1` | The current local build starts the game and query listeners and can expose legacy RCON when enabled; REST `/info` did not listen during the 2026-08-02 official-argument and RCON-disabled probes, so Windows-native management/switch acceptance remains unqualified. |
| Palworld dedicated server | Docker build reported `v1.0.2.101103`; Windows install recorded Steam build `24466863` | These are separate local observations, not proof that the two runtimes are equivalent. This is not a promise that later Palworld builds are compatible. Back up and review before every update. |
| Docker image | `thijsvanloef/palworld-server-docker@sha256:401d3eb5c053bcd72949e1ede8c4e38be5e5ad66be7272ac37940706df0aeb2f` only | Digest-pinned selected deployment; changing it requires a documented compatibility review and backup. |
| Node.js | 22.x for CI; 22–24 for local tooling | CI uses Node 22. The optional browser smoke locks `playwright-core` in `package-lock.json`, installs it with `npm ci`, and connects to an installed local Chrome. |
| Windows desktop host | Windows 11 x64; .NET 8 or self-contained x64 publish; Evergreen WebView2 Runtime | The host embeds only the local Web Console and uses its protected APIs for Docker/Windows controls. It does not add a remote listener or independently start a game runtime. Portable ZIP and current-user MSI packaging are source-supported; the MSI does not bundle WebView2. |

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
- Windows-native REST management is unqualified for the currently installed
  build until a local TCP listener and authenticated `/v1/api/info` response are
  both observed. A running game port or legacy RCON listener is not sufficient.

The Windows launcher now defaults to `WINDOWS_REST_COMPATIBILITY_MODE=ini-only`,
matching the official configuration contract. `compat` remains an opt-in probe
for older builds that may recognize the legacy `-restapi` switch; the current
local build was tested with that switch and still did not open TCP 8212.

The selected Windows behavior is fail-closed and layered: REST remains the
primary management path; when REST is absent, explicitly enabled loopback RCON
can handle `Save`, `Broadcast`, `KickPlayer`, `BanPlayer`, and `UnBanPlayer`.
If neither REST nor RCON can confirm a save, runtime switching refuses to stop
the active server. A healthy game UDP listener alone is not treated as a safe
save or management channel.

### Deferred next-window investigation

The 2026-08-02 approved local probe started the Windows-native server with the
current official argument set and verified the game/query UDP listeners and
legacy RCON when enabled. REST was enabled in the generated INI, but TCP `8212`
did not listen; disabling RCON separately produced the same REST result. The
server was stopped, the original save and Windows INI were restored, and no
runtime was left running. Continue from this evidence in a later maintenance
window rather than repeatedly restarting the formal server in the current
window. The next live probe should capture the generated INI hash, exact process
command line, TCP listener state, and authenticated `/v1/api/info` result, then
test the explicitly enabled RCON fallback once and restore the original save.

## Upgrade evidence required

Before expanding any exact baseline above, record the source and target versions,
data scope, backup location, test steps, pass criteria, observed outcome, and
recovery path. `UPDATE_ON_BOOT=true` may update game files while the image digest
remains fixed, so the image digest alone cannot identify the server build.
