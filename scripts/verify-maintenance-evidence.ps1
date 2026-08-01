[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$AllowSynthetic,
    [switch]$AsJson
)

# Validates a completed P2 evidence record. It reads one local JSON file and
# does not contact Docker, REST, RCON, the tunnel, or any game process.
$ErrorActionPreference = 'Stop'
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Error([string]$Message) { $errors.Add($Message) }
function Add-Warning([string]$Message) { $warnings.Add($Message) }
function Has-Value($Value) { return $null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value) }
function Require-Value($Object, [string]$Property, [string]$Label) {
    if ($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Property -or -not (Has-Value $Object.$Property)) {
        Add-Error "$Label is required."
        return $null
    }
    return $Object.$Property
}
function Require-Boolean($Object, [string]$Property, [string]$Label) {
    if ($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Property -or $Object.$Property -isnot [bool]) {
        Add-Error "$Label must be true or false."
        return $null
    }
    return [bool]$Object.$Property
}
function Test-IsoTimestamp($Value, [string]$Label) {
    $parsed = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Value, [ref]$parsed)) {
        Add-Error "$Label must be an ISO-8601 timestamp."
        return $null
    }
    return $parsed
}
function Test-Sha256($Value, [string]$Label) {
    if ([string]$Value -notmatch '^sha256:[0-9a-fA-F]{64}$') {
        Add-Error "$Label must be sha256:<64 hexadecimal characters>."
        return $false
    }
    return $true
}

$resolvedPath = $null
try {
    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $raw = [System.IO.File]::ReadAllText($resolvedPath)
    $record = $raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    Add-Error "Evidence record cannot be read as JSON: $($_.Exception.Message)"
}

