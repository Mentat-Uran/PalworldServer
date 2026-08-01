# Contributing

## Scope and safety

This repository contains source code and a secret-free configuration template for a
locally operated Palworld server. Do not commit `.env`, `data/`, backups, save
files, logs, player identifiers, tunnel addresses, or screenshots containing those
values. Do not submit changes that expose REST, RCON, Docker, or the local Web
Console to the public internet.

Changes that start, stop, restart, switch, restore, update, or modify a live server
require an operator-approved maintenance window. A passing static check or CI run
does not authorize a runtime operation.

## Development workflow

1. Start from `.env.example`; create your own `.env` locally and set a strong,
   unique `ADMIN_PASSWORD`.
2. Keep Docker and Windows native runtimes mutually exclusive. Do not run an
   end-to-end runtime switch or restore against a shared world without a verified
   backup and operator approval.
3. Run the source checks before opening a pull request:

   ```powershell
   .\scripts\verify-project.ps1
   node .\scripts\test-i18n-parity.cjs
   node .\scripts\test-player-command-picker.cjs
   node .\scripts\test-console-guided-actions.cjs
   ```

   If Docker is intentionally unavailable, use `-SkipDocker`; this omits only the
   Compose rendering check. Warnings about local configuration or inactive runtime
   state must be reviewed rather than ignored blindly.
4. When the local Web Console is running, run the browser regression as a separate
   runtime check. Install the declared local development dependency first; it uses
   your installed Google Chrome and does not download a browser binary:

   ```powershell
   npm ci
   npm run test:ui
   ```

   If Chrome is not in a standard Windows location, set
   `$env:PALWORLD_UI_SMOKE_CHROME` to its executable path before the second
   command. This smoke check refreshes local tunnel/archive evidence and writes
   local screenshots, but it does not start, stop, switch, or reconfigure a game
   runtime.

5. Describe the evidence you ran and any skipped runtime checks in the pull request.

## Change expectations

- Preserve the source-of-truth roles: `.env` for local settings,
  `scripts/settings-catalog.ps1` for setting schema, and generated INI files as
  applied-output evidence.
- Keep secrets write-only in the Web Console and maintain localhost-only management
  interfaces.
- New settings, API routes, or UI controls need input validation, Chinese/English
  strings, keyboard/focus behavior, and an update to the applicable operator docs.
- Treat Mod support as fail-closed on Linux. Do not enable a Mod manager or add a
  server Mod without the documented source, compatibility, hash, and backup gates.

## Pull requests

Keep pull requests narrowly scoped. Include the user-visible or operational impact,
the commands run with their result, and any manual validation still required. Never
claim external connectivity, recovery capability, or configuration application from
a file existing or a process starting alone.
