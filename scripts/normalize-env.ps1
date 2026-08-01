[CmdletBinding()]
param(
    [string]$Path
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
if (-not $Path) { $Path = Join-Path $projectDir ".env" }

function Read-DotEnv([string]$FilePath) {
    $values = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($FilePath)) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        $index = $line.IndexOf("=")
        if ($index -le 0) { continue }
        $key = $line.Substring(0, $index).Trim()
        $value = $line.Substring($index + 1).Trim()
        if ($value.Length -ge 2) {
            if (($value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') -or
                ($value[0] -eq "'" -and $value[$value.Length - 1] -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }
        $values[$key] = $value
    }
    return $values
}

function Format-DotEnvValue([string]$Value) {
    if ($null -eq $Value) { return "" }
    if ($Value -match "[`r`n`0]") { throw "A dotenv value contains a control character." }
    if ($Value -match "[\s#`"']" -or $Value.Contains('$')) {
        # Compose treats single-quoted dotenv values literally.
        return "'" + $Value.Replace("'", "\'") + "'"
    }
    return $Value
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw ".env not found: $Path"
}

$values = Read-DotEnv $Path

# Legacy Web Console keys used a non-existent SERVER_SETTINGS_ prefix.
$legacyMap = @{
    "MAX_PLAYERS" = "PLAYERS"
    "SERVER_SETTINGS_EXP_RATE" = "EXP_RATE"
    "SERVER_SETTINGS_PAL_CAPTURE_RATE" = "PAL_CAPTURE_RATE"
    "SERVER_SETTINGS_PAL_SPAWN_NUM_RATE" = "PAL_SPAWN_NUM_RATE"
    "SERVER_SETTINGS_WORK_SPEED_RATE" = "WORK_SPEED_RATE"
    "SERVER_SETTINGS_COLLECTION_DROP_RATE" = "COLLECTION_DROP_RATE"
    "SERVER_SETTINGS_ENEMY_DROP_ITEM_RATE" = "ENEMY_DROP_ITEM_RATE"
    "SERVER_SETTINGS_DAY_TIME_SPEED_RATE" = "DAYTIME_SPEEDRATE"
    "SERVER_SETTINGS_NIGHT_TIME_SPEED_RATE" = "NIGHTTIME_SPEEDRATE"
    "SERVER_SETTINGS_PAL_EGG_DEFAULT_HATCHING_TIME" = "PAL_EGG_DEFAULT_HATCHING_TIME"
    "SERVER_SETTINGS_AUTO_SAVE_SPAN" = "AUTO_SAVE_SPAN"
    "SERVER_SETTINGS_SUPPLY_DROP_SPAN" = "SUPPLY_DROP_SPAN"
    "SERVER_SETTINGS_PLAYER_DAMAGE_RATE_ATTACK" = "PLAYER_DAMAGE_RATE_ATTACK"
    "SERVER_SETTINGS_PLAYER_DAMAGE_RATE_DEFENSE" = "PLAYER_DAMAGE_RATE_DEFENSE"
    "SERVER_SETTINGS_PAL_DAMAGE_RATE_ATTACK" = "PAL_DAMAGE_RATE_ATTACK"
    "SERVER_SETTINGS_PAL_DAMAGE_RATE_DEFENSE" = "PAL_DAMAGE_RATE_DEFENSE"
    "SERVER_SETTINGS_DEATH_PENALTY" = "DEATH_PENALTY"
    "SERVER_SETTINGS_B_ENABLE_PLAYER_TO_PLAYER_DAMAGE" = "ENABLE_PLAYER_TO_PLAYER_DAMAGE"
    "SERVER_SETTINGS_B_ENABLE_FRIENDLY_FIRE" = "ENABLE_FRIENDLY_FIRE"
    "SERVER_SETTINGS_B_IS_PVP" = "IS_PVP"
    "SERVER_SETTINGS_B_ENABLE_INVADER_ENEMY" = "ENABLE_INVADER_ENEMY"
    "SERVER_SETTINGS_PLAYER_STOMACH_DECREACE_RATE" = "PLAYER_STOMACH_DECREASE_RATE"
    "SERVER_SETTINGS_PLAYER_STAMINA_DECREACE_RATE" = "PLAYER_STAMINA_DECREASE_RATE"
    "SERVER_SETTINGS_PLAYER_AUTO_HP_REGENE_RATE" = "PLAYER_AUTO_HP_REGEN_RATE"
    "SERVER_SETTINGS_PLAYER_AUTO_HP_REGENE_RATE_IN_SLEEP" = "PLAYER_AUTO_HP_REGEN_RATE_IN_SLEEP"
    "SERVER_SETTINGS_PAL_STOMACH_DECREACE_RATE" = "PAL_STOMACH_DECREASE_RATE"
    "SERVER_SETTINGS_PAL_STAMINA_DECREACE_RATE" = "PAL_STAMINA_DECREASE_RATE"
    "SERVER_SETTINGS_PAL_AUTO_HP_REGENE_RATE" = "PAL_AUTO_HP_REGEN_RATE"
    "SERVER_SETTINGS_PAL_AUTO_HP_REGENE_RATE_IN_SLEEP" = "PAL_AUTO_HP_REGEN_RATE_IN_SLEEP"
    "SERVER_SETTINGS_BUILD_OBJECT_HP_RATE" = "BUILD_OBJECT_HP_RATE"
    "SERVER_SETTINGS_BUILD_OBJECT_DAMAGE_RATE" = "BUILD_OBJECT_DAMAGE_RATE"
    "SERVER_SETTINGS_BUILD_OBJECT_DETERIORATION_DAMAGE_RATE" = "BUILD_OBJECT_DETERIORATION_DAMAGE_RATE"
    "SERVER_SETTINGS_BASE_CAMP_MAX_NUM" = "BASE_CAMP_MAX_NUM"
    "SERVER_SETTINGS_BASE_CAMP_WORKER_MAX_NUM" = "BASE_CAMP_WORKER_MAX_NUM"
    "SERVER_SETTINGS_DROP_ITEM_MAX_NUM" = "DROP_ITEM_MAX_NUM"
    "SERVER_SETTINGS_GUILD_PLAYER_MAX_NUM" = "GUILD_PLAYER_MAX_NUM"
    "SERVER_SETTINGS_B_ENABLE_FAST_TRAVEL" = "ENABLE_FAST_TRAVEL"
    "SERVER_SETTINGS_B_SHOW_PLAYER_LIST" = "SHOW_PLAYER_LIST"
}

$migrated = 0
foreach ($legacyKey in $legacyMap.Keys) {
    if ($values.ContainsKey($legacyKey)) {
        $newKey = $legacyMap[$legacyKey]
        if (-not $values.ContainsKey($newKey)) {
            $values[$newKey] = $values[$legacyKey]
        }
        $values.Remove($legacyKey)
        $migrated++
    }
}

# Correct unsupported/deprecated keys from the original deployment.
$values.Remove("RCON_PASSWORD")
$values.Remove("BACKUP_RETENTION_DAYS")
$values.Remove("ALLOW_CONNECT_PLATFORM")
$values.Remove("PAL_EGG_DEFAULT_RANDOM_HEALTH_NUM")

# Project decisions. These values are intentionally authoritative.
$required = @{
    "TZ" = "Asia/Shanghai"
    "PORT" = "8211"
    "PLAYERS" = "8"
    "COMMUNITY" = "false"
    "UPDATE_ON_BOOT" = "true"
    "REST_API_ENABLED" = "true"
    "REST_API_PORT" = "8212"
    "RCON_ENABLED" = "true"
    "RCON_PORT" = "25575"
    "QUERY_PORT" = "27015"
    "CROSSPLAY_PLATFORMS" = "(Steam,Xbox,PS5,Mac)"
    "BACKUP_ENABLED" = "true"
    "BACKUP_CRON_EXPRESSION" = "0 4 * * *"
    "DELETE_OLD_BACKUPS" = "true"
    "OLD_BACKUP_DAYS" = "5"
    "USE_BACKUP_SAVE_DATA" = "true"
    "ENABLE_PLAYER_LOGGING" = "true"
    "PLAYER_LOGGING_POLL_PERIOD" = "10"
    "LOG_FILTER_ENABLED" = "true"
    "LOG_LEVEL" = "INFO"
    "LOG_FORMAT_TYPE" = "default"
    "COOP_PLAYER_MAX_NUM" = "8"
    "DAYTIME_SPEEDRATE" = "0.5"
    "NIGHTTIME_SPEEDRATE" = "1.0"
    "EXP_RATE" = "2.0"
    "DEATH_PENALTY" = "None"
}
foreach ($key in $required.Keys) { $values[$key] = $required[$key] }

if (-not $values.ContainsKey("ADMIN_PASSWORD") -or $values["ADMIN_PASSWORD"].Length -lt 16) {
    throw "ADMIN_PASSWORD is missing or shorter than 16 characters; refusing to rewrite .env."
}
if (-not $values.ContainsKey("SERVER_PASSWORD")) { $values["SERVER_PASSWORD"] = "" }
if (-not $values.ContainsKey("SERVER_NAME")) { $values["SERVER_NAME"] = "Palworld-Docker" }
if (-not $values.ContainsKey("SERVER_DESCRIPTION")) { $values["SERVER_DESCRIPTION"] = "Private Server" }

$sections = @(
    @{
        Title = "Runtime"
        Keys = @(
            "TZ", "PORT", "PLAYERS", "COMMUNITY", "PUBLIC_IP", "PUBLIC_PORT",
            "SERVER_NAME", "SERVER_DESCRIPTION", "ADMIN_PASSWORD", "SERVER_PASSWORD",
            "UPDATE_ON_BOOT", "REST_API_ENABLED", "REST_API_PORT", "RCON_ENABLED",
            "RCON_PORT", "QUERY_PORT", "CROSSPLAY_PLATFORMS"
        )
    },
    @{
        Title = "Backups"
        Keys = @(
            "BACKUP_ENABLED", "BACKUP_CRON_EXPRESSION", "DELETE_OLD_BACKUPS",
            "OLD_BACKUP_DAYS", "USE_BACKUP_SAVE_DATA"
        )
    },
    @{
        Title = "Logging"
        Keys = @(
            "ENABLE_PLAYER_LOGGING", "PLAYER_LOGGING_POLL_PERIOD",
            "LOG_FILTER_ENABLED", "LOG_LEVEL", "LOG_FORMAT_TYPE"
        )
    },
    @{
        Title = "Game settings"
        Keys = @(
            "COOP_PLAYER_MAX_NUM", "DAYTIME_SPEEDRATE", "NIGHTTIME_SPEEDRATE",
            "EXP_RATE", "PAL_CAPTURE_RATE", "PAL_SPAWN_NUM_RATE", "PAL_DAMAGE_RATE_ATTACK",
            "PAL_DAMAGE_RATE_DEFENSE", "PLAYER_DAMAGE_RATE_ATTACK", "PLAYER_DAMAGE_RATE_DEFENSE",
            "PLAYER_STOMACH_DECREASE_RATE", "PLAYER_STAMINA_DECREASE_RATE",
            "PLAYER_AUTO_HP_REGEN_RATE", "PLAYER_AUTO_HP_REGEN_RATE_IN_SLEEP",
            "PAL_STOMACH_DECREASE_RATE", "PAL_STAMINA_DECREASE_RATE",
            "PAL_AUTO_HP_REGEN_RATE", "PAL_AUTO_HP_REGEN_RATE_IN_SLEEP",
            "BUILD_OBJECT_HP_RATE", "BUILD_OBJECT_DAMAGE_RATE",
            "BUILD_OBJECT_DETERIORATION_DAMAGE_RATE", "COLLECTION_DROP_RATE",
            "ENEMY_DROP_ITEM_RATE", "DEATH_PENALTY", "ENABLE_PLAYER_TO_PLAYER_DAMAGE",
            "ENABLE_FRIENDLY_FIRE", "IS_PVP", "ENABLE_INVADER_ENEMY",
            "DROP_ITEM_MAX_NUM", "BASE_CAMP_MAX_NUM", "BASE_CAMP_WORKER_MAX_NUM",
            "GUILD_PLAYER_MAX_NUM", "PAL_EGG_DEFAULT_HATCHING_TIME", "WORK_SPEED_RATE",
            "AUTO_SAVE_SPAN", "SUPPLY_DROP_SPAN", "ENABLE_FAST_TRAVEL", "SHOW_PLAYER_LIST"
        )
    }
)

$writtenKeys = @{}
$output = New-Object System.Collections.Generic.List[string]
foreach ($section in $sections) {
    $output.Add("# === $($section.Title) ===")
    foreach ($key in $section.Keys) {
        if ($values.ContainsKey($key)) {
            $output.Add("$key=$(Format-DotEnvValue ([string]$values[$key]))")
            $writtenKeys[$key] = $true
        }
    }
    $output.Add("")
}

$ignoredKeys = @("RCON_PASSWORD", "BACKUP_RETENTION_DAYS", "ALLOW_CONNECT_PLATFORM", "PAL_EGG_DEFAULT_RANDOM_HEALTH_NUM")
$remaining = @($values.Keys | Where-Object {
    -not $writtenKeys.ContainsKey($_) -and $_ -notin $ignoredKeys
} | Sort-Object)
if ($remaining.Count -gt 0) {
    $output.Add("# === Additional image settings ===")
    foreach ($key in $remaining) {
        $output.Add("$key=$(Format-DotEnvValue ([string]$values[$key]))")
    }
    $output.Add("")
}

$fullPath = [System.IO.Path]::GetFullPath($Path)
$tempPath = "$fullPath.tmp.$PID"
$rollbackPath = "$fullPath.rollback.$PID"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try {
    [System.IO.File]::WriteAllLines($tempPath, $output.ToArray(), $utf8NoBom)
    [System.IO.File]::Replace($tempPath, $fullPath, $rollbackPath)
} finally {
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Force
    }
    if (Test-Path -LiteralPath $rollbackPath) {
        Remove-Item -LiteralPath $rollbackPath -Force
    }
}

Write-Host "[OK] Normalized .env without creating a secret-bearing backup."
Write-Host "[OK] Migrated $migrated legacy setting keys; wrote $($values.Count) keys."
