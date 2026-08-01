# Mod Manager Reservation

This directory reserves a fail-closed Mod management workflow. No Mod is configured or installed.

Current state:

- `managerEnabled`: `false`
- `runtime`: `linux-docker`
- manifest entries: `0`
- `data\Mods\` is intentionally absent

Palworld 1.0 currently supports server-side Mods only on the Windows dedicated server. The current server runs the Linux Docker build, so `Sync` refuses to write any game directory even if a manifest entry is added.

The reserved workflow follows the official Windows dedicated-server structure:

- Workshop source: Steam client Workshop directory
- Staging target: `data\Mods\Workshop\<WorkshopId>\Info.json`
- Activation: `data\Mods\PalModSettings.ini`
- Updates: compare the local Workshop source hash with `expectedSha256`, review it, update the approved hash, then run `Sync`
- Deployment: the Windows dedicated server deploys `Info.json` install rules after restart

## Commands

```powershell
# Read-only status
.\scripts\mod-manager.ps1 -Action Status

# Validate the empty/disabled manifest
.\scripts\mod-manager.ps1 -Action Validate

# Future: inspect source hash and check for changes
.\scripts\mod-manager.ps1 -Action Hash -ModId 1234567890
.\scripts\mod-manager.ps1 -Action Check

# Future: copy approved Workshop content and generate PalModSettings.ini
# This is blocked while managerEnabled=false or runtime=linux-docker.
.\scripts\mod-manager.ps1 -Action Sync
```

To add a Mod in the future:

1. Confirm the server has moved to a Mod-compatible Windows dedicated runtime.
2. Subscribe/download the Workshop item through Steam.
3. Copy an entry template into `manifest.json` with `enabled=false` and an empty `expectedSha256`.
4. Run `Hash`, inspect `Info.json`, confirm `IsServer=true`, then record the returned approved SHA-256.
5. Set the entry `enabled=true`.
6. Only after all entries validate, set `runtime=windows-dedicated` and `managerEnabled=true`.
7. Run `Check`, back up the world, run `Sync`, then restart in a maintenance window.

The manager never downloads arbitrary URLs, never installs a loader, never modifies `ManagedMods`, and never silently accepts a new hash.

Entry template:

```json
{
  "workshopId": "1234567890",
  "displayName": "Example server Mod",
  "packageName": "PackageNameFromInfoJson",
  "enabled": false,
  "sourceFolder": "1234567890",
  "expectedSha256": "",
  "updatePolicy": "manual",
  "dependencies": [],
  "notes": "Confirm client requirements and save compatibility."
}
```

Official reference: <https://docs.palworldgame.com/settings-and-operation/mod/>
