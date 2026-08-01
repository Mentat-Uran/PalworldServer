# Maintenance-window runbook and evidence record

P2 operations are permitted only after the operator has approved a maintenance
window. This document is a runbook and evidence template; it neither grants
approval nor makes a runtime claim. Store completed records only under the
ignored local path `data\diagnostics\maintenance-evidence\`. Redact player
identifiers, IP addresses, passwords, Webhooks, full tunnel addresses, and world
contents before sharing any extract.

Completed records use JSON schema version 1 and must be validated locally:

```powershell
.\scripts\verify-maintenance-evidence.ps1 `
  -Path .\data\diagnostics\maintenance-evidence\2026-07-29-switch.json
```

The verifier is read-only. It validates structured fields and rejects obvious
credentials, player identifiers, and IP addresses, but it cannot establish that
an operator's statement is true. Do not validate the source-controlled
`maintenance-evidence.synthetic.json` without `-AllowSynthetic`; it is CI test
data, not a P2 record.

## Before every P2 operation

1. Announce the window and confirm no player is online through the primary REST
   API. Do not publish the player response.
2. Run the read-only preflight. It never starts, stops, saves, switches, restores,
   updates, or backs up a server:

   ```powershell
   .\scripts\test-maintenance-readiness.ps1 -Operation switch -Target windows
   ```

3. Resolve every `error` result. A stale `runtime.state` must first be examined
   with `recover-runtime-state.ps1 -DryRun`; changing a live state file requires
   operator direction during the window.
   `preflightReady=true` (and the legacy `ready=true`) means only that this
   read-only check found no blocking precondition. `acceptanceReady` is always
   `false` here; it cannot replace the executed-operation evidence below.
4. Record the source commit, image digest, exact game-server build, active
   runtime, data scope, backup location, planned pass criteria, and recovery
   path. A backup file's presence alone is not a restore acceptance result.
5. Before a planned update or switch, REST-save successfully, create the required
   versioned backup/snapshot, then stop gracefully. An RCON fallback or a failed
   save is an exception requiring an explicit record and cannot silently count
   as a passing drill.

## P2 acceptance criteria

### Docker to Windows and Windows to Docker

Run both directions as independent records. For each direction, require all of:

- exactly one runtime process before and after the action;
- successful REST save before stopping the source runtime;
- a verified pre-switch snapshot and a recorded SHA-256;
- target runtime REST `/info` and settings checks after it becomes healthy;
- the same approved world scope and a documented core save-game fingerprint
  before and after the switch. If the target runtime has already written a new
  save, record a scope-safe explanation for the byte difference; a live-file
  mismatch alone is not corruption evidence; and
- an explicit recovery action and the observed result if any criterion fails.

A target process starting, a health response, or a switch log ending in `ok` is
not sufficient by itself.

### Destructive restore rehearsal

Use a disposable world copy or identify the explicitly approved world scope.
Record the chosen snapshot name and digest, pre-restore safety snapshot, restore
command, post-restore integrity checks, and recovery path. Do not infer success
from archive extraction or the existence of a backup directory.

### Tunnel and six-player stability

For the tunnel, record a successful remote join or externally observed data
traffic in addition to the local UDP mapping, local process, control connection,
and proxy-ready log. For stability, record only aggregate data: 6 concurrent
players, start/end time, runtime/image/game versions, server health, and any
recovery action. Never put player lists, identifiers, locations, IPs, or raw logs
in a source-controlled record.

### Strict-vanilla decision

The operator must choose and record either a strict-vanilla policy or an
explicitly bounded mod-enabled-client policy. `bAllowClientMod=true` by itself
does not prove a server Mod exists, is safe, or is approved. Linux Docker Mods
remain fail-closed.

## Local evidence contract

Create a new ignored local JSON file for each operation. Required common fields
are `performedAt`, `operatorApproval`, `sourceCommit`, `runtime`, `versions`,
`dataScope`, `passCriteria`, `recovery`, `result`, and
`sensitiveDataIncluded=false`. The validator also requires the operation-specific
fields below:

| Operation | Required evidence in addition to common fields |
|---|---|
| `switch` | Successful REST save, verified pre-switch snapshot SHA-256, successful target REST `/info` and settings checks, plus before/after core save-game fingerprints. Explain any expected live byte difference; do not infer corruption from it alone. |
| `restore` | Verified selected snapshot SHA-256, pre-restore safety snapshot SHA-256, and successful post-restore integrity check. |
| `tunnel` | Local UDP/process/control/proxy checks plus remote join or external traffic observation. |
| `stability` | Aggregate-only run with at least 6 players, at least 60 minutes, and healthy end state. |
| `vanilla` | Explicit policy choice and confirmation that server Mods remain absent on Linux Docker. |

The source fixture is intentionally synthetic and must never be copied as real
evidence. It exists only so CI can execute the verifier:

```powershell
.\scripts\verify-maintenance-evidence.ps1 `
  -Path .\docs\maintenance-evidence.synthetic.json -AllowSynthetic
```
