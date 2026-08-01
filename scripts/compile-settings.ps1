# compile-settings.ps1
#
# Unified INI compiler: generates both LinuxServer and WindowsServer
# PalWorldSettings.ini (and optionally Engine.ini) from .env + settings-catalog.ps1.
#
# The ENV -> INI key mapping is derived from the pinned thijsvanloef image's
# compile-settings.sh behavior. The mapping table below is the authoritative
# source for this project; do not edit individual INI files by hand.
#
# Usage:
#   .\scripts\compile-settings.ps1               # Compile both INIs
#   .\scripts\compile-settings.ps1 -Validate     # Compile + verify drift
#   .\scripts\compile-settings.ps1 -EngineOnly   # Only Engine.ini
#   .\scripts\compile-settings.ps1 -SettingsOnly # Only PalWorldSettings.ini (default)

param(
    [switch]$Validate,
    [switch]$EngineOnly,
    [switch]$SettingsOnly,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectDir '.env'
$catalogPath = Join-Path $projectDir 'scripts\settings-catalog.ps1'
$linuxConfigDir = Join-Path $projectDir 'data\Pal\Saved\Config\LinuxServer'
$windowsConfigDir = Join-Path $projectDir 'win-server\Pal\Saved\Config\WindowsServer'
$diagnosticsDir = Join-Path $projectDir 'data\diagnostics'
$compileLogPath = Join-Path $diagnosticsDir 'ini-compile.log'

# ---------------------------------------------------------------------------
# ENV -> INI key mapping table (118 game fields + PLAYERS->ServerPlayerMaxNum)
# Format: ENV_KEY|IniKey|ValueType
# ValueType: bool, string, int, number, choice, secret, special_parens, special_bare
# ---------------------------------------------------------------------------
$mappingRows = @'
DIFFICULTY|Difficulty|choice
RANDOMIZER_TYPE|RandomizerType|choice
RANDOMIZER_SEED|RandomizerSeed|string
IS_RANDOMIZER_PAL_LEVEL_RANDOM|bIsRandomizerPalLevelRandom|bool
DAYTIME_SPEEDRATE|DayTimeSpeedRate|number
NIGHTTIME_SPEEDRATE|NightTimeSpeedRate|number
EXP_RATE|ExpRate|number
PAL_CAPTURE_RATE|PalCaptureRate|number
PAL_SPAWN_NUM_RATE|PalSpawnNumRate|number
PAL_DAMAGE_RATE_ATTACK|PalDamageRateAttack|number
PAL_DAMAGE_RATE_DEFENSE|PalDamageRateDefense|number
PLAYER_DAMAGE_RATE_ATTACK|PlayerDamageRateAttack|number
PLAYER_DAMAGE_RATE_DEFENSE|PlayerDamageRateDefense|number
PLAYER_STOMACH_DECREASE_RATE|PlayerStomachDecreaceRate|number
PLAYER_STAMINA_DECREASE_RATE|PlayerStaminaDecreaceRate|number
PLAYER_AUTO_HP_REGEN_RATE|PlayerAutoHPRegeneRate|number
PLAYER_AUTO_HP_REGEN_RATE_IN_SLEEP|PlayerAutoHpRegeneRateInSleep|number
PAL_STOMACH_DECREASE_RATE|PalStomachDecreaceRate|number
PAL_STAMINA_DECREASE_RATE|PalStaminaDecreaceRate|number
PAL_AUTO_HP_REGEN_RATE|PalAutoHPRegeneRate|number
PAL_AUTO_HP_REGEN_RATE_IN_SLEEP|PalAutoHpRegeneRateInSleep|number
BUILD_OBJECT_HP_RATE|BuildObjectHpRate|number
BUILD_OBJECT_DAMAGE_RATE|BuildObjectDamageRate|number
BUILD_OBJECT_DETERIORATION_DAMAGE_RATE|BuildObjectDeteriorationDamageRate|number
COLLECTION_DROP_RATE|CollectionDropRate|number
COLLECTION_OBJECT_HP_RATE|CollectionObjectHpRate|number
COLLECTION_OBJECT_RESPAWN_SPEED_RATE|CollectionObjectRespawnSpeedRate|number
ENEMY_DROP_ITEM_RATE|EnemyDropItemRate|number
DEATH_PENALTY|DeathPenalty|choice
ENABLE_PLAYER_TO_PLAYER_DAMAGE|bEnablePlayerToPlayerDamage|bool
ENABLE_FRIENDLY_FIRE|bEnableFriendlyFire|bool
ENABLE_INVADER_ENEMY|bEnableInvaderEnemy|bool
ACTIVE_UNKO|bActiveUNKO|bool
ENABLE_AIM_ASSIST_PAD|bEnableAimAssistPad|bool
ENABLE_AIM_ASSIST_KEYBOARD|bEnableAimAssistKeyboard|bool
DROP_ITEM_MAX_NUM|DropItemMaxNum|int
DROP_ITEM_MAX_NUM_UNKO|DropItemMaxNum_UNKO|int
BASE_CAMP_MAX_NUM|BaseCampMaxNum|int
BASE_CAMP_WORKER_MAX_NUM|BaseCampWorkerMaxNum|int
DROP_ITEM_ALIVE_MAX_HOURS|DropItemAliveMaxHours|number
AUTO_RESET_GUILD_NO_ONLINE_PLAYERS|bAutoResetGuildNoOnlinePlayers|bool
AUTO_RESET_GUILD_TIME_NO_ONLINE_PLAYERS|AutoResetGuildTimeNoOnlinePlayers|number
GUILD_PLAYER_MAX_NUM|GuildPlayerMaxNum|int
BASE_CAMP_MAX_NUM_IN_GUILD|BaseCampMaxNumInGuild|int
PAL_EGG_DEFAULT_HATCHING_TIME|PalEggDefaultHatchingTime|number
WORK_SPEED_RATE|WorkSpeedRate|number
AUTO_SAVE_SPAN|AutoSaveSpan|int
IS_MULTIPLAY|bIsMultiplay|bool
IS_PVP|bIsPvP|bool
HARDCORE|bHardcore|bool
CHARACTER_RECREATE_IN_HARDCORE|bCharacterRecreateInHardcore|bool
PAL_LOST|bPalLost|bool
CAN_PICKUP_OTHER_GUILD_DEATH_PENALTY_DROP|bCanPickupOtherGuildDeathPenaltyDrop|bool
ENABLE_NON_LOGIN_PENALTY|bEnableNonLoginPenalty|bool
ENABLE_FAST_TRAVEL|bEnableFastTravel|bool
IS_START_LOCATION_SELECT_BY_MAP|bIsStartLocationSelectByMap|bool
EXIST_PLAYER_AFTER_LOGOUT|bExistPlayerAfterLogout|bool
ENABLE_DEFENSE_OTHER_GUILD_PLAYER|bEnableDefenseOtherGuildPlayer|bool
INVISIBLE_OTHER_GUILD_BASE_CAMP_AREA_FX|bInvisibleOtherGuildBaseCampAreaFX|bool
BUILD_AREA_LIMIT|bBuildAreaLimit|bool
ITEM_WEIGHT_RATE|ItemWeightRate|number
COOP_PLAYER_MAX_NUM|CoopPlayerMaxNum|int
PLAYERS|ServerPlayerMaxNum|int
SERVER_NAME|ServerName|string
SERVER_DESCRIPTION|ServerDescription|string
ADMIN_PASSWORD|AdminPassword|secret
SERVER_PASSWORD|ServerPassword|secret
PUBLIC_PORT|PublicPort|int
PUBLIC_IP|PublicIP|string
RCON_ENABLED|RCONEnabled|bool
RCON_PORT|RCONPort|int
REGION|Region|string
USEAUTH|bUseAuth|bool
BAN_LIST_URL|BanListURL|string
REST_API_ENABLED|RESTAPIEnabled|bool
REST_API_PORT|RESTAPIPort|int
SHOW_PLAYER_LIST|bShowPlayerList|bool
CHAT_POST_LIMIT_PER_MINUTE|ChatPostLimitPerMinute|int
CROSSPLAY_PLATFORMS|CrossplayPlatforms|special_parens
USE_BACKUP_SAVE_DATA|bIsUseBackupSaveData|bool
SUPPLY_DROP_SPAN|SupplyDropSpan|int
ENABLE_PREDATOR_BOSS_PAL|EnablePredatorBossPal|bool
MAX_BUILDING_LIMIT_NUM|MaxBuildingLimitNum|int
SERVER_REPLICATE_PAWN_CULL_DISTANCE|ServerReplicatePawnCullDistance|number
ALLOW_GLOBAL_PALBOX_EXPORT|bAllowGlobalPalboxExport|bool
ALLOW_GLOBAL_PALBOX_IMPORT|bAllowGlobalPalboxImport|bool
EQUIPMENT_DURABILITY_DAMAGE_RATE|EquipmentDurabilityDamageRate|number
ITEM_CONTAINER_FORCE_MARK_DIRTY_INTERVAL|ItemContainerForceMarkDirtyInterval|number
ITEM_CORRUPTION_MULTIPLIER|ItemCorruptionMultiplier|number
PHYSICS_ACTIVE_DROP_ITEM_MAX_NUM|PhysicsActiveDropItemMaxNum|int
ALLOW_CLIENT_MOD|bAllowClientMod|bool
PLAYER_DATA_PAL_STORAGE_UPDATE_CHECK_TICK_INTERVAL|PlayerDataPalStorageUpdateCheckTickInterval|number
LOG_FORMAT_TYPE|LogFormatType|choice
IS_SHOW_JOIN_LEFT_MESSAGE|bIsShowJoinLeftMessage|bool
MONSTER_FARM_ACTION_SPEED_RATE|MonsterFarmActionSpeedRate|number
DENY_TECHNOLOGY_LIST|DenyTechnologyList|special_bare
GUILD_REJOIN_COOLDOWN_MINUTES|GuildRejoinCooldownMinutes|int
AUTO_TRANSFER_MASTER_CHECK_INTERVAL_SECONDS|AutoTransferMasterCheckIntervalSeconds|number
AUTO_TRANSFER_MASTER_THRESHOLD_DAYS|AutoTransferMasterThresholdDays|int
MAX_GUILDS_PER_FRAME|MaxGuildsPerFrame|int
BLOCK_RESPAWN_TIME|BlockRespawnTime|number
RESPAWN_PENALTY_DURATION_THRESHOLD|RespawnPenaltyDurationThreshold|number
RESPAWN_PENALTY_TIME_SCALE|RespawnPenaltyTimeScale|number
DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_BASE_CAMP|bDisplayPvPItemNumOnWorldMap_BaseCamp|bool
DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_PLAYER|bDisplayPvPItemNumOnWorldMap_Player|bool
ADDITIONAL_DROP_ITEM_WHEN_PLAYER_KILLING_IN_PVP_MODE|AdditionalDropItemWhenPlayerKillingInPvPMode|special_bare
ADDITIONAL_DROP_ITEM_NUM_WHEN_PLAYER_KILLING_IN_PVP_MODE|AdditionalDropItemNumWhenPlayerKillingInPvPMode|int
ADDITIONAL_DROP_ITEM_WHEN_PLAYER_KILLING_IN_PVP_MODE_ENABLED|bAdditionalDropItemWhenPlayerKillingInPvPMode|bool
ENABLE_VOICE_CHAT|bEnableVoiceChat|bool
VOICE_CHAT_MAX_VOLUME_DISTANCE|VoiceChatMaxVolumeDistance|number
VOICE_CHAT_ZERO_VOLUME_DISTANCE|VoiceChatZeroVolumeDistance|number
ALLOW_ENHANCE_STAT_HEALTH|bAllowEnhanceStat_Health|bool
ALLOW_ENHANCE_STAT_ATTACK|bAllowEnhanceStat_Attack|bool
ALLOW_ENHANCE_STAT_STAMINA|bAllowEnhanceStat_Stamina|bool
ALLOW_ENHANCE_STAT_WEIGHT|bAllowEnhanceStat_Weight|bool
ALLOW_ENHANCE_STAT_WORK_SPEED|bAllowEnhanceStat_WorkSpeed|bool
ENABLE_BUILDING_PLAYER_UID_DISPLAY|bEnableBuildingPlayerUIdDisplay|bool
BUILDING_NAME_DISPLAY_CACHE_TTL_SECONDS|BuildingNameDisplayCacheTTLSeconds|int
'@

# Engine.ini field mapping
$engineMappingRows = @'
LAN_SERVER_MAX_TICK_RATE|LanServerMaxTickRate|int
NET_SERVER_MAX_TICK_RATE|NetServerMaxTickRate|int
CONFIGURED_INTERNET_SPEED|ConfiguredInternetSpeed|int
CONFIGURED_LAN_SPEED|ConfiguredLanSpeed|int
MAX_CLIENT_RATE|MaxClientRate|int
MAX_INTERNET_CLIENT_RATE|MaxInternetClientRate|int
SMOOTH_FRAME_RATE|bSmoothFrameRate|bool
SMOOTH_FRAME_RATE_UPPER_LIMIT|SmoothFrameRateUpperLimit|number
SMOOTH_FRAME_RATE_LOWER_LIMIT|SmoothFrameRateLowerLimit|number
USE_FIXED_FRAME_RATE|bUseFixedFrameRate|bool
FIXED_FRAME_RATE|FixedFrameRate|int
MIN_DESIRED_FRAME_RATE|MinDesiredFrameRate|int
NET_CLIENT_TICKS_PER_SECOND|NetClientTicksPerSecond|int
'@

# ---------------------------------------------------------------------------
# Load .env
# ---------------------------------------------------------------------------
function Get-EnvVars {
    $vars = @{}
    if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) {
        throw ".env not found at: $envPath"
    }
    foreach ($line in [System.IO.File]::ReadAllLines($envPath)) {
        if ($line -match '^\s*([^#=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            # Strip surrounding quotes
            if ($value.Length -ge 2 -and
                (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                 ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $vars[$key] = $value
        }
    }
    return $vars
}

# ---------------------------------------------------------------------------
# Load catalog defaults
# ---------------------------------------------------------------------------
function Get-CatalogDefaults {
    . $catalogPath
    $catalog = New-SettingsCatalog
    $defaults = @{}
    foreach ($key in $catalog.Keys) {
        $defaults[$key] = [string]$catalog[$key].default
    }
    return $defaults
}

# ---------------------------------------------------------------------------
# Format value for INI
# ---------------------------------------------------------------------------
function Format-IniValue {
    param([string]$Value, [string]$ValueType)
    switch ($ValueType) {
        'bool' {
            # Normalize to True/False (UE convention)
            if ($Value -match '^(?i:true|1|yes|on)$') { return 'True' }
            if ($Value -match '^(?i:false|0|no|off)$') { return 'False' }
            # Unknown: default to False
            return 'False'
        }
        'string' { return "`"$Value`"" }
        'secret' { return "`"$Value`"" }
        'choice' { return $Value }
        'int'    { return $Value }
        'number' { return $Value }
        'special_parens' {
            # CROSSPLAY_PLATFORMS: value is already (Steam,Xbox,PS5,Mac) or bare list
            $v = $Value.Trim()
            if ($v.StartsWith('(') -and $v.EndsWith(')')) { return $v }
            return "($v)"
        }
        'special_bare' {
            # DENY_TECHNOLOGY_LIST: bare value, no quotes
            return $Value
        }
        default { return $Value }
    }
}

# ---------------------------------------------------------------------------
# Build PalWorldSettings.ini content
# ---------------------------------------------------------------------------
function Build-PalWorldSettings {
    param([hashtable]$EnvVars, [hashtable]$Defaults)

    $entries = New-Object System.Collections.Generic.List[string]
    foreach ($row in ($mappingRows -split "`r?`n")) {
        if (-not $row.Trim()) { continue }
        $parts = $row.Split(@('|'), 3, [System.StringSplitOptions]::None)
        $envKey = $parts[0]
        $iniKey = $parts[1]
        $valueType = $parts[2]

        # Resolve value: .env first, then default
        $rawValue = $null
        if ($EnvVars.ContainsKey($envKey)) { $rawValue = $EnvVars[$envKey] }
        elseif ($Defaults.ContainsKey($envKey)) { $rawValue = $Defaults[$envKey] }
        else { $rawValue = '' }

        $formatted = Format-IniValue -Value $rawValue -ValueType $valueType
        $entries.Add("$iniKey=$formatted")
    }

    $inner = $entries -join ','
    return "[/Script/Pal.PalGameWorldSettings]`nOptionSettings=($inner)"
}

# ---------------------------------------------------------------------------
# Build Engine.ini content
# ---------------------------------------------------------------------------
function Build-EngineIni {
    param([hashtable]$EnvVars, [hashtable]$Defaults)

    # Check if engine generation is enabled
    $disableEngine = $true
    if ($EnvVars.ContainsKey('DISABLE_GENERATE_ENGINE')) {
        $disableEngine = ($EnvVars['DISABLE_GENERATE_ENGINE'] -notmatch '^(?i:false|0|no|off)$')
    } elseif ($Defaults.ContainsKey('DISABLE_GENERATE_ENGINE')) {
        $disableEngine = ($Defaults['DISABLE_GENERATE_ENGINE'] -notmatch '^(?i:false|0|no|off)$')
    }
    if ($disableEngine) { return $null }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('[/Script/EngineSettings.GameNetSpeedSettings]')
    foreach ($row in ($engineMappingRows -split "`r?`n")) {
        if (-not $row.Trim()) { continue }
        $parts = $row.Split(@('|'), 3, [System.StringSplitOptions]::None)
        $envKey = $parts[0]; $iniKey = $parts[1]; $valueType = $parts[2]
        $rawValue = if ($EnvVars.ContainsKey($envKey)) { $EnvVars[$envKey] } elseif ($Defaults.ContainsKey($envKey)) { $Defaults[$envKey] } else { '' }
        $formatted = Format-IniValue -Value $rawValue -ValueType $valueType
        $lines.Add("$iniKey=$formatted")
    }
    return $lines -join "`n"
}

# ---------------------------------------------------------------------------
# Write INI with specific line ending
# ---------------------------------------------------------------------------
function Write-IniFile {
    param([string]$Path, [string]$Content, [string]$LineEnding)
    # Ensure parent dir
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    # Normalize to LF, then convert to target
    $normalized = $Content -replace "`r`n", "`n"
    if ($LineEnding -eq '`r`n') {
        $normalized = $normalized -replace "`n", "`r`n"
    }
    # UTF-8 with BOM (UE expects BOM on Windows; container image also writes BOM)
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $normalized, $utf8Bom)
}

# ---------------------------------------------------------------------------
# Compute SHA-256
# ---------------------------------------------------------------------------
function Get-FileSha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$startTime = Get-Date
if (-not $Quiet) { Write-Host '[compile-settings] Starting INI compilation...' }

# Ensure diagnostics dir
if (-not (Test-Path -LiteralPath $diagnosticsDir -PathType Container)) {
    New-Item -ItemType Directory -Path $diagnosticsDir -Force | Out-Null
}

$envVars = Get-EnvVars
$defaults = Get-CatalogDefaults

$fieldCount = 0
$writtenFiles = @()
$validationErrors = @()

if (-not $EngineOnly) {
    $settingsContent = Build-PalWorldSettings -EnvVars $envVars -Defaults $defaults
    $fieldCount = ($settingsContent -split ',').Count

    $linuxPath = Join-Path $linuxConfigDir 'PalWorldSettings.ini'
    $windowsPath = Join-Path $windowsConfigDir 'PalWorldSettings.ini'

    Write-IniFile -Path $linuxPath -Content $settingsContent -LineEnding "`n"
    Write-IniFile -Path $windowsPath -Content $settingsContent -LineEnding "`r`n"
    $writtenFiles += $linuxPath, $windowsPath

    if (-not $Quiet) {
        Write-Host "[compile-settings] PalWorldSettings.ini: $fieldCount fields"
        Write-Host "  -> $linuxPath (LF)"
        Write-Host "  -> $windowsPath (CRLF)"
    }
}

$engineContent = Build-EngineIni -EnvVars $envVars -Defaults $defaults
if ($engineContent) {
    $linuxEnginePath = Join-Path $linuxConfigDir 'Engine.ini'
    $windowsEnginePath = Join-Path $windowsConfigDir 'Engine.ini'
    Write-IniFile -Path $linuxEnginePath -Content $engineContent -LineEnding "`n"
    Write-IniFile -Path $windowsEnginePath -Content $engineContent -LineEnding "`r`n"
    $writtenFiles += $linuxEnginePath, $windowsEnginePath
    if (-not $Quiet) { Write-Host "[compile-settings] Engine.ini written to both platforms" }
}

# Validation
if ($Validate) {
    if (-not $Quiet) { Write-Host '[compile-settings] Validating...' }
    $linuxSettings = Join-Path $linuxConfigDir 'PalWorldSettings.ini'
    $windowsSettings = Join-Path $windowsConfigDir 'PalWorldSettings.ini'

    if ((Test-Path -LiteralPath $linuxSettings) -and (Test-Path -LiteralPath $windowsSettings)) {
        $linuxRaw = Get-Content -LiteralPath $linuxSettings -Raw
        $windowsRaw = Get-Content -LiteralPath $windowsSettings -Raw
        # Strip line-ending differences
        $linuxNorm = $linuxRaw -replace "`r`n", "`n"
        $windowsNorm = $windowsRaw -replace "`r`n", "`n"
        if ($linuxNorm -ne $windowsNorm) {
            $validationErrors += 'PalWorldSettings.ini content differs between Linux and Windows (excluding line endings)'
        }
    }

    # Check key fields exist
    $criticalKeys = @('ServerPlayerMaxNum', 'CoopPlayerMaxNum', 'ExpRate', 'ServerName', 'RCONEnabled')
    foreach ($key in $criticalKeys) {
        if ($windowsRaw -notmatch "$key=") {
            $validationErrors += "Critical INI key missing: $key"
        }
    }

    # Drift: .env mtime vs INI mtime
    $envMtime = (Get-Item -LiteralPath $envPath).LastWriteTime
    if (Test-Path -LiteralPath $windowsSettings) {
        $iniMtime = (Get-Item -LiteralPath $windowsSettings).LastWriteTime
        if ($envMtime -gt $iniMtime) {
            $validationErrors += "Drift: .env mtime ($($envMtime.ToString('o'))) > INI mtime ($($iniMtime.ToString('o')))"
        }
    }
}

# Write compile log
$logEntry = [ordered]@{
    ts          = $startTime.ToString('o')
    fieldCount  = $fieldCount
    files       = $writtenFiles
    sha256      = @{}
    validation  = if ($validationErrors.Count -eq 0) { 'ok' } else { 'errors' }
    errors      = $validationErrors
}
foreach ($f in $writtenFiles) {
    $logEntry.sha256[$f] = Get-FileSha256 -Path $f
}
$logLine = $logEntry | ConvertTo-Json -Compress
Add-Content -LiteralPath $compileLogPath -Value $logLine -Encoding UTF8

if (-not $Quiet) {
    $elapsed = ((Get-Date) - $startTime).TotalMilliseconds
    Write-Host "[compile-settings] Done in $([int]$elapsed)ms"
    if ($Validate -and $validationErrors.Count -gt 0) {
        Write-Host '[compile-settings] Validation errors:' -ForegroundColor Yellow
        foreach ($e in $validationErrors) { Write-Host "  - $e" -ForegroundColor Yellow }
    }
}

if ($Validate -and $validationErrors.Count -gt 0) { exit 1 }
exit 0
