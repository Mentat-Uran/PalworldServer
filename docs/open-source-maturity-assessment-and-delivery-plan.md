# Open-source maturity assessment and delivery plan

Assessment date: 2026-07-31. This is an assessment of the repository and its
delivery controls, not evidence that any live server, tunnel, backup restore, or
remote connection has been verified.

## Current assessment

| Area | Status | Evidence and boundary |
|---|---|---|
| Reusable source | Established | MIT license, README, secret-free `.env.example`, modular Web Console source, and operator docs are present. Runtime data and secrets are ignored. |
| Safe operational model | Established | Docker and Windows runtime exclusivity, backups, localhost-only management, and fail-closed Mod rules are documented and implemented. A zero-player bidirectional Full-snapshot drill passed; this is not a substitute for P2 maintenance-window acceptance. |
| Static quality gate | Established | `scripts/verify-project.ps1` parses PowerShell and JavaScript, validates the settings catalog, compose contract, Mod manifest, runtime state, and generated-INI consistency. It now follows the split `web/index.html` / `web/styles.css` / `web/app.js` structure. |
| Browser regression | Partial | `scripts/ui-smoke.cjs` covers live-panel behavior. `package-lock.json` pins its no-browser `playwright-core` dependency and the smoke uses an installed Chrome with a fresh loopback DevTools handshake. A Windows-native loopback pass validated runtime-aware update/CPU semantics, both language directions, settings, logs, RCON and narrow layout; it still requires a running local Web Console and is intentionally not treated as a static CI pass. |
| Windows desktop host | Established | A locked .NET 8 WinForms/WebView2 project publishes a self-contained x64 executable, portable ZIP, and current-user MSI with Start menu and upgrade/uninstall behavior. It embeds only the existing loopback Web Console, has no direct Docker, PalServer, REST, or RCON control path, and preserves the backend's existing safeguards. The artifacts are unsigned; this is not remote-access or multiplayer acceptance. |
| Continuous integration | Established for source validation | GitHub Actions runs `npm ci --ignore-scripts` from the checked-in lock, resolves the no-browser library, then creates a CI-only `.env` and runs static validation plus the disposable player-session accounting regression on Windows PowerShell 5.1 and PowerShell 7, without Docker, a browser, or a live server. It cannot prove runtime behavior. |
| Contributor and vulnerability process | Established baseline | `CONTRIBUTING.md` and `SECURITY.md` define data handling, validation, maintenance-window, and private-reporting expectations. |
| Release governance | Established for first-release preparation | Changelog, versioning/release checklist, collaboration templates, compatibility contract, and clean-onboarding test are present. No public tag, signed artifact, or runtime acceptance is claimed. |
| Publication hygiene | Established for tracked source | `audit-public-release.ps1` rejects tracked runtime data, likely deployment endpoints, likely real `.env` secrets, and remote or wildcard Web Console paths. CI runs it against the exact tracked source set. Human diff review and hosting-account review remain required. |
| New-host experience | Established baseline | `test-host-prerequisites.ps1` reports Windows, `.env`, Docker/Compose/WSL or Windows-runtime prerequisites without starting services. A local Compose override example avoids editing shared source for host-specific CPU and memory limits. |
| Community continuity | Established baseline | Code of conduct, support boundary, governance guide, issue contact links, PR template, and Dependabot configuration make the project usable beyond a single operator without assuming a personal account or email address. |

## Delivery plan

### P0 — source safety and reproducibility

Delivered in this increment:

- Repair the stale static verifier after the frontend was split into external CSS
  and JavaScript files.
- Restore the empty Mod manifest to its documented disabled Linux-safe default.
- Add Windows GitHub Actions static validation with a CI-only non-secret `.env`.
- Add contribution and security-reporting boundaries.

Acceptance: GitHub Actions passes on a clean checkout; no CI step starts Docker,
the server, a runtime switch, or a restore.

### P1 — release readiness

Before the first public release:

1. Add a changelog, versioning policy, and release checklist that distinguishes
   source validation from live-server evidence.
2. Add issue and pull-request templates with secret and player-data warnings.
3. Document supported Windows, Docker Desktop, Palworld-server, and pinned-image
   compatibility ranges.
4. Produce a clean-checkout onboarding test using only `.env.example` and a
   disposable data directory.

Delivered in this increment:

- Add `CHANGELOG.md`, a semantic versioning policy, and a release checklist
  that keeps source validation separate from live-server evidence.
- Add issue and pull-request templates with explicit secret and player-data
  warnings.
- Add a compatibility contract that pins the only currently qualified image and
  game-server baseline and names unqualified paths.
- Add `scripts/test-clean-checkout.ps1`, which copies only source into a fresh
  disposable workspace, initializes `.env` from `.env.example`, and invokes
  static validation without Docker.
- Add public-release audit, read-only host prerequisite check, ignored Compose
  override example, contributor support/governance documents, issue contact
  links, and GitHub Actions dependency update configuration.
- Remove deployment-specific remote-panel origin and password handling. The Web
  Console now registers only loopback URL prefixes and rejects non-loopback
  requests before routing any API call.
- Add the locked `PalworldServerConsole` WinForms/WebView2 desktop host and its
  x64 self-contained ZIP/MSI packaging script. It discovers or starts only the
  existing local panel and leaves game-runtime actions to the protected backend.

Acceptance: source-only checks pass on the disposable workspace and the tracked
source passes the publication audit. The first public tag, executable signing,
hosting-account configuration, and all P2 runtime evidence remain separate
work. The MSI/ZIP package and SHA-256 sidecars are now part of the source release
build, but code signing and clean-machine installation evidence remain separate.

### P2 — operational confidence

Only in operator-approved maintenance windows:

1. Run and record Docker-to-Windows and Windows-to-Docker switch drills.
2. Rehearse destructive backup restore using a disposable or explicitly approved
   world copy.
3. Capture remote-player tunnel evidence and a six-player stability run.
4. Decide strict-vanilla policy for `bAllowClientMod` and document the resulting
   configuration and evidence.

Each P2 result must record date, runtime versions, data scope, pass criteria, and
recovery path. A successful process start, backup file, or tunnel registration is
not sufficient evidence of acceptance.

P2 readiness delivered in source: `docs/maintenance-window-runbook.md` defines
the per-operation evidence record, `scripts/test-maintenance-readiness.ps1`
performs only read-only preflight checks, and
`scripts/verify-maintenance-evidence.ps1` validates completed local evidence
against the operation-specific acceptance fields. None of these artifacts
constitutes operator approval or substitutes for a maintenance-window result.
