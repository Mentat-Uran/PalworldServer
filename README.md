# Palworld Server Toolkit

Palworld Server Toolkit is a Windows-oriented, local-first toolkit for operating a self-hosted Palworld dedicated server. It supports a Docker Desktop/WSL2 runtime and a Windows-native runtime that share one protected save layout, plus a local-only Web Console and maintenance scripts.

The project is an operations and safety toolkit, not an official Pocketpair product. Palworld, Pocketpair, community images, and external tunnel services remain the property and responsibility of their respective owners.

## What is included

- Docker Compose and Windows-native server startup paths.
- Runtime switching with state checks, mutex protection, snapshots, and restore-oriented diagnostics.
- A Web Console bound to loopback by default.
- Configuration validation, backups, log archiving, player-session aggregation, and maintenance-readiness checks.
- Optional desktop host source for the local Web Console.

The repository documents source-level behavior and local validation boundaries. A clean checkout or passing static check does not prove Internet reachability, multiplayer stability, disaster recovery, tunnel availability, or production acceptance.

## Quick start

1. Copy `.env.example` to `.env`.
2. Set a local administrator password and review the runtime values.
3. Run the host preflight:

```powershell
.\scripts\test-host-prerequisites.ps1 -Runtime docker
```

4. Start the selected runtime with `start-docker.bat` or `start-windows.bat` during an approved maintenance window.

Read [`docs/clean-checkout-onboarding.md`](docs/clean-checkout-onboarding.md), [`docs/compatibility.md`](docs/compatibility.md), and [`docs/maintenance-window-runbook.md`](docs/maintenance-window-runbook.md) before operating a real server.

## Safety and privacy

- Never commit `.env`, save games, backups, live logs, runtime markers, local output, SteamCMD files, installed server binaries, or personal diagnostics.
- Keep the Web Console and management ports on loopback unless an explicit, reviewed network policy says otherwise.
- Do not stop, restart, switch, restore, or rebuild a live server without an approved maintenance window and a current preflight.
- Treat snapshots and historical logs as evidence of files or past events, not as proof of a successful recovery or current external connectivity.
- Do not include passwords, webhook URLs, tunnel credentials, player identifiers, or private server addresses in issues or pull requests.

## GitHub Actions

This repository intentionally contains no GitHub Actions workflows. Validation is local and explicit; hosted automation is not part of the project’s operating model.

## Contributing

Read [`AGENTS.md`](AGENTS.md), [`CONTRIBUTING.md`](CONTRIBUTING.md), [`SECURITY.md`](SECURITY.md), and the relevant runbook before changing runtime behavior. Prefer read-only checks, preserve the current runtime identity, and report evidence boundaries honestly.

## License

Project code is released under the [MIT License](LICENSE). Game software, community container images, third-party tools, and external services are separately licensed.
