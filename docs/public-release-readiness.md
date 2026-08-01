# Public-release readiness

This repository is designed to be reusable source for self-hosted Palworld
operators. It is not a hosted service, and publishing its source must never
publish a world, a player record, a tunnel address, a backup, an `.env` file,
or a local management interface.

## Pre-publication commands

Run these from a candidate release checkout:

```powershell
.\scripts\audit-public-release.ps1 -Strict
.\scripts\test-clean-checkout.ps1
.\scripts\verify-project.ps1
```

`audit-public-release.ps1` is read-only and examines tracked source only. It
rejects machine-local paths, likely deployment endpoints, likely real secret
assignments, and a wildcard or remote-management Web Console. It is a useful
guardrail, not a substitute for a human review of release diffs or Git hosting
access settings.

While preparing uncommitted source, append `-IncludeUntracked` to audit both
tracked files and non-ignored candidate files. CI intentionally uses the default
tracked-file scope because that is the exact release input.

When the local Web Console is already running, maintainers can separately run
`scripts\test-web-console-boundary.ps1`. It is a read-only runtime probe: it
confirms loopback access, an invalid LAN host rejection, and a spoofed-host
non-loopback rejection without opening a player, game, or tunnel connection.

`test-clean-checkout.ps1` creates disposable configuration and data. Neither it
nor static validation starts a server, tests a tunnel, accesses a backup, or
proves a runtime feature.

## Maintainer decisions before the first public release

- Choose the repository owner, visibility, moderation contact, and protected
  branch policy in the hosting service.
- Review every tracked historical document. Keep general lessons, but remove
  host names, public addresses, player information, screenshots, and local file
  locations that do not help another operator.
- Decide whether GitHub Discussions, Issues, and private security advisories are
  enabled. `SUPPORT.md`, issue templates, and `SECURITY.md` describe the source
  workflow without assuming a particular account or email address.
- Create an annotated source tag only after the checklist in
  `versioning-and-releases.md` is complete. The MIT license already applies to
  this source; third-party game, image, Steam, and tunnel terms remain separate.

## Supported contribution boundary

Contributors may improve source, documentation, source-only tests, operator
workflows, and safe diagnostics. A contributor must not use an issue or pull
request to request access to another person's world, credentials, tunnel,
backup, logs, or Web Console. Runtime-changing work stays behind the maintenance
window and evidence requirements in `CONTRIBUTING.md`.