if ($record) {
    if ([int]$record.schemaVersion -ne 1) { Add-Error 'schemaVersion must be 1.' }
    $operation = Require-Value $record 'operation' 'operation'
    if ($operation -and $operation -notin @('switch', 'restore', 'tunnel', 'stability', 'vanilla')) {
        Add-Error "operation is unsupported: $operation"
    }
    $performedAt = Require-Value $record 'performedAt' 'performedAt'
    if ($performedAt) { [void](Test-IsoTimestamp $performedAt 'performedAt') }
    $result = Require-Value $record 'result' 'result'
    if ($result -and $result -notin @('pass', 'fail', 'incomplete')) { Add-Error "result is unsupported: $result" }

    $isSynthetic = $false
    if ($record.PSObject.Properties.Name -contains 'synthetic') {
        if ($record.synthetic -isnot [bool]) { Add-Error 'synthetic must be true or false.' }
        else { $isSynthetic = [bool]$record.synthetic }
    }
    if ($isSynthetic -and -not $AllowSynthetic) {
        Add-Error 'Synthetic evidence is accepted only with -AllowSynthetic and cannot prove a P2 result.'
    }

    [void](Require-Value $record 'operatorApproval' 'operatorApproval reference')
    $commit = Require-Value $record 'sourceCommit' 'sourceCommit'
    if ($commit -and [string]$commit -notmatch '^[0-9a-fA-F]{7,64}$') { Add-Error 'sourceCommit must be a Git commit SHA.' }
    $sensitive = Require-Boolean $record 'sensitiveDataIncluded' 'sensitiveDataIncluded'
    if ($sensitive -eq $true) { Add-Error 'Evidence record declares sensitive data; redact it before validation.' }
    if ($raw -match '(?i)(password|webhook|bearer\s+|steamid|playeruid|\b(?:\d{1,3}\.){3}\d{1,3}\b)') {
        Add-Error 'Evidence record appears to include a credential, player identifier, or IP address; redact it.'
    }

    $runtime = $record.runtime
    foreach ($property in @('before', 'after')) {
        $value = Require-Value $runtime $property "runtime.$property"
        if ($value -and $value -notin @('docker', 'windows', 'none')) {
            Add-Error "runtime.$property must be docker, windows, or none."
        }
    }
    $versions = $record.versions
    $image = Require-Value $versions 'containerImageDigest' 'versions.containerImageDigest'
    if ($image) { [void](Test-Sha256 $image 'versions.containerImageDigest') }
    [void](Require-Value $versions 'gameServerBuild' 'versions.gameServerBuild')

    $scope = $record.dataScope
    $scopeKind = Require-Value $scope 'kind' 'dataScope.kind'
    if ($scopeKind -and $scopeKind -notin @('disposable-copy', 'operator-approved-world')) {
        Add-Error 'dataScope.kind must be disposable-copy or operator-approved-world.'
    }
    [void](Require-Value $scope 'description' 'dataScope.description')
    if ($scopeKind -eq 'operator-approved-world') { [void](Require-Value $scope 'approvalReference' 'dataScope.approvalReference') }

    $criteria = @($record.passCriteria)
    if ($criteria.Count -eq 0 -or @($criteria | Where-Object { -not (Has-Value $_) }).Count -gt 0) {
        Add-Error 'passCriteria must contain one or more non-empty criteria.'
    }
    $recovery = $record.recovery
    [void](Require-Value $recovery 'path' 'recovery.path')
    [void](Require-Value $recovery 'outcome' 'recovery.outcome')

    if ($operation -eq 'switch') {
        if ($runtime.before -notin @('docker', 'windows') -or $runtime.after -notin @('docker', 'windows') -or $runtime.before -eq $runtime.after) {
            Add-Error 'A switch record must have different docker/windows runtime before and after values.'
        }
        $save = $record.preSwitchRestSave
        if ((Require-Value $save 'status' 'preSwitchRestSave.status') -ne 'success') { Add-Error 'A passing switch requires preSwitchRestSave.status=success.' }
        $snapshot = $record.preSwitchSnapshot
        [void](Require-Value $snapshot 'name' 'preSwitchSnapshot.name')
        $snapshotHash = Require-Value $snapshot 'sha256' 'preSwitchSnapshot.sha256'
        if ($snapshotHash) { [void](Test-Sha256 $snapshotHash 'preSwitchSnapshot.sha256') }
        if ((Require-Boolean $snapshot 'verified' 'preSwitchSnapshot.verified') -ne $true) { Add-Error 'A passing switch requires preSwitchSnapshot.verified=true.' }
        if ((Require-Value $record.targetRestInfo 'status' 'targetRestInfo.status') -ne 'success') { Add-Error 'A passing switch requires targetRestInfo.status=success.' }
        if ((Require-Value $record.targetSettings 'status' 'targetSettings.status') -ne 'success') { Add-Error 'A passing switch requires targetSettings.status=success.' }
        $saveGames = $record.saveGames
        $beforeFingerprint = Require-Value $saveGames 'beforeFingerprint' 'saveGames.beforeFingerprint'
        $afterFingerprint = Require-Value $saveGames 'afterFingerprint' 'saveGames.afterFingerprint'
        if ($beforeFingerprint -and $afterFingerprint -and $beforeFingerprint -ne $afterFingerprint) {
            $explanation = $null
            if ($saveGames.PSObject.Properties.Name -contains 'fingerprintExplanation') { $explanation = $saveGames.fingerprintExplanation }
            if (Has-Value $explanation) { Add-Warning "saveGames fingerprints differ across the switch: $explanation" }
            else { Add-Error 'saveGames fingerprints differ across the switch. Provide saveGames.fingerprintExplanation or ensure fingerprints match.' }
        }
    } elseif ($operation -eq 'restore') {
        $snapshot = $record.selectedSnapshot
        $hash = Require-Value $snapshot 'sha256' 'selectedSnapshot.sha256'
        if ($hash) { [void](Test-Sha256 $hash 'selectedSnapshot.sha256') }
        if ((Require-Boolean $snapshot 'verified' 'selectedSnapshot.verified') -ne $true) { Add-Error 'A restore record requires selectedSnapshot.verified=true.' }
        $safety = $record.preRestoreSafetySnapshot
        $safetyHash = Require-Value $safety 'sha256' 'preRestoreSafetySnapshot.sha256'
        if ($safetyHash) { [void](Test-Sha256 $safetyHash 'preRestoreSafetySnapshot.sha256') }
        if ((Require-Value $record.postRestoreIntegrity 'status' 'postRestoreIntegrity.status') -ne 'success') { Add-Error 'A passing restore requires postRestoreIntegrity.status=success.' }
    } elseif ($operation -eq 'tunnel') {
        $local = $record.localTunnelChecks
        foreach ($property in @('udpMapping', 'process', 'controlConnection', 'proxyReady')) {
            if ((Require-Boolean $local $property "localTunnelChecks.$property") -ne $true) { Add-Error "A passing tunnel requires localTunnelChecks.$property=true." }
        }
        $external = $record.externalVerification
        $joined = Require-Boolean $external 'remoteJoinObserved' 'externalVerification.remoteJoinObserved'
        $traffic = Require-Boolean $external 'externalDataTrafficObserved' 'externalVerification.externalDataTrafficObserved'
        if ($joined -ne $true -and $traffic -ne $true) { Add-Error 'A passing tunnel requires a remote join or external data-traffic observation.' }
    } elseif ($operation -eq 'stability') {
        $run = $record.stabilityRun
        $players = 0
        if (-not [int]::TryParse([string](Require-Value $run 'concurrentPlayers' 'stabilityRun.concurrentPlayers'), [ref]$players) -or $players -lt 6) {
            Add-Error 'A stability record requires at least 6 concurrent players.'
        }
        $started = Test-IsoTimestamp (Require-Value $run 'startedAt' 'stabilityRun.startedAt') 'stabilityRun.startedAt'
        $ended = Test-IsoTimestamp (Require-Value $run 'endedAt' 'stabilityRun.endedAt') 'stabilityRun.endedAt'
        if ($started -and $ended -and ($ended - $started).TotalMinutes -lt 60) { Add-Error 'A stability record must cover at least 60 minutes.' }
        if ((Require-Boolean $run 'aggregateOnly' 'stabilityRun.aggregateOnly') -ne $true) { Add-Error 'A stability record must be aggregateOnly=true.' }
        if ((Require-Value $run 'healthAtEnd' 'stabilityRun.healthAtEnd') -ne 'success') { Add-Error 'A stability record requires healthAtEnd=success.' }
    } elseif ($operation -eq 'vanilla') {
        $policy = Require-Value $record 'vanillaPolicy' 'vanillaPolicy'
        if ($policy -and $policy -notin @('strict-vanilla', 'bounded-mod-enabled-client')) { Add-Error 'vanillaPolicy is unsupported.' }
        if ((Require-Boolean $record 'serverModsInstalled' 'serverModsInstalled') -ne $false) { Add-Error 'serverModsInstalled must be false while Linux Docker Mods are fail-closed.' }
    }

    if ($result -eq 'pass' -and $errors.Count -gt 0) { Add-Warning 'Record claims pass but has validation errors.' }
    if ($result -ne 'pass') { Add-Warning "Record result is $result and cannot satisfy the corresponding P2 acceptance item." }
}

$summary = [pscustomobject][ordered]@{
    path = $resolvedPath
    valid = ($errors.Count -eq 0)
    errors = @($errors)
    warnings = @($warnings)
}
if ($AsJson) { $summary | ConvertTo-Json -Depth 5 }
else {
    foreach ($warning in $warnings) { Write-Host "[WARN] $warning" -ForegroundColor Yellow }
    foreach ($error in $errors) { Write-Host "[FAIL] $error" -ForegroundColor Red }
    if ($errors.Count -eq 0) { Write-Host '[OK] Maintenance evidence record is structurally valid.' -ForegroundColor Green }
    Write-Host "MAINTENANCE_EVIDENCE_ERRORS=$($errors.Count)"
}
if ($errors.Count -gt 0) { exit 1 }
exit 0
