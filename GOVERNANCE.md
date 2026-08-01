# Governance

The project is maintained through small, reviewable changes. Maintainers decide
scope, release timing, compatibility baselines, and security response after
reviewing evidence supplied in issues and pull requests.

## Decision rules

- Source-only changes require documented validation and can be reviewed without
  access to a live server.
- Changes that start, stop, switch, restore, update, or reconfigure a server
  require an operator-approved maintenance window and recovery plan.
- Compatibility claims require the exact source revision and, where relevant,
  game build and image digest. A successful process start or static CI run is
  not enough evidence for multiplayer, backup restore, or tunnel acceptance.
- Security and privacy outrank convenience: management interfaces remain
  loopback-only and runtime data never enters public issues or release assets.

## Maintainer continuity

Before a public release, the repository owner should configure branch protection
for `main`, require the source-validation workflow, and keep at least one backup
maintainer with access to private security reports. If the original maintainer
becomes inactive, a new maintainer should record the handover and avoid claiming
untested runtime compatibility.
