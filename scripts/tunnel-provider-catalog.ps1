# Provider catalog shared by launch validation, the settings schema, and the
# optional tunnel lifecycle script. A provider is enabled by adding a folder
# under providers with a provider.json file; secrets and runtime arguments do
# not belong in this catalog.

function Get-TunnelProviderCatalog {
    param([string]$ProjectDirectory = (Split-Path -Parent $PSScriptRoot))

    $providersRoot = Join-Path $ProjectDirectory 'providers'
    if (-not (Test-Path -LiteralPath $providersRoot -PathType Container)) {
        throw "Tunnel provider directory is missing: $providersRoot"
    }

    $definitions = @()
    foreach ($directory in @(Get-ChildItem -LiteralPath $providersRoot -Directory -ErrorAction Stop)) {
        $manifestPath = Join-Path $directory.FullName 'provider.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }

        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $id = [string]$manifest.id
        if ($id -notmatch '^[a-z0-9][a-z0-9-]*$' -or $id -ne $directory.Name) {
            throw "Invalid tunnel provider id in $manifestPath. It must match its directory name and use lowercase letters, numbers, and hyphens."
        }
        if ([string]::IsNullOrWhiteSpace([string]$manifest.displayName)) {
            throw "Tunnel provider $id is missing displayName in $manifestPath."
        }

        $autoDiscover = @()
        if ($null -ne $manifest.autoDiscoverExecutables) {
            foreach ($entry in @($manifest.autoDiscoverExecutables)) {
                $name = [string]$entry
                if ($name -and $name -notmatch '[\\/]') { $autoDiscover += $name }
            }
        }
        $definitions += [pscustomobject][ordered]@{
            id = $id
            displayName = [string]$manifest.displayName
            kind = if ($manifest.kind) { [string]$manifest.kind } else { 'process' }
            autoDiscoverExecutables = @($autoDiscover)
            directory = $directory.FullName
        }
    }

    if (-not (@($definitions | Where-Object { $_.id -eq 'none' }).Count -eq 1)) {
        throw 'The tunnel provider catalog must contain exactly one providers/none/provider.json entry.'
    }
    return @($definitions | Sort-Object id)
}

function Get-TunnelProviderDefinition {
    param(
        [Parameter(Mandatory)][string]$Provider,
        [string]$ProjectDirectory = (Split-Path -Parent $PSScriptRoot)
    )

    if ($Provider -notmatch '^[a-z0-9][a-z0-9-]*$') { return $null }
    return @(Get-TunnelProviderCatalog -ProjectDirectory $ProjectDirectory |
        Where-Object { $_.id -eq $Provider }) | Select-Object -First 1
}

function Get-TunnelProviderIds {
    param([string]$ProjectDirectory = (Split-Path -Parent $PSScriptRoot))
    return @((Get-TunnelProviderCatalog -ProjectDirectory $ProjectDirectory | Select-Object -ExpandProperty id))
}
