[CmdletBinding()]
param(
    [ValidateSet("Status", "Validate", "Hash", "Check", "Sync", "Enable", "Disable")]
    [string]$Action = "Status",
    [string]$ModId,
    [string]$ManifestPath,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
if (-not $ManifestPath) { $ManifestPath = Join-Path $projectDir "mods\manifest.json" }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Resolve-ConfiguredPath([string]$PathValue) {
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $projectDir $PathValue))
}

function Assert-PathInside([string]$Candidate, [string]$Root, [string]$Label) {
    $fullCandidate = [System.IO.Path]::GetFullPath($Candidate)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd("\", "/")
    $rootPrefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullCandidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label escapes its allowed root."
    }
    return $fullCandidate
}

function Write-AtomicText([string]$Path, [string]$Text) {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $parent)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    $tempPath = "$fullPath.tmp.$PID"
    $rollbackPath = "$fullPath.rollback.$PID"
    try {
        [System.IO.File]::WriteAllText($tempPath, $Text, $utf8NoBom)
        if (Test-Path -LiteralPath $fullPath) {
            [System.IO.File]::Replace($tempPath, $fullPath, $rollbackPath)
        } else {
            Move-Item -LiteralPath $tempPath -Destination $fullPath
        }
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
        if (Test-Path -LiteralPath $rollbackPath) { Remove-Item -LiteralPath $rollbackPath -Force }
    }
}

function Read-Manifest() {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Mod manifest not found: $ManifestPath"
    }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1) { throw "Unsupported Mod manifest schema version." }
    if ($manifest.runtime -notin @("linux-docker", "windows-dedicated")) {
        throw "Unsupported Mod runtime: $($manifest.runtime)"
    }
    if ($null -eq $manifest.mods) { throw "Manifest mods must be an array." }
    return $manifest
}

function Get-DirectorySha256([string]$Directory) {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        throw "Directory not found: $Directory"
    }
    $rootItem = Get-Item -LiteralPath $Directory -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Directory root is a reparse point and is not trusted: $Directory"
    }
    $reparsePoints = @(Get-ChildItem -LiteralPath $Directory -Recurse -Force |
        Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 })
    if ($reparsePoints.Count -gt 0) {
        throw "Directory contains a reparse point and is not trusted: $($reparsePoints[0].FullName)"
    }

    $root = [System.IO.Path]::GetFullPath($Directory).TrimEnd("\", "/")
    $lines = New-Object System.Collections.Generic.List[string]
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -Force -File | Sort-Object FullName)
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($root.Length + 1).Replace("\", "/")
        $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $lines.Add("$relative`t$fileHash")
    }
    $canonical = [string]::Join("`n", $lines.ToArray())
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Test-HasServerInstallRule($Value) {
    if ($null -eq $Value) { return $false }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $false }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) {
            if (Test-HasServerInstallRule $item) { return $true }
        }
        return $false
    }
    foreach ($property in $Value.PSObject.Properties) {
        if ($property.Name -eq "IsServer" -and ([string]$property.Value -match "^(?i:true)$")) {
            return $true
        }
        if (Test-HasServerInstallRule $property.Value) { return $true }
    }
    return $false
}

