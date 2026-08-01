# Windows desktop application

`PalworldServerConsole.exe` is the 1.0 Windows desktop host for the existing
local Web Console. It embeds the same web frontend in Microsoft Edge WebView2;
it does not create a second Docker, Windows-runtime, REST, RCON, or settings
backend.

## What it manages

After selecting a valid PalworldServer project directory, the application:

1. Reuses a reachable local Web Console, or starts `settings-panel.ps1` if no
   local panel is responding.
2. Opens the existing Web Console inside a desktop window.
3. Lets the existing protected API control the active Docker or Windows-native
   runtime, including the established save, backup, switch and confirmation
   safeguards.

The application itself never starts a game runtime, calls `docker.exe`, calls
`PalServer.exe`, opens a network listener, or makes the Web Console remotely
reachable. Closing it does not stop the panel or either game runtime.

## Build and package

Requirements: Windows 11 x64, .NET 8 SDK, and Internet access to the public
NuGet registry for the first restore.

```powershell
.\scripts\test-desktop-host.ps1
.\scripts\build-desktop-app.ps1 -SelfContained -Zip
```

The published application is written under `output\desktop-app\`; output is
local and ignored by Git. `-SelfContained` packages the .NET runtime for the
selected Windows architecture. `-Zip` creates a timestamped archive without
replacing an earlier package.

The ZIP is a portable package, not an installer. It is currently unsigned; a
public release must add code signing, a published SHA-256, release notes, and a
fresh clean-machine install check before it is presented as a trusted download.

Run the resulting executable with an explicit project root when it is installed
outside the repository:

```powershell
& 'C:\path\to\PalworldServerConsole.exe' --project-root '<project-root>'
```

On first launch without this argument, select the project folder containing
`settings-panel.ps1`, `docker-compose.yml`, `web\index.html`, and `.env`.
The selected path is stored only under the current user's local application-data
directory.

## WebView2 Runtime

The package uses the Evergreen Microsoft Edge WebView2 Runtime already present
on many Windows 11 installations. It is not bundled with the repository or the
application. If it is missing, the application shows an actionable message and
offers to open the official Microsoft WebView2 page; it does not alter the
server or install software automatically.

## Evidence boundaries

A successful desktop-window launch proves that the local host can reach the
same loopback panel used by a browser. It does not prove a remote tunnel join,
multiplayer stability, backup restore, or a player-management command. The
underlying runtime evidence rules in the Web Console and maintenance runbook
remain unchanged.
