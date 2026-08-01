## Change summary

Describe the source, documentation, or operator-workflow change.

## Validation evidence

- [ ] `scripts/test-clean-checkout.ps1`
- [ ] `scripts/verify-project.ps1` (or explain why `-SkipDocker` was used)
- [ ] Browser/runtime checks, if applicable, with their result

State any validation that was not run and why. A static pass does not prove
runtime behavior, recovery, remote connectivity, or configuration application.

## Safety review

- [ ] No `.env`, password, webhook, player identifier, IP address, save, backup,
  diagnostic log, or private tunnel address is included.
- [ ] No management interface is exposed beyond localhost.
- [ ] Any live-server, switch, restore, update, or Mod change had an
  operator-approved maintenance window and a documented recovery path.
