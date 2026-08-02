# Installation and first setup

Run all commands from the extracted project root. The Windows firewall step
requires an elevated PowerShell; the Web Console itself remains loopback-only.

1. Run `scripts\bootstrap-first-run.ps1 -Runtime windows`.
2. Review `.env` and keep the generated administrator password private.
3. Run `scripts\test-host-prerequisites.ps1 -Runtime windows`.
4. Run `install-windows-server.bat` for the Windows-native runtime, or install
   Docker Desktop with WSL2 and use the Docker launcher.
5. Start only one runtime during an approved maintenance window.

The installer shows SteamCMD output as it arrives, verifies the existing
installation on repeat runs, compiles the settings, checks the save junction,
and applies the configured management firewall gate.

For an existing project upgraded from an older configuration, run
`scripts\normalize-env.ps1` during a maintenance window before compiling or
starting the server. It creates a private backup under
`data\diagnostics\env-migrations`, migrates legacy setting names, fills only
missing values from `.env.example`, and preserves explicit operator choices.
