# Support

Use the repository's bug-report template for a reproducible source or safe
operator-workflow defect, and the feature-request template for a proposal. Keep
reports redacted: do not attach `.env` files, passwords, player data, saves,
backups, logs, screenshots with identifiers, or tunnel addresses.

Before opening a report, run the read-only checks that apply to your setup:

```powershell
.\scripts\test-host-prerequisites.ps1 -Runtime docker
.\scripts\verify-project.ps1
```

Use `-Runtime windows` for the optional Windows-native server. Add
`-RequireTunnel` only if you are setting up remote UDP play. These commands do
not start a server or prove remote connectivity.

For a vulnerability, follow `SECURITY.md` and use a private channel. Do not
open a public support request.

This project supports self-hosting on the documented Windows baseline. It does
not provide hosted infrastructure, tunnel accounts, game support, save recovery
guarantees, or support for publicly exposing management interfaces.
