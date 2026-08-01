# Security policy

## Supported source line

Security fixes are accepted for the current `main` branch. Deployed servers must
also keep their Palworld server files and the pinned container image under an
operator-controlled update process; source changes alone do not update a live
server.

## Reporting a vulnerability

Do not open a public issue for a vulnerability that could disclose credentials,
player data, save files, a reachable management endpoint, or a tunnel address. Use
the repository's private security-advisory feature when it is enabled, or contact
the repository maintainer through an existing trusted private channel. Include a
minimal reproduction, affected version or commit, impact, and safe remediation
idea. Do not attach real `.env` files, logs, backups, or save data.

## Operational boundaries

- Only game UDP 8211 may be externally reachable.
- REST, RCON, Docker, backup storage, and the Web Console must remain local-only.
- Treat `/players`, `/game-data`, diagnostics, and daily log archives as sensitive.
- Before server, image, or configuration updates: check players, save through REST,
  create a versioned backup, then stop gracefully.
- A restore is destructive and must be performed only in an approved maintenance
  window with a pre-restore snapshot.
