[CmdletBinding()]
param(
    # Strict mode also fails for warnings that need a maintainer's written review.
    [switch]$Strict,
    # Include non-ignored source candidates while preparing a change before it
    # is staged. A release audit on CI uses the default tracked-file scope.
    [switch]$IncludeUntracked
)

# Read-only publication audit. It examines only files tracked by Git and never
# starts a runtime, reads .env, or opens game, backup, log, or save data.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-AuditError([string]$Message) { $errors.Add($Message) }
function Add-AuditWarning([string]$Message) { $warnings.Add($Message) }

$git = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $git) {
    Add-AuditError 'git.exe is required to audit the exact public tracked-file set.'
    $trackedFiles = @()
} else {
    try {
        $trackedFiles = @(& $git.Source -C $projectDir ls-files --cached 2>$null | Where-Object { $_ })
        if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }
        if ($IncludeUntracked) {
            $untracked = @(& $git.Source -C $projectDir ls-files --others --exclude-standard 2>$null | Where-Object { $_ })
            if ($LASTEXITCODE -ne 0) { throw 'git ls-files --others failed.' }
            $trackedFiles = @($trackedFiles + $untracked | Sort-Object -Unique)
        }
    } catch {
        Add-AuditError "Could not enumerate tracked files: $($_.Exception.Message)"
        $trackedFiles = @()
    }
}

foreach ($required in @(
    'LICENSE', 'package.json', 'package-lock.json', 'README.md', 'README.en.md', 'CONTRIBUTING.md', 'SECURITY.md', 'CHANGELOG.md',
    'desktop/PalworldConsole.Desktop/PalworldConsole.Desktop.csproj', 'desktop/PalworldConsole.Desktop/Program.cs', 'desktop/PalworldConsole.Desktop/packages.lock.json', 'installer/PalworldServerConsole.wxs', 'docs/desktop-app.md',
    'docs/public-release-readiness.md', '.github/PULL_REQUEST_TEMPLATE.md',
    '.github/ISSUE_TEMPLATE/bug_report.md', '.github/ISSUE_TEMPLATE/feature_request.md'
)) {
    if ($trackedFiles -notcontains $required) {
        Add-AuditError "Public-release file is missing from Git: $required"
    }
}

foreach ($path in $trackedFiles) {
    $normalized = $path.Replace('\', '/')
    if ($normalized -match '^(?:data|backups|output|steamcmd|win-server)/' -or
        $normalized -match '(^|/)\.env$' -or
        $normalized -match '(^|/)\.(?:settings-panel|daily-log-collector)\.(?:pid|port)$' -or
        $normalized -match '\.(?:log|tmp)$') {
        Add-AuditError "Machine-local or sensitive path is tracked: $path"
    }
}

$textExtensions = @('.md', '.ps1', '.bat', '.cjs', '.js', '.json', '.yml', '.yaml', '.txt', '.example', '.wxs', '')
foreach ($path in $trackedFiles) {
    $extension = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($extension -notin $textExtensions) { continue }
    $fullPath = Join-Path $projectDir $path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        if ($IncludeUntracked) {
            Add-AuditWarning "Tracked deletion is pending a commit and was excluded from the candidate source: $path"
        } else {
            Add-AuditError "Tracked file is unavailable in the working tree: $path"
        }
        continue
    }
    try {
        $text = [System.IO.File]::ReadAllText($fullPath)
    } catch {
        Add-AuditError "Could not inspect tracked file ${path}: $($_.Exception.Message)"
        continue
    }

    if ($path -ne 'scripts/audit-public-release.ps1' -and ($text -match '(?i)\bfrp-way\.com\b' -or
        $text -match '(?i)\b[a-z0-9-]*[a-z][a-z0-9-]*(?:\.[a-z0-9-]+)+:\d{2,5}\b')) {
        Add-AuditError "Possible deployment-specific endpoint appears in public source: $path"
    }
    if ($text -match '(?i)C:\\Users\\Administrator\\') {
        Add-AuditWarning "User-profile path should be generalized before a public release: $path"
    }

    if ($path -match '(^|/)\.env(?:\.example)?$') {
        $lineNumber = 0
        foreach ($line in $text -split "`r?`n") {
            $lineNumber++
            if ($line -notmatch '^\s*(ADMIN_PASSWORD|SERVER_PASSWORD|PANEL_ADMIN_PASSWORD|DISCORD_WEBHOOK_URL)\s*=\s*(.*?)\s*$') { continue }
            $value = $matches[2].Trim().Trim('"').Trim("'")
            if (-not $value -or $value -match '^(?i:CHANGE_ME|REPLACE_ME|YOUR_|EXAMPLE|ci-only-|onboarding-|<.*>)') { continue }
            Add-AuditError "Possible real secret assignment in ${path}:$lineNumber"
        }
    }
}

$panelPath = Join-Path $projectDir 'settings-panel.ps1'
if (Test-Path -LiteralPath $panelPath -PathType Leaf) {
    $panelText = [System.IO.File]::ReadAllText($panelPath)
    if ($panelText -match 'http://\+:' -or $panelText -match 'remotePanelOrigin|PANEL_ADMIN_PASSWORD') {
        Add-AuditError 'Web Console source contains a wildcard listener or remote-management path.'
    }
    foreach ($prefix in @('http://localhost:', 'http://127.0.0.1:', 'http://[::1]:')) {
        if ($panelText -notmatch [regex]::Escape($prefix)) {
            Add-AuditError "Web Console loopback prefix is absent: $prefix"
        }
    }
}

foreach ($message in $warnings) { Write-Warning $message }
foreach ($message in $errors) { Write-Error $message }
Write-Output "PUBLIC_RELEASE_AUDIT_WARNINGS=$($warnings.Count)"
Write-Output "PUBLIC_RELEASE_AUDIT_ERRORS=$($errors.Count)"
Write-Output "PUBLIC_RELEASE_AUDIT_SCOPE=$(if ($IncludeUntracked) { 'tracked-plus-untracked' } else { 'tracked' })"

if ($errors.Count -gt 0 -or ($Strict -and $warnings.Count -gt 0)) { exit 1 }