function Get-ModInspection($manifest, $mod) {
    if ([string]$mod.workshopId -notmatch "^[0-9]+$") {
        throw "Invalid Workshop ID: $($mod.workshopId)"
    }
    if ([string]$mod.packageName -notmatch "^[A-Za-z0-9_.-]+$") {
        throw "Invalid packageName for Workshop $($mod.workshopId)."
    }
    if ([string]$mod.sourceFolder -notmatch "^[A-Za-z0-9_.-]+$") {
        throw "Invalid sourceFolder for Workshop $($mod.workshopId)."
    }
    $expectedSha256 = [string]$mod.expectedSha256
    if ($expectedSha256 -and $expectedSha256 -notmatch "^[A-Fa-f0-9]{64}$") {
        throw "Workshop $($mod.workshopId) expectedSha256 must be empty or contain 64 hexadecimal characters."
    }
    if ($mod.updatePolicy -ne "manual") {
        throw "Only manual, hash-approved updates are supported."
    }

    $sourceRoot = Resolve-ConfiguredPath ([string]$manifest.sourceRoot)
    $sourcePath = Assert-PathInside (Join-Path $sourceRoot ([string]$mod.sourceFolder)) $sourceRoot "sourceFolder"
    $workshopRoot = Resolve-ConfiguredPath ([string]$manifest.workshopRoot)
    $targetPath = Assert-PathInside (Join-Path $workshopRoot ([string]$mod.workshopId)) $workshopRoot "Workshop target"
    $sourceExists = Test-Path -LiteralPath $sourcePath -PathType Container
    $targetExists = Test-Path -LiteralPath $targetPath -PathType Container
    $sourceHash = $null
    $targetHash = $null
    $sourceVersion = $null
    $serverCompatible = $false
    $infoPackageName = $null
    $errorMessage = $null

    if ($sourceExists) {
        try {
            $infoPath = Join-Path $sourcePath "Info.json"
            if (-not (Test-Path -LiteralPath $infoPath -PathType Leaf)) {
                throw "Info.json is not directly under the Workshop source folder."
            }
            $info = Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $infoPackageName = [string]$info.PackageName
            $sourceVersion = [string]$info.Version
            if ($infoPackageName -ne [string]$mod.packageName) {
                throw "Info.json PackageName does not match manifest packageName."
            }
            $serverCompatible = Test-HasServerInstallRule $info
            if (-not $serverCompatible) {
                throw "Info.json does not contain an InstallRule with IsServer=true."
            }
            $sourceHash = Get-DirectorySha256 $sourcePath
            if ($targetExists) { $targetHash = Get-DirectorySha256 $targetPath }
        } catch {
            $errorMessage = $_.Exception.Message
        }
    }

    $hashApproved = $false
    if ($sourceHash -and $expectedSha256) {
        $hashApproved = $sourceHash -eq $expectedSha256.ToLowerInvariant()
    }
    if ([bool]$mod.enabled -and -not $sourceExists) {
        $errorMessage = "Workshop source directory is missing."
    } elseif ([bool]$mod.enabled -and -not $errorMessage -and -not $hashApproved) {
        $errorMessage = "Workshop source hash has not been approved."
    }
    $updateAvailable = $false
    if ($sourceHash -and $targetHash) { $updateAvailable = $sourceHash -ne $targetHash }

    return [ordered]@{
        workshopId = [string]$mod.workshopId
        displayName = [string]$mod.displayName
        packageName = [string]$mod.packageName
        enabled = [bool]$mod.enabled
        updatePolicy = [string]$mod.updatePolicy
        sourceExists = $sourceExists
        installed = $targetExists
        sourceVersion = $sourceVersion
        sourceSha256 = $sourceHash
        installedSha256 = $targetHash
        hashApproved = $hashApproved
        serverCompatible = $serverCompatible
        updateAvailable = $updateAvailable
        error = $errorMessage
    }
}

function Get-ManagerReport($manifest) {
    $runtimeSupported = $manifest.runtime -eq "windows-dedicated"
    $reason = ""
    if (-not [bool]$manifest.managerEnabled) {
        $reason = "Mod manager is disabled by manifest."
    } elseif (-not $runtimeSupported) {
        $reason = "Palworld 1.0 server-side Mods currently require the Windows dedicated server."
    }

    $mods = @()
    $ids = @{}
    $packages = @{}
    foreach ($mod in @($manifest.mods)) {
        $id = [string]$mod.workshopId
        $package = [string]$mod.packageName
        if ($ids.ContainsKey($id)) { throw "Duplicate Workshop ID in manifest: $id" }
        if ($packages.ContainsKey($package)) { throw "Duplicate PackageName in manifest: $package" }
        $ids[$id] = $true
        $packages[$package] = $true
        $mods += Get-ModInspection $manifest $mod
    }

    $enabledCount = @($mods | Where-Object { $_.enabled }).Count
    $installedCount = @($mods | Where-Object { $_.installed }).Count
    $updateCount = @($mods | Where-Object { $_.updateAvailable }).Count
    $errorCount = @($mods | Where-Object { $_.error }).Count

    return [ordered]@{
        ok = $true
        schemaVersion = [int]$manifest.schemaVersion
        managerEnabled = [bool]$manifest.managerEnabled
        runtime = [string]$manifest.runtime
        runtimeSupported = $runtimeSupported
        operational = ([bool]$manifest.managerEnabled -and $runtimeSupported)
        reason = $reason
        totalMods = $mods.Count
        enabledMods = $enabledCount
        installedMods = $installedCount
        updatesAvailable = $updateCount
        validationErrors = $errorCount
        sourceRootExists = Test-Path -LiteralPath (Resolve-ConfiguredPath ([string]$manifest.sourceRoot)) -PathType Container
        mods = $mods
        changed = $false
        restartRequired = $false
    }
}

