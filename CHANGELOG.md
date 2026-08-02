# Changelog

All notable source changes are recorded here. This project follows the structure
of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the release
policy in [`docs/versioning-and-releases.md`](docs/versioning-and-releases.md).

The changelog describes source delivery only. It never proves that a live server,
tunnel, backup restore, or remote player connection has been verified.

## [Unreleased]

No unreleased changes.

## [0.2.1] - 2026-08-02

### Fixed

- Configuration migration now derives missing values from the safe public
  template, preserves explicit operator settings, retains tunnel-provider keys,
  and creates a private rollback backup before rewriting `.env`.
- Cloud validation no longer restores or compiles the desktop host; formal
  release builds, Authenticode signing, signature verification, and artifact
  manifests are handled by the local release orchestrator for manual upload.
- Windows-native startup now uses the current documented PalServer argument set,
  keeps REST/RCON in the generated INI, and records the exact REST health
  endpoint when readiness fails. Windows REST now has an explicit
  `WINDOWS_REST_COMPATIBILITY_MODE` gate; the default remains `ini-only`, while
  the legacy `-restapi` probe is opt-in and did not fix the current local build.
  Windows health now falls back only to exact PalServer/game-UDP readiness;
  save and selected player operations use explicitly enabled loopback RCON when
  REST is absent, and runtime switching refuses to stop without a confirmed
  management save.
- Tunnel provider discovery and lifecycle validation now use public
  `providers/*/provider.json` manifests instead of a central SakuraFrp allowlist;
  custom process providers can be configured without editing the lifecycle
  script.
- Windows start launchers now run the read-only host prerequisite gate before
  runtime switching, including Docker/WSL2, disk, memory, Windows-server, and
  configured tunnel executable checks.
- Docker container identity and the local runtime mutex now derive from the
  optional `PROJECT_INSTANCE_ID`; the default remains `palworld-server`, while
  separate project directories can use distinct identities and ports.

## [0.2.0] - 2026-08-02

### Added

- Unified REST management operations, neutral defaults, explicit network modes,
  optional tunnel providers, first-run bootstrap, support bundles, and a
  complete source release bundle.
- A single version source and local version-consistency validation.

## [0.1.2] - 2026-08-02

### Added

- A beginner-first Windows-native onboarding path with a visible,
  double-clickable `install-windows-server.bat` launcher.
- Source and execution-contract coverage for the Windows installer BAT,
  including clean-checkout validation and CI coverage.
- Clearer desktop-host first-run guidance, quick-start documentation, and
  social-media copy covering MSI versus portable ZIP.

## [0.1.1] - 2026-08-02

### Fixed

- Explicitly pin the desktop host's private `Microsoft.NET.ILLink.Tasks` build
  dependency to 8.0.28 so locked restore is stable across current .NET SDK
  patch versions.
- Replace the player-session test's Windows-only `System.Web.Extensions` JSON
  dependency with the built-in PowerShell JSON cmdlets, keeping the same
  privacy-preserving data shape in Windows PowerShell 5.1 and PowerShell 7.
- Run the player-session regression explicitly in both supported Windows
  PowerShell hosts in CI.

## [0.1.0] - 2026-08-02

### Added

- Source-only Windows CI validation using a generated, non-secret `.env`.
- Contributor and private vulnerability-reporting guidance.
- Release governance, compatibility contract, collaboration templates, and a
  disposable clean-onboarding validation path.
- Privacy-preserving player-session accounting shared by the daily collector
  and Web Console read view.
- Windows-native lifecycle log source and explicit REST/RCON firewall gate.
- Public-release audit, read-only host prerequisite check, local Compose
  override example, support/governance/community documents, issue contact links,
  and Dependabot configuration.
- A source-only Chinese/English Web Console dictionary parity check.
- Source-contract checks for player-ID command insertion and goal-first Web
  Console actions, runnable without a browser or live game server.
- Self-contained Windows desktop delivery in both portable ZIP and current-user
  MSI forms, with Start menu integration, major-version upgrade support, and
  SHA-256 sidecars.

### Changed

- Player-duration rendering now has one shared formatter with second, minute,
  hour, and day boundaries. A disposable regression test covers first write,
  offline accumulation, reconnects, field variants, runtime attribution, and
  the no-raw-ID privacy boundary; browser smoke covers a multi-day table row.
- Web Console source no longer contains a deployment-specific remote origin,
  remote management password, or wildcard listener. It registers explicit
  loopback prefixes and rejects non-loopback requests before routing.
- Windows CI now runs the source suite under both Windows PowerShell 5.1 and
  PowerShell 7, with a no-BOM CI `.env` that is valid in both hosts.
- README now distinguishes required Docker-host dependencies from optional
  SakuraFrp remote access and an optional same-host Palworld game client.
- Added a read-only Web Console boundary probe for loopback success, invalid LAN
  host rejection, spoofed-host non-loopback rejection, and security headers.
- The optional Compose resource override now shows the official 16 GiB memory
  baseline, while the read-only host preflight reports when a host is below it.
- Added an English self-hosting guide covering safety, optional dependencies,
  quick start, runtime evidence, resources, releases, and contribution paths.
- English CPU and memory chart labels now match the Chinese dictionary; static
  validation fails when the two locale key sets diverge.
- Player session totals now close at the last confirmed online sample instead
  of adding an unobserved collector outage. The console labels this as observed
  time and a disposable regression covers both closing and fresh rendering.
- Windows CI now runs the disposable player-session accounting regression in
  both supported PowerShell hosts; static validation fails if that CI coverage
  is removed.
- The Web Console now translates static labels, accessible names, log headings,
  and log explanation/action prefixes in both locales. Its source check rejects
  missing Chinese/English dictionary entries referenced by HTML or literal
  translation calls.
- Browser-smoke prerequisites are now declared in `package.json`; the runner
  supports a documented Chrome path override and creates a fresh ephemeral
  DevTools endpoint instead of attaching to a fixed port.
- CI now installs and resolves the exact no-browser browser-smoke library with
  lifecycle scripts disabled; it does not download a browser or run the live
  browser smoke suite.
- Static validation follows the split Web Console source layout and checks the
  disabled Linux-safe Mod manifest.
- Windows player counts handle an empty REST player collection correctly; player
  session updates no longer depend on an open browser tab or store raw IDs.
- Daily archives distinguish Windows lifecycle events from best-effort engine
  output, and empty Mod manifests remain disabled after a Windows switch.
- Compatibility and operator-status documentation now records the current
  locally tested server version and actual Windows regression boundary.
- Maintenance preflight output now distinguishes a no-error precondition check
  from operational acceptance evidence.
- Windows native backups now create their destination, fail closed after a
  failed save, validate tar output, and retain a local-only RCON save fallback.
- The Overview now presents goal-first save, backup, player, tunnel, and log
  actions for operators who do not know Palworld commands. The RCON panel can
  prepare announcements, route through the active Docker or Windows runtime,
  insert in-memory selected player IDs without writing them to markup, and
  confirms kick, ban, unban, shutdown, and exit commands before dispatch.
- The desktop host now uses the bounded `/api/runtime` readiness endpoint rather
  than waiting on the slower dashboard telemetry endpoint.

## Release history

The latest public release is [v0.2.1](https://github.com/Mentat-Uran/PalworldServer/releases/tag/v0.2.1).
