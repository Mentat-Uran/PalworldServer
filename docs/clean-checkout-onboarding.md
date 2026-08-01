# Clean-checkout onboarding validation

`scripts/test-clean-checkout.ps1` copies the allowed project source into a newly
created disposable workspace, initializes it only from `.env.example`, and runs
the project's static validation. GitHub Actions runs it from a clean checkout;
local runs also exclude machine-local runtime data and ad-hoc scratch files. It
does not copy your `.env`, `data`, backups, logs, Windows server installation,
SteamCMD installation, or Git data.

Run from a checkout:

```powershell
.\scripts\test-clean-checkout.ps1
```

The script removes the temporary workspace on success or failure. To inspect it
afterward, use `-KeepWorkspace`; the emitted path may contain only its generated
test configuration and disposable data marker, never a production world copy.

```powershell
.\scripts\test-clean-checkout.ps1 -KeepWorkspace
```

This is deliberately a source-only test: it calls
`verify-project.ps1 -SkipDocker` and never runs `docker compose up`,
`palworld.bat`, a runtime switch, restore, update, backup, or tunnel launcher.
Run Compose rendering and any live-server validation separately and only within
the boundaries documented in `CONTRIBUTING.md`.

The static validation includes
`scripts/test-runtime-orchestration-contract.ps1`. It checks that the checked-in
Docker and Windows providers, shared configuration compiler, save junction,
snapshot/rollback flow, unified Web Console routes, log collector, and
hash-gated Mod manager remain wired together. It proves source composition
only; it is not evidence that a live switch, restore, remote join, or
multiplayer stability run has succeeded.

The static suite also runs scripts/test-runtime-common-behavior.ps1 under its
own generated project root. It executes atomic state updates, stale-switch
recovery, malformed-state fail-closed behavior, empty-Mod manifest synchronization,
incident masking, and cross-process mutex contention without using the live
state file or any Palworld process.