function Set-ModEnabled($manifest, [string]$WorkshopId, [bool]$Enabled) {
    if (-not $WorkshopId) { throw "-ModId is required." }
    $matches = @($manifest.mods | Where-Object { [string]$_.workshopId -eq $WorkshopId })
    if ($matches.Count -ne 1) { throw "Workshop ID not found in manifest: $WorkshopId" }
    $matches[0].enabled = $Enabled
    $jsonText = $manifest | ConvertTo-Json -Depth 20
    Write-AtomicText $ManifestPath ($jsonText + "`r`n")
    $report = Get-ManagerReport (Read-Manifest)
    $report.changed = $true
    return $report
}

function Invoke-Sync($manifest) {
    $report = Get-ManagerReport $manifest
    if (-not $report.managerEnabled) { throw "Mod manager is disabled; no files were changed." }
    if (-not $report.runtimeSupported) {
        throw "Current runtime is linux-docker. Official Palworld 1.0 server Mods require windows-dedicated."
    }
    if ($report.validationErrors -gt 0) { throw "Manifest/source validation failed; no files were changed." }

    $enabled = @($report.mods | Where-Object { $_.enabled })
    foreach ($item in $enabled) {
        if (-not $item.sourceExists) { throw "Workshop $($item.workshopId) source is missing." }
        if (-not $item.hashApproved) { throw "Workshop $($item.workshopId) source hash is not approved." }
        if (-not $item.serverCompatible) { throw "Workshop $($item.workshopId) is not server-compatible." }
    }

    $activeIds = @{}
    foreach ($item in $enabled) { $activeIds[$item.workshopId] = $true }
    foreach ($mod in @($manifest.mods | Where-Object { $_.enabled })) {
        foreach ($dependency in @($mod.dependencies)) {
            if (-not $activeIds.ContainsKey([string]$dependency)) {
                throw "Workshop $($mod.workshopId) has an inactive dependency: $dependency"
            }
        }
    }

    $workshopRoot = Resolve-ConfiguredPath ([string]$manifest.workshopRoot)
    $settingsPath = Resolve-ConfiguredPath ([string]$manifest.settingsPath)
    $statePath = Resolve-ConfiguredPath ([string]$manifest.statePath)
    $backupRoot = Resolve-ConfiguredPath ([string]$manifest.backupRoot)
    [void](Assert-PathInside $workshopRoot $projectDir "workshopRoot")
    [void](Assert-PathInside $settingsPath $projectDir "settingsPath")
    [void](Assert-PathInside $statePath $projectDir "statePath")
    [void](Assert-PathInside $backupRoot $projectDir "backupRoot")
    [void](New-Item -ItemType Directory -Path $workshopRoot -Force)
    [void](New-Item -ItemType Directory -Path $backupRoot -Force)

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $backupRoot $stamp
    [void](New-Item -ItemType Directory -Path $backupPath -Force)

    $sourceRoot = Resolve-ConfiguredPath ([string]$manifest.sourceRoot)
    $stagingSession = Join-Path (Resolve-ConfiguredPath "data\mod-manager\staging") "$stamp-$PID"
    [void](New-Item -ItemType Directory -Path $stagingSession -Force)
    try {
        # Stage and re-hash every enabled Mod before replacing any installed content.
        foreach ($item in $enabled) {
            $mod = @($manifest.mods | Where-Object { [string]$_.workshopId -eq $item.workshopId })[0]
            $source = Assert-PathInside (Join-Path $sourceRoot ([string]$mod.sourceFolder)) $sourceRoot "sourceFolder"
            $stagingPath = Join-Path $stagingSession $item.workshopId
            [void](New-Item -ItemType Directory -Path $stagingPath -Force)
            foreach ($sourceItem in @(Get-ChildItem -LiteralPath $source -Force)) {
                Copy-Item -LiteralPath $sourceItem.FullName -Destination $stagingPath -Recurse -Force
            }
            $stagedHash = Get-DirectorySha256 $stagingPath
            if ($stagedHash -ne $item.sourceSha256) {
                throw "Workshop $($item.workshopId) changed while it was being staged; no installed content was replaced."
            }
        }

        foreach ($item in $enabled) {
            $target = Assert-PathInside (Join-Path $workshopRoot $item.workshopId) $workshopRoot "Workshop target"
            if (Test-Path -LiteralPath $target) {
                Move-Item -LiteralPath $target -Destination (Join-Path $backupPath $item.workshopId)
            }
            Move-Item -LiteralPath (Join-Path $stagingSession $item.workshopId) -Destination $target
        }
    } finally {
        if (Test-Path -LiteralPath $stagingSession) {
            Remove-Item -LiteralPath $stagingSession -Recurse -Force
        }
    }

    if (Test-Path -LiteralPath $settingsPath) {
        Copy-Item -LiteralPath $settingsPath -Destination (Join-Path $backupPath "PalModSettings.ini") -Force
    }
    $settingsLines = New-Object System.Collections.Generic.List[string]
    $settingsLines.Add("[PalModSettings]")
    $settingsLines.Add("bGlobalEnableMod=$($enabled.Count -gt 0)")
    foreach ($item in $enabled) { $settingsLines.Add("ActiveModList=$($item.packageName)") }
    Write-AtomicText $settingsPath ([string]::Join("`r`n", $settingsLines.ToArray()) + "`r`n")

    $state = [ordered]@{
        schemaVersion = 1
        syncedAt = (Get-Date).ToString("o")
        activeMods = @($enabled | ForEach-Object {
            [ordered]@{
                workshopId = $_.workshopId
                packageName = $_.packageName
                version = $_.sourceVersion
                sha256 = $_.sourceSha256
            }
        })
    }
    Write-AtomicText $statePath (($state | ConvertTo-Json -Depth 10) + "`r`n")
    $result = Get-ManagerReport (Read-Manifest)
    $result.changed = $true
    $result.restartRequired = $true
    $result.backupCreated = $backupPath
    return $result
}

