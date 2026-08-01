# Changelog

All notable source changes are recorded here. This project follows the structure
of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the release
policy in [`docs/versioning-and-releases.md`](docs/versioning-and-releases.md).

The changelog describes source delivery only. It never proves that a live server,
tunnel, backup restore, or remote player connection has been verified.

## [Unreleased]

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

## Release history

No versioned public release has been created yet.
