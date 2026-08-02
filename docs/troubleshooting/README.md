# Troubleshooting

- Run `scripts\test-host-prerequisites.ps1` for local dependency checks.
- Run `scripts\verify-project.ps1 -SkipDocker` for source checks.
- Use `scripts\export-support-bundle.ps1` before opening a public issue.
- For Sakura FRP, compare the local UDP listener, provider state, and an
  external player test separately.
- For save problems, stop the active runtime and follow the save-boundary and
  maintenance-window documents. Do not infer recovery from a copied archive.
