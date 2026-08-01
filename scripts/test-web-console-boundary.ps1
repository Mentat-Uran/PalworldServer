[CmdletBinding()]
param(
    [int]$Port = 0
)

# Read-only runtime probe for the Web Console's loopback-only boundary. It does
# not change a service, authenticate, submit a request body, or read player data.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot

function Assert-Boundary {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "WEB_CONSOLE_BOUNDARY_FAILED: $Message" }
}

function Invoke-BoundaryCurl {
    param([string]$Url, [string[]]$Headers = @())
    $arguments = @('--noproxy', '*', '--silent', '--show-error', '--connect-timeout', '4', '--max-time', '6', '--include')
    foreach ($header in $Headers) {
        $arguments += @('-H', $header)
    }
    $arguments += $Url
    $output = & curl.exe @arguments 2>&1
    return [ordered]@{
        exitCode = $LASTEXITCODE
        text = [string]::Join([Environment]::NewLine, [string[]]$output)
    }
}

if ($Port -le 0) {
    $portPath = Join-Path $projectDir '.settings-panel.port'
    if (-not (Test-Path -LiteralPath $portPath -PathType Leaf)) {
        throw 'Web Console port file is missing. Start the local Web Console before this probe.'
    }
    $Port = [int]([System.IO.File]::ReadAllText($portPath).Trim())
}

$local = Invoke-BoundaryCurl -Url ('http://127.0.0.1:' + $Port + '/api/state')
Assert-Boundary -Condition ($local.exitCode -eq 0 -and $local.text -match 'HTTP/1\.1 200' -and $local.text -match '"status"') -Message 'loopback API probe did not return the expected local state response'

$lanIp = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' -and $_.AddressState -eq 'Preferred' } |
    Select-Object -First 1 -ExpandProperty IPAddress
if (-not $lanIp) {
    Write-Output 'WEB_CONSOLE_BOUNDARY_LAN=skipped-no-preferred-ipv4'
    Write-Output 'WEB_CONSOLE_BOUNDARY=passed'
    exit 0
}

$lanUrl = 'http://' + $lanIp + ':' + $Port + '/api/state'
$invalidHost = Invoke-BoundaryCurl -Url $lanUrl
Assert-Boundary -Condition ($invalidHost.exitCode -eq 0 -and $invalidHost.text -match 'HTTP/1\.1 400' -and $invalidHost.text -match 'Invalid Hostname') -Message 'LAN request without a loopback Host was not rejected by HTTP.sys'

$spoofedHost = Invoke-BoundaryCurl -Url $lanUrl -Headers @('Host: localhost:' + $Port)
Assert-Boundary -Condition ($spoofedHost.exitCode -eq 0 -and $spoofedHost.text -match 'HTTP/1\.1 403' -and $spoofedHost.text -match 'Web Console is restricted to localhost') -Message 'LAN request with a spoofed loopback Host was not rejected by the request gate'
Assert-Boundary -Condition ($spoofedHost.text -notmatch '"memMb"|"players"|"worldguid"') -Message 'non-loopback response disclosed dashboard data'
foreach ($header in @('X-Content-Type-Options: nosniff', 'X-Frame-Options: DENY', 'Referrer-Policy: no-referrer', 'Permissions-Policy: camera=\(\), microphone=\(\), geolocation=\(\)')) {
    Assert-Boundary -Condition ($spoofedHost.text -match $header) -Message "security header is missing from non-loopback rejection: $header"
}

Write-Output "WEB_CONSOLE_BOUNDARY_PORT=$Port"
Write-Output "WEB_CONSOLE_BOUNDARY_LAN=passed"
Write-Output 'WEB_CONSOLE_BOUNDARY=passed'
