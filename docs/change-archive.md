# Change archive

This is an append-only, redacted record of engineering milestones. The Git
commit containing a record is its source rollback point. Runtime snapshots and
their SHA-256 values are recorded only when an approved operation touches
configuration or SaveGames.

## M0 — Source validation and native-config archive alignment (2026-07-29)

- Baseline: `ee00d9f` (`main` before this branch).
- Scope: source validation repairs, disabling an empty Mod manager, and a
  detected-state reconciliation; no server start/stop, REST save, snapshot
  creation, configuration compilation, or SaveGames mutation.
- Changes:
  - made `verify-project.ps1` validate the split `web/index.html`,
    `web/styles.css`, and `web/app.js` layout and syntax-check the actual JS;
  - made verification, switch snapshots, and restore write to the live native
    configuration path: `win-server\\Pal\\Saved\\Config\\WindowsServer`;
  - retained `Config\\WindowsServer` inside snapshot archives, so previously
    created archives stay readable while restores now target the live path;
  - changed recovery to compare `runtime.state` to detected Docker/PalServer
    processes instead of accepting any structurally valid state as current;
  - limited the recovery backup-freshness alert to an active runtime, so an
    intentionally offline server is not classified as having corrupt saves;
  - limited Mod runtime-drift validation to an active runtime, eliminating a
    false warning for the deliberately disabled, empty manager while offline;
  - ran recovery after a dry-run verified no Docker container or PalServer.exe;
    `data/runtime.state` now records `active=none`.
  - changed `mods/manifest.json` to disabled because it contains no approved
    Mods.
- Required validation: PowerShell parser checks for edited scripts; Node syntax
  checks for `web/app.js` and `scripts/ui-smoke.cjs`; project verification with
  Docker validation skipped; repository status review.
- Result: all four edited PowerShell scripts parsed successfully; both Node
  syntax checks passed; `verify-project.ps1` passed with `VERIFY_ERRORS=0`.
  The live-browser smoke suite was intentionally not run because the local Web
  Console and game runtime were offline.
- Evidence limit: this record does not prove runtime switching, restore,
  connectivity, tunnel reachability, or live configuration application.
- Rollback: revert the commit that contains this record. No data rollback is
  required because M0 intentionally does not modify runtime data.
