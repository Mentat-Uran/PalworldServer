# Palworld Server Toolkit

Palworld Server Toolkit is a local-first Windows toolkit for operating a self-hosted Palworld dedicated server. It supports Docker Desktop/WSL2 and Windows-native runtimes that share one protected save boundary, together with a loopback-only Web Console and maintenance scripts.

It is not an official Pocketpair product. Palworld, Pocketpair, community images, and external tunnel services remain separately owned and licensed.

## Included

- Docker Compose and Windows-native startup paths.
- Protected runtime switching, state checks, snapshots, and restore-oriented diagnostics.
- Local Web Console, configuration validation, backups, log archiving, and maintenance checks.
- Optional Windows desktop host for the local console, distributed as a
  self-contained portable ZIP and a current-user MSI installer.

## Quick start

1. Copy `.env.example` to `.env` and set a local administrator password.
2. Run `scripts/test-host-prerequisites.ps1 -Runtime docker`.
3. Start `start-docker.bat` or `start-windows.bat` during an approved maintenance window.

Read [`docs/clean-checkout-onboarding.md`](docs/clean-checkout-onboarding.md), [`docs/compatibility.md`](docs/compatibility.md), and [`docs/maintenance-window-runbook.md`](docs/maintenance-window-runbook.md) before operating a real server.

## Safety

Never commit `.env`, saves, backups, logs, runtime markers, installed binaries, tunnel credentials, webhook URLs, or player data. Keep the Web Console and management interfaces on loopback by default. Static checks and historical logs do not prove live connectivity, recovery, multiplayer stability, or production acceptance.

## GitHub Actions

GitHub Actions runs source-only Windows validation on pushes to `main`, pull
requests, and manual dispatch. It does not start Docker, PalServer, a tunnel,
or a live Web Console. The same checks can be run locally with
`scripts\verify-project.ps1 -SkipDocker`.

The desktop host is released in two forms: a self-contained ZIP that runs from
the directory where it is extracted, and a current-user MSI that installs to a
local application directory and creates a Start menu shortcut. Build both with
`scripts\build-desktop-app.ps1 -SelfContained -Msi -Zip -Version 0.1.0`.

## License

Project code is released under the [MIT License](LICENSE). Game software, community images, and external services are separately licensed.
