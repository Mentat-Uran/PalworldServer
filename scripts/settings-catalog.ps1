# Settings catalog for the local Palworld Web Console.
#
# Evidence boundary:
# - "game" keys are consumed by the pinned image's compile-settings.sh and
#   written to PalWorldSettings.ini.
# - "engine" keys are consumed by compile-engine.sh when
#   DISABLE_GENERATE_ENGINE=false.
# - "container" keys are consumed by the pinned image's startup, backup,
#   update, logging, pause, or notification scripts.
# - ARM64/Box64-only keys are intentionally excluded on this amd64 host.

function New-SettingsCatalog {
    $catalog = [ordered]@{}

    $integerKeys = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
    @(
        "PLAYERS", "COOP_PLAYER_MAX_NUM", "DROP_ITEM_MAX_NUM", "DROP_ITEM_MAX_NUM_UNKO",
        "BASE_CAMP_MAX_NUM", "BASE_CAMP_WORKER_MAX_NUM", "GUILD_PLAYER_MAX_NUM",
        "BASE_CAMP_MAX_NUM_IN_GUILD", "PUBLIC_PORT", "RCON_PORT", "REST_API_PORT",
        "CHAT_POST_LIMIT_PER_MINUTE", "SUPPLY_DROP_SPAN", "MAX_BUILDING_LIMIT_NUM",
        "PHYSICS_ACTIVE_DROP_ITEM_MAX_NUM", "GUILD_REJOIN_COOLDOWN_MINUTES",
        "AUTO_TRANSFER_MASTER_THRESHOLD_DAYS", "MAX_GUILDS_PER_FRAME",
        "ADDITIONAL_DROP_ITEM_NUM_WHEN_PLAYER_KILLING_IN_PVP_MODE",
        "BUILDING_NAME_DISPLAY_CACHE_TTL_SECONDS", "PORT", "QUERY_PORT", "PUID", "PGID",
        "WORKER_THREADS_SERVER", "OLD_BACKUP_DAYS", "AUTO_UPDATE_WARN_MINUTES",
        "AUTO_REBOOT_WARN_MINUTES", "AUTO_PAUSE_TIMEOUT_EST", "PLAYER_LOGGING_POLL_PERIOD",
        "DISCORD_CONNECT_TIMEOUT", "DISCORD_MAX_TIMEOUT", "LAN_SERVER_MAX_TICK_RATE",
        "NET_SERVER_MAX_TICK_RATE", "CONFIGURED_INTERNET_SPEED", "CONFIGURED_LAN_SPEED",
        "MAX_CLIENT_RATE", "MAX_INTERNET_CLIENT_RATE", "FIXED_FRAME_RATE",
        "MIN_DESIRED_FRAME_RATE", "NET_CLIENT_TICKS_PER_SECOND"
    ) | ForEach-Object { [void]$integerKeys.Add($_) }

    $groupOverrides = @{
        TZ = "runtime"; PORT = "network"; QUERY_PORT = "network"; PUBLIC_PORT = "network"
        PUBLIC_IP = "network"; REGION = "network"; COMMUNITY = "network"
         RCON_ENABLED = "network"; RCON_PORT = "network"; REST_API_ENABLED = "network"
         REST_API_PORT = "network"; ENABLE_LEGACY_RCON = "network"; NETWORK_MODE = "network"
         TUNNEL_PROVIDER = "network"; TUNNEL_EXECUTABLE = "network"; TUNNEL_ARGUMENTS = "network"
         TUNNEL_LOCAL_PORT = "network"; TUNNEL_REMOTE_PORT = "network"; PROJECT_INSTANCE_ID = "runtime"; USEAUTH = "network"; BAN_LIST_URL = "network"
        CROSSPLAY_PLATFORMS = "network"; SERVER_REPLICATE_PAWN_CULL_DISTANCE = "network"
        SERVER_NAME = "basic"; SERVER_DESCRIPTION = "basic"; SERVER_PASSWORD = "basic"
        ADMIN_PASSWORD = "basic"; PLAYERS = "basic"; COOP_PLAYER_MAX_NUM = "basic"
        DIFFICULTY = "world"; RANDOMIZER_TYPE = "world"; RANDOMIZER_SEED = "world"
        IS_RANDOMIZER_PAL_LEVEL_RANDOM = "world"; DAYTIME_SPEEDRATE = "world"
        NIGHTTIME_SPEEDRATE = "world"; EXP_RATE = "world"; PAL_CAPTURE_RATE = "world"
        PAL_SPAWN_NUM_RATE = "world"; PAL_EGG_DEFAULT_HATCHING_TIME = "world"
        WORK_SPEED_RATE = "world"; AUTO_SAVE_SPAN = "world"; SUPPLY_DROP_SPAN = "world"
        ENABLE_PREDATOR_BOSS_PAL = "world"; ENABLE_INVADER_ENEMY = "world"
        ENABLE_FAST_TRAVEL = "world"; IS_START_LOCATION_SELECT_BY_MAP = "world"
        BUILD_AREA_LIMIT = "building"; BASE_CAMP_MAX_NUM = "building"
        BASE_CAMP_WORKER_MAX_NUM = "building"; BASE_CAMP_MAX_NUM_IN_GUILD = "building"
        MAX_BUILDING_LIMIT_NUM = "building"; ENABLE_BUILDING_PLAYER_UID_DISPLAY = "building"
        BUILDING_NAME_DISPLAY_CACHE_TTL_SECONDS = "building"
        AUTO_RESET_GUILD_NO_ONLINE_PLAYERS = "guild"
        AUTO_RESET_GUILD_TIME_NO_ONLINE_PLAYERS = "guild"; GUILD_PLAYER_MAX_NUM = "guild"
        GUILD_REJOIN_COOLDOWN_MINUTES = "guild"; AUTO_TRANSFER_MASTER_CHECK_INTERVAL_SECONDS = "guild"
        AUTO_TRANSFER_MASTER_THRESHOLD_DAYS = "guild"; MAX_GUILDS_PER_FRAME = "guild"
        IS_MULTIPLAY = "guild"; EXIST_PLAYER_AFTER_LOGOUT = "guild"
        ENABLE_DEFENSE_OTHER_GUILD_PLAYER = "guild"
        INVISIBLE_OTHER_GUILD_BASE_CAMP_AREA_FX = "guild"
        SHOW_PLAYER_LIST = "permissions"; CHAT_POST_LIMIT_PER_MINUTE = "permissions"
        ALLOW_GLOBAL_PALBOX_EXPORT = "permissions"; ALLOW_GLOBAL_PALBOX_IMPORT = "permissions"
        ALLOW_CLIENT_MOD = "permissions"; DENY_TECHNOLOGY_LIST = "permissions"
        ENABLE_VOICE_CHAT = "permissions"; VOICE_CHAT_MAX_VOLUME_DISTANCE = "permissions"
        VOICE_CHAT_ZERO_VOLUME_DISTANCE = "permissions"; IS_SHOW_JOIN_LEFT_MESSAGE = "permissions"
        USE_BACKUP_SAVE_DATA = "automation"; LOG_FORMAT_TYPE = "logging"
    }

    # Localized labels are rendered by the UTF-8 HTML frontend. Keep this
    # PowerShell 5.1 file ASCII-only so it parses consistently without a BOM.
    $labelZh = @{}

    function Get-Group([string]$key, [string]$source) {
        if ($groupOverrides.ContainsKey($key)) { return $groupOverrides[$key] }
        if ($source -eq "engine") { return "engine" }
        if ($key -match "^(BACKUP|DELETE_OLD_BACKUPS|OLD_BACKUP|AUTO_UPDATE|AUTO_REBOOT|AUTO_PAUSE|UPDATE_ON_BOOT)") { return "automation" }
        if ($key -match "^(DISCORD|LOG_|ENABLE_PLAYER_LOGGING|PLAYER_LOGGING)") { return "logging" }
        if ($key -match "(GUILD|MULTIPLAY|OTHER_GUILD)") { return "guild" }
        if ($key -match "(BUILD|BASE_CAMP|CAMP)") { return "building" }
        if ($key -match "(DROP|ITEM|WEIGHT|COLLECTION|CORRUPTION|DURABILITY)") { return "items" }
        if ($key -match "(DAMAGE|PVP|PVP|DEATH|HARDCORE|RESPAWN|ACTIVE_UNKO|FRIENDLY|ENHANCE_STAT_ATTACK)") { return "combat" }
        if ($key -match "^PLAYER_|AIM_ASSIST|ENHANCE_STAT_(HEALTH|STAMINA|WEIGHT|WORK_SPEED)") { return "player" }
        if ($key -match "^PAL_|MONSTER_FARM") { return "pal" }
        if ($source -eq "container") { return "runtime" }
        return "advanced"
    }

    function Get-EnglishLabel([string]$key) {
        $text = ($key -replace "_", " ").ToLowerInvariant()
        return (Get-Culture).TextInfo.ToTitleCase($text)
    }

    function Add-Setting {
        param(
            [string]$Key,
            [string]$Default,
            [string]$Source,
            [string]$Type = "",
            [Nullable[double]]$Min = $null,
            [Nullable[double]]$Max = $null,
            [Nullable[double]]$Step = $null,
            [string[]]$Options = @(),
            [string]$Risk = "normal",
            [bool]$Secret = $false,
            [string]$DependsOn = "",
            [string]$DescriptionZh = "",
            [string]$DescriptionEn = ""
        )
        if (-not $Type) {
            if ($Default -match "^(?i:true|false)$") { $Type = "boolean" }
            elseif ($integerKeys.Contains($Key)) { $Type = "integer" }
            elseif ($Default -match "^-?(?:\d+\.?\d*|\.\d+)$") { $Type = "number" }
            else { $Type = "string" }
        }
        if ($Type -eq "choice" -and $Options.Count -eq 0) { throw "Choice setting $Key needs options." }

        $group = Get-Group $Key $Source
        $meta = [ordered]@{
            key = $Key
            type = $Type
            default = $Default
            source = $Source
            group = $group
            risk = $Risk
            secret = $Secret
            dependsOn = $DependsOn
            labelZh = $(if ($labelZh.ContainsKey($Key)) { $labelZh[$Key] } else { "" })
            labelEn = Get-EnglishLabel $Key
            descriptionZh = $DescriptionZh
            descriptionEn = $DescriptionEn
            restartRequired = $true
            advanced = ($group -in @("runtime", "engine", "advanced", "logging"))
        }
        if ($null -ne $Min) { $meta["min"] = [double]$Min }
        if ($null -ne $Max) { $meta["max"] = [double]$Max }
        if ($null -ne $Step) { $meta["step"] = [double]$Step }
        if ($Options.Count -gt 0) { $meta["options"] = @($Options) }
        if ($Type -eq "string" -or $Type -eq "secret") {
            $meta["minLength"] = $(if ($Key -eq "SERVER_NAME") { 1 } elseif ($Key -eq "ADMIN_PASSWORD") { 16 } else { 0 })
            $meta["maxLength"] = $(if ($Key -match "DESCRIPTION|MESSAGE") { 512 } elseif ($Key -match "URL|LIST") { 2048 } else { 256 })
        }
        $catalog[$Key] = $meta
    }

    function Set-CatalogValue {
        param([string]$Key, [string]$Property, $Value)
        $meta = $catalog[$Key]
        $meta[$Property] = $Value
    }

    # Exact PalWorldSettings.ini environment mapping from the pinned image.
    $gameRows = @'
DIFFICULTY|None
RANDOMIZER_TYPE|None
RANDOMIZER_SEED|
IS_RANDOMIZER_PAL_LEVEL_RANDOM|false
DAYTIME_SPEEDRATE|1
NIGHTTIME_SPEEDRATE|1
EXP_RATE|1
PAL_CAPTURE_RATE|1
PAL_SPAWN_NUM_RATE|1
PAL_DAMAGE_RATE_ATTACK|1
PAL_DAMAGE_RATE_DEFENSE|1
PLAYER_DAMAGE_RATE_ATTACK|1
PLAYER_DAMAGE_RATE_DEFENSE|1
PLAYER_STOMACH_DECREASE_RATE|1
PLAYER_STAMINA_DECREASE_RATE|1
PLAYER_AUTO_HP_REGEN_RATE|1
PLAYER_AUTO_HP_REGEN_RATE_IN_SLEEP|1
PAL_STOMACH_DECREASE_RATE|1
PAL_STAMINA_DECREASE_RATE|1
PAL_AUTO_HP_REGEN_RATE|1
PAL_AUTO_HP_REGEN_RATE_IN_SLEEP|1
BUILD_OBJECT_HP_RATE|1
BUILD_OBJECT_DAMAGE_RATE|1
BUILD_OBJECT_DETERIORATION_DAMAGE_RATE|1
COLLECTION_DROP_RATE|1
COLLECTION_OBJECT_HP_RATE|1
COLLECTION_OBJECT_RESPAWN_SPEED_RATE|1
ENEMY_DROP_ITEM_RATE|1
DEATH_PENALTY|Item
ENABLE_PLAYER_TO_PLAYER_DAMAGE|false
ENABLE_FRIENDLY_FIRE|false
ENABLE_INVADER_ENEMY|true
ACTIVE_UNKO|false
ENABLE_AIM_ASSIST_PAD|true
ENABLE_AIM_ASSIST_KEYBOARD|false
DROP_ITEM_MAX_NUM|3000
DROP_ITEM_MAX_NUM_UNKO|100
BASE_CAMP_MAX_NUM|128
BASE_CAMP_WORKER_MAX_NUM|15
DROP_ITEM_ALIVE_MAX_HOURS|1
AUTO_RESET_GUILD_NO_ONLINE_PLAYERS|false
AUTO_RESET_GUILD_TIME_NO_ONLINE_PLAYERS|72
GUILD_PLAYER_MAX_NUM|20
BASE_CAMP_MAX_NUM_IN_GUILD|4
PAL_EGG_DEFAULT_HATCHING_TIME|1
WORK_SPEED_RATE|1
AUTO_SAVE_SPAN|30
IS_MULTIPLAY|false
IS_PVP|false
HARDCORE|false
CHARACTER_RECREATE_IN_HARDCORE|false
PAL_LOST|false
CAN_PICKUP_OTHER_GUILD_DEATH_PENALTY_DROP|false
ENABLE_NON_LOGIN_PENALTY|true
ENABLE_FAST_TRAVEL|true
IS_START_LOCATION_SELECT_BY_MAP|false
EXIST_PLAYER_AFTER_LOGOUT|false
ENABLE_DEFENSE_OTHER_GUILD_PLAYER|false
INVISIBLE_OTHER_GUILD_BASE_CAMP_AREA_FX|false
BUILD_AREA_LIMIT|false
ITEM_WEIGHT_RATE|1
COOP_PLAYER_MAX_NUM|4
SERVER_NAME|Default Palworld Server
SERVER_DESCRIPTION|
ADMIN_PASSWORD|
SERVER_PASSWORD|
PUBLIC_PORT|8211
PUBLIC_IP|
RCON_ENABLED|false
RCON_PORT|25575
REGION|
USEAUTH|true
BAN_LIST_URL|https://b.palworldgame.com/api/banlist.txt
REST_API_ENABLED|true
REST_API_PORT|8212
SHOW_PLAYER_LIST|false
CHAT_POST_LIMIT_PER_MINUTE|30
USE_BACKUP_SAVE_DATA|true
SUPPLY_DROP_SPAN|180
ENABLE_PREDATOR_BOSS_PAL|true
MAX_BUILDING_LIMIT_NUM|0
SERVER_REPLICATE_PAWN_CULL_DISTANCE|15000
CROSSPLAY_PLATFORMS|(Steam,Xbox,PS5,Mac)
ALLOW_GLOBAL_PALBOX_EXPORT|true
ALLOW_GLOBAL_PALBOX_IMPORT|false
EQUIPMENT_DURABILITY_DAMAGE_RATE|1
ITEM_CONTAINER_FORCE_MARK_DIRTY_INTERVAL|1
ITEM_CORRUPTION_MULTIPLIER|1
PHYSICS_ACTIVE_DROP_ITEM_MAX_NUM|-1
ALLOW_CLIENT_MOD|true
PLAYER_DATA_PAL_STORAGE_UPDATE_CHECK_TICK_INTERVAL|1
LOG_FORMAT_TYPE|Text
IS_SHOW_JOIN_LEFT_MESSAGE|true
MONSTER_FARM_ACTION_SPEED_RATE|1
DENY_TECHNOLOGY_LIST|
GUILD_REJOIN_COOLDOWN_MINUTES|0
AUTO_TRANSFER_MASTER_CHECK_INTERVAL_SECONDS|3600
AUTO_TRANSFER_MASTER_THRESHOLD_DAYS|14
MAX_GUILDS_PER_FRAME|10
BLOCK_RESPAWN_TIME|5
RESPAWN_PENALTY_DURATION_THRESHOLD|0
RESPAWN_PENALTY_TIME_SCALE|2
DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_BASE_CAMP|false
DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_PLAYER|false
ADDITIONAL_DROP_ITEM_WHEN_PLAYER_KILLING_IN_PVP_MODE|PlayerDropItem
ADDITIONAL_DROP_ITEM_NUM_WHEN_PLAYER_KILLING_IN_PVP_MODE|1
ADDITIONAL_DROP_ITEM_WHEN_PLAYER_KILLING_IN_PVP_MODE_ENABLED|false
ENABLE_VOICE_CHAT|false
VOICE_CHAT_MAX_VOLUME_DISTANCE|3000
VOICE_CHAT_ZERO_VOLUME_DISTANCE|15000
ALLOW_ENHANCE_STAT_HEALTH|true
ALLOW_ENHANCE_STAT_ATTACK|true
ALLOW_ENHANCE_STAT_STAMINA|true
ALLOW_ENHANCE_STAT_WEIGHT|true
ALLOW_ENHANCE_STAT_WORK_SPEED|true
ENABLE_BUILDING_PLAYER_UID_DISPLAY|false
BUILDING_NAME_DISPLAY_CACHE_TTL_SECONDS|60
'@

    foreach ($row in ($gameRows -split "`r?`n")) {
        if (-not $row.Trim()) { continue }
        $parts = $row.Split(@("|"), 2, [System.StringSplitOptions]::None)
        $key = $parts[0]
        $default = $parts[1]
        $params = @{ Key = $key; Default = $default; Source = "game" }
        if ($key -eq "DIFFICULTY") {
            $params.Type = "choice"; $params.Options = @("None", "Normal", "Difficult")
        } elseif ($key -eq "RANDOMIZER_TYPE") {
            $params.Type = "choice"; $params.Options = @("None", "Region", "All")
        } elseif ($key -eq "DEATH_PENALTY") {
            $params.Type = "choice"; $params.Options = @("None", "Item", "ItemAndEquipment", "All")
        } elseif ($key -eq "LOG_FORMAT_TYPE") {
            $params.Type = "choice"; $params.Options = @("Text", "Json")
        } elseif ($key -in @("ADMIN_PASSWORD", "SERVER_PASSWORD")) {
            $params.Type = "secret"; $params.Secret = $true
        }
        if ($key -match "^(IS_PVP|HARDCORE|CHARACTER_RECREATE|PAL_LOST|ENABLE_PLAYER_TO_PLAYER_DAMAGE|ALLOW_GLOBAL_PALBOX_IMPORT|ALLOW_CLIENT_MOD|DENY_TECHNOLOGY_LIST)") {
            $params.Risk = "caution"
        }
        if ($key -match "^(CHARACTER_RECREATE_IN_HARDCORE|PAL_LOST)$") { $params.DependsOn = "HARDCORE=true" }
        if ($key -match "(PVP|PvP)" -and $key -ne "IS_PVP") { $params.DependsOn = "IS_PVP=true" }
        if ($key -match "^VOICE_CHAT_" -and $key -ne "ENABLE_VOICE_CHAT") { $params.DependsOn = "ENABLE_VOICE_CHAT=true" }
        if ($key -match "^RANDOMIZER_" -and $key -ne "RANDOMIZER_TYPE") { $params.DependsOn = "RANDOMIZER_TYPE!=None" }
        Add-Setting @params
    }

    # Startup, maintenance, backup, logging and image behavior on amd64.
    $containerRows = @'
TZ|UTC|string
PORT|8211|integer
PLAYERS|32|integer
PUID|1000|integer
PGID|1000|integer
QUERY_PORT|27015|integer
COMMUNITY|false|boolean
MULTITHREADING|false|boolean
ENABLE_PERF_THREADING_ARGS|false|boolean
WORKER_THREADS_SERVER|4|integer
PALWORLD_ALLOW_NEGATIVE_DELTA_TIME|false|boolean
UPDATE_ON_BOOT|false|boolean
BACKUP_ENABLED|true|boolean
BACKUP_CRON_EXPRESSION|0 0 * * *|string
DELETE_OLD_BACKUPS|true|boolean
OLD_BACKUP_DAYS|7|integer
AUTO_UPDATE_ENABLED|false|boolean
AUTO_UPDATE_CRON_EXPRESSION|0 * * * *|string
AUTO_UPDATE_WARN_MINUTES|30|integer
AUTO_REBOOT_ENABLED|false|boolean
AUTO_REBOOT_EVEN_IF_PLAYERS_ONLINE|false|boolean
AUTO_REBOOT_WARN_MINUTES|5|integer
AUTO_REBOOT_CRON_EXPRESSION|0 0 * * *|string
AUTO_PAUSE_ENABLED|false|boolean
AUTO_PAUSE_TIMEOUT_EST|180|integer
AUTO_PAUSE_LOG|true|boolean
AUTO_PAUSE_DEBUG|false|boolean
ENABLE_PLAYER_LOGGING|true|boolean
PLAYER_LOGGING_POLL_PERIOD|10|integer
LOG_FILTER_ENABLED|true|boolean
LOG_LEVEL|INFO|choice
ENABLE_GAMEDATA_API|false|boolean
USE_DEPOT_DOWNLOADER|false|boolean
INSTALL_BETA_INSIDER|false|boolean
DISCORD_WEBHOOK_URL||secret
DISCORD_CONNECT_TIMEOUT|30|integer
DISCORD_MAX_TIMEOUT|30|integer
DISCORD_SUPPRESS_NOTIFICATIONS|false|boolean
'@
    foreach ($row in ($containerRows -split "`r?`n")) {
        if (-not $row.Trim()) { continue }
        $parts = $row.Split(@("|"), 3, [System.StringSplitOptions]::None)
        $key = $parts[0]; $default = $parts[1]; $type = $parts[2]
        $params = @{ Key = $key; Default = $default; Source = "container"; Type = $type }
        if ($type -eq "secret") { $params.Secret = $true }
        if ($key -eq "LOG_LEVEL") { $params.Options = @("TRACE", "DEBUG", "INFO", "WARN", "ERROR") }
        if ($key -match "^(PUID|PGID|PORT|QUERY_PORT|MULTITHREADING|ENABLE_PERF|WORKER|PALWORLD_ALLOW|AUTO_UPDATE|AUTO_REBOOT|USE_DEPOT|INSTALL_BETA)") {
            $params.Risk = "caution"
        }
        if ($key -eq "AUTO_REBOOT_EVEN_IF_PLAYERS_ONLINE") { $params.Risk = "danger"; $params.DependsOn = "AUTO_REBOOT_ENABLED=true" }
        if ($key -match "^AUTO_PAUSE_" -and $key -ne "AUTO_PAUSE_ENABLED") { $params.DependsOn = "AUTO_PAUSE_ENABLED=true" }
        if ($key -match "^AUTO_UPDATE_" -and $key -ne "AUTO_UPDATE_ENABLED") { $params.DependsOn = "AUTO_UPDATE_ENABLED=true" }
        if ($key -match "^AUTO_REBOOT_" -and $key -ne "AUTO_REBOOT_ENABLED") { $params.DependsOn = "AUTO_REBOOT_ENABLED=true" }
        if ($key -match "^BACKUP_|^DELETE_OLD|^OLD_BACKUP") { $params.DependsOn = "BACKUP_ENABLED=true" }
        if ($key -eq "WORKER_THREADS_SERVER") { $params.DependsOn = "ENABLE_PERF_THREADING_ARGS=true" }
        Add-Setting @params
    }

    # Management and optional tunnel controls are deliberately kept separate
    # from game settings so the UI can validate the operational contract.
    Add-Setting -Key "ENABLE_LEGACY_RCON" -Default "false" -Source "network" -Type "boolean" -Risk "caution"
    Add-Setting -Key "PROJECT_INSTANCE_ID" -Default "palworld-server" -Source "runtime" -Type "string" -Risk "caution" `
        -DescriptionZh "Instance identity for the Docker container and local runtime lock." `
        -DescriptionEn "Docker container and local runtime-lock identity; use a unique value when running multiple project directories on one host."
    Add-Setting -Key "WINDOWS_REST_COMPATIBILITY_MODE" -Default "ini-only" -Source "runtime" -Type "choice" -Options @("compat", "ini-only") -Risk "caution" `
        -DescriptionZh "Windows REST launch compatibility mode." `
        -DescriptionEn "Use compat to pass the legacy REST launch switch required by some Windows server builds; use ini-only only after verifying the build."
    Add-Setting -Key "NETWORK_MODE" -Default "direct" -Source "network" -Type "choice" -Options @("direct", "community", "tunnel")
    $providerCatalogScript = Join-Path $PSScriptRoot 'tunnel-provider-catalog.ps1'
    if (-not (Get-Command Get-TunnelProviderIds -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $providerCatalogScript -PathType Leaf)) {
        . $providerCatalogScript
    }
    $providerOptions = @(Get-TunnelProviderIds -ProjectDirectory (Split-Path -Parent $PSScriptRoot))
    Add-Setting -Key "TUNNEL_PROVIDER" -Default "none" -Source "network" -Type "choice" -Options $providerOptions
    Add-Setting -Key "TUNNEL_EXECUTABLE" -Default "" -Source "network" -Type "string" -DependsOn "TUNNEL_PROVIDER!=none"
    Add-Setting -Key "TUNNEL_ARGUMENTS" -Default "" -Source "network" -Type "secret" -Secret $true -DependsOn "TUNNEL_PROVIDER!=none"
    Add-Setting -Key "TUNNEL_LOCAL_PORT" -Default "8211" -Source "network" -Type "integer" -DependsOn "NETWORK_MODE=tunnel"
    Add-Setting -Key "TUNNEL_REMOTE_PORT" -Default "" -Source "network" -Type "string" -DependsOn "NETWORK_MODE=tunnel"

    # Notification hooks present in the pinned image. URLs are write-only.
    $discordEvents = @(
        @("PLAYER_JOIN", "player_name has joined Palworld!"),
        @("PLAYER_LEAVE", "player_name has left Palworld."),
        @("PRE_BACKUP", "Creating backup..."),
        @("POST_BACKUP", "Backup created at file_path"),
        @("PRE_BACKUP_DELETE", "Removing backups older than old_backup_days days"),
        @("POST_BACKUP_DELETE", "Removed backups older than old_backup_days days"),
        @("ERR_BACKUP_DELETE", "Unable to delete old backups."),
        @("PRE_SHUTDOWN", "Server is shutting down..."),
        @("POST_SHUTDOWN", "Server has been stopped!"),
        @("PRE_START", "Server has been started!"),
        @("PRE_UPDATE_BOOT", "Server is updating..."),
        @("POST_UPDATE_BOOT", "Server update complete!")
    )
    foreach ($event in $discordEvents) {
        $prefix = "DISCORD_$($event[0])_MESSAGE"
        Add-Setting -Key "${prefix}_ENABLED" -Default "false" -Source "container" -Type "boolean" -DependsOn "DISCORD_WEBHOOK_URL=configured"
        Add-Setting -Key "${prefix}_URL" -Default "" -Source "container" -Type "secret" -Secret $true -DependsOn "${prefix}_ENABLED=true"
        Add-Setting -Key $prefix -Default $event[1] -Source "container" -Type "string" -DependsOn "${prefix}_ENABLED=true"
    }

    # Engine.ini generation is off by default. These values have no effect
    # until DISABLE_GENERATE_ENGINE is set to false.
    Add-Setting -Key "DISABLE_GENERATE_ENGINE" -Default "true" -Source "engine" -Type "boolean" -Risk "caution" `
        -DescriptionZh "Engine.ini generation is disabled while this value is true." `
        -DescriptionEn "When true the image does not regenerate Engine.ini; set false to apply the engine fields below."
    $engineRows = @'
LAN_SERVER_MAX_TICK_RATE|120|integer
NET_SERVER_MAX_TICK_RATE|120|integer
CONFIGURED_INTERNET_SPEED|104857600|integer
CONFIGURED_LAN_SPEED|104857600|integer
MAX_CLIENT_RATE|104857600|integer
MAX_INTERNET_CLIENT_RATE|104857600|integer
SMOOTH_FRAME_RATE|true|boolean
SMOOTH_FRAME_RATE_UPPER_LIMIT|120|number
SMOOTH_FRAME_RATE_LOWER_LIMIT|30|number
USE_FIXED_FRAME_RATE|false|boolean
FIXED_FRAME_RATE|120|integer
MIN_DESIRED_FRAME_RATE|60|integer
NET_CLIENT_TICKS_PER_SECOND|120|integer
'@
    foreach ($row in ($engineRows -split "`r?`n")) {
        if (-not $row.Trim()) { continue }
        $parts = $row.Split(@("|"), 3, [System.StringSplitOptions]::None)
        Add-Setting -Key $parts[0] -Default $parts[1] -Source "engine" -Type $parts[2] `
            -Risk "caution" -DependsOn "DISABLE_GENERATE_ENGINE=false"
    }

    # Add broad structural limits only where the underlying format has a
    # clear constraint. Unknown game-specific ranges remain finite-number
    # validated without invented restrictions.
    foreach ($key in @("PORT", "PUBLIC_PORT", "QUERY_PORT", "RCON_PORT", "REST_API_PORT")) {
        Set-CatalogValue $key "min" 1.0; Set-CatalogValue $key "max" 65535.0; Set-CatalogValue $key "step" 1.0
    }
    foreach ($key in @("PLAYERS", "COOP_PLAYER_MAX_NUM")) {
        Set-CatalogValue $key "min" 1.0; Set-CatalogValue $key "max" 32.0; Set-CatalogValue $key "step" 1.0
    }
    foreach ($key in @("PUID", "PGID")) {
        Set-CatalogValue $key "min" 0.0; Set-CatalogValue $key "max" 2147483647.0; Set-CatalogValue $key "step" 1.0
    }
    foreach ($key in @("OLD_BACKUP_DAYS", "AUTO_UPDATE_WARN_MINUTES", "AUTO_REBOOT_WARN_MINUTES",
        "AUTO_PAUSE_TIMEOUT_EST", "PLAYER_LOGGING_POLL_PERIOD", "CHAT_POST_LIMIT_PER_MINUTE")) {
        Set-CatalogValue $key "min" 0.0; Set-CatalogValue $key "step" 1.0
    }
    foreach ($key in @("EXP_RATE", "PAL_CAPTURE_RATE", "PAL_SPAWN_NUM_RATE", "DAYTIME_SPEEDRATE",
        "NIGHTTIME_SPEEDRATE", "WORK_SPEED_RATE")) {
        Set-CatalogValue $key "min" 0.0; Set-CatalogValue $key "step" 0.1
    }
    Set-CatalogValue "BASE_CAMP_MAX_NUM_IN_GUILD" "min" 1.0
    Set-CatalogValue "BASE_CAMP_MAX_NUM_IN_GUILD" "max" 10.0
    Set-CatalogValue "BASE_CAMP_WORKER_MAX_NUM" "min" 1.0
    Set-CatalogValue "BASE_CAMP_WORKER_MAX_NUM" "max" 50.0
    Set-CatalogValue "SERVER_REPLICATE_PAWN_CULL_DISTANCE" "min" 5000.0
    Set-CatalogValue "SERVER_REPLICATE_PAWN_CULL_DISTANCE" "max" 15000.0
    Set-CatalogValue "MAX_BUILDING_LIMIT_NUM" "min" 0.0
    Set-CatalogValue "VOICE_CHAT_MAX_VOLUME_DISTANCE" "min" 0.0
    Set-CatalogValue "VOICE_CHAT_ZERO_VOLUME_DISTANCE" "min" 0.0
    Set-CatalogValue "PHYSICS_ACTIVE_DROP_ITEM_MAX_NUM" "min" -1.0
    # Keep the catalog source compatible with Windows PowerShell 5.1 parsing.

    return $catalog
}