try {
    $manifest = Read-Manifest
    switch ($Action) {
        "Status" { $result = Get-ManagerReport $manifest }
        "Validate" {
            $result = Get-ManagerReport $manifest
            if ($result.validationErrors -gt 0) { throw "Mod validation failed." }
        }
        "Check" { $result = Get-ManagerReport $manifest }
        "Hash" {
            if (-not $ModId) { throw "-ModId is required for Hash." }
            $mod = @($manifest.mods | Where-Object { [string]$_.workshopId -eq $ModId })
            if ($mod.Count -ne 1) { throw "Workshop ID not found in manifest: $ModId" }
            $inspection = Get-ModInspection $manifest $mod[0]
            $result = [ordered]@{ ok = $true; action = "Hash"; mod = $inspection }
        }
        "Sync" { $result = Invoke-Sync $manifest }
        "Enable" { $result = Set-ModEnabled $manifest $ModId $true }
        "Disable" { $result = Set-ModEnabled $manifest $ModId $false }
    }
    $result["action"] = $Action
    if ($Json) {
        $result | ConvertTo-Json -Depth 20 -Compress
    } else {
        $result | ConvertTo-Json -Depth 20
    }
    exit 0
} catch {
    $failure = [ordered]@{
        ok = $false
        action = $Action
        error = $_.Exception.Message
        changed = $false
        restartRequired = $false
    }
    if ($Json) {
        $failure | ConvertTo-Json -Depth 10 -Compress
    } else {
        $failure | ConvertTo-Json -Depth 10
    }
    exit 2
}
