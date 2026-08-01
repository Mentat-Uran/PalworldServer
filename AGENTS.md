# AGENTS.md

This file describes the public contribution and safety rules for the Palworld Server Toolkit.

## Scope

The project manages a self-hosted dedicated server through explicit local scripts. Docker and Windows-native runtimes share one save boundary; they are alternative runtimes, not two servers to run concurrently.

## Safety rules

- Treat `.env`, save games, backups, logs, runtime markers, installed server files, tunnel credentials, webhook URLs, and player data as private and untracked.
- Do not start, stop, restart, switch, restore, rebuild, or update a live runtime without an approved maintenance window.
- Before runtime work, compare the observed process/container identity, health, ports, save path, and restart count. Recheck them afterward.
- Prefer read-only preflight and diagnostics. A static check, historical log, snapshot, or tunnel registration is not by itself acceptance evidence.
- Keep Web Console and management interfaces bound to loopback by default. Any remote access must be explicit and documented with its risks.
- Never invent a successful restore, external connection, multiplayer session, or stability result from missing evidence.

## Code and documentation

- Keep Docker and Windows behavior aligned around one documented save contract.
- Preserve fail-closed behavior for malformed state, unsafe paths, missing configuration, and ambiguous runtime identity.
- Keep secrets write-only and redacted from logs, API responses, screenshots, and documentation.
- Add or update focused local tests for changes to runtime switching, state files, configuration, Web Console contracts, or backup/restore logic.
- Distinguish source-level validation from live acceptance in README, runbooks, and release notes.

## Local checks

Use the project’s PowerShell and Node checks from a clean or disposable copy when possible. Do not run a live lifecycle test unless the user has approved the maintenance window and the required preflight has passed.

## Git and publication

- Inspect `git status`, the current branch, and the diff before staging.
- Never commit `.env`, `data/`, backups, logs, runtime markers, installed server files, generated output, credentials, or private player/server information.
- Keep commits focused and document what was actually validated.
