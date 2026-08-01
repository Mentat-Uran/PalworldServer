# Architecture

Palworld Local Server Console is a single-project, single-instance manager.
Docker and Windows-native Palworld runtimes are alternatives and share one
save boundary; they must not run concurrently.

## Boundaries

- `settings-panel.ps1` is a loopback-only HTTP console.
- `scripts/management-api.ps1` is the shared REST endpoint and authentication
  adapter.
- `scripts/win-runtime.ps1` and `scripts/docker-runtime.ps1` implement the
  same runtime operations.
- `scripts/runtime-common.ps1` owns atomic runtime state, mutex, incidents,
  and switch evidence.
- `scripts/tunnel-provider.ps1` owns only provider processes recorded by this
  project. The default provider is `none`.
- `data/Pal/Saved/SaveGames` is the shared save boundary. It is private and
  must not be committed.

## Management contract

REST is enabled by default and binds to the configured local management port.
The normal management operations are save, announce, kick, ban, unban, and
shutdown. Legacy RCON is opt-in and is not a dependency for backups or normal
shutdown.

The public game UDP port is separate from all management ports. A tunnel may
forward only the game UDP port. The Web Console, REST, and RCON must remain
loopback-only.

## Evidence model

Source validation proves source contracts. A local process or listener proves
local readiness. A tunnel process proves provider lifecycle only. External
player connectivity, backup recovery, and multiplayer stability require their
own approved maintenance-window evidence.
