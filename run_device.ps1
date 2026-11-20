<#
.SYNOPSIS
    Run RoadResQ on the physical Android device with the backend host compiled in.

.DESCRIPTION
    AppConfig deliberately holds no hardcoded development IP (spec §4), and its
    Android default is http://10.0.2.2:5050 — the *emulator* alias for the host
    machine, which is unreachable from a physical phone. Any `flutter run` or
    `flutter build apk` issued without --dart-define=ROADRESQ_HOST therefore
    produces an APK whose socket times out forever on a real device.

    This script detects the machine's current Wi-Fi IPv4 address and passes it
    explicitly, so the host can never be silently lost. If the Wi-Fi address
    changes (DHCP), the script picks up the new one automatically.

.EXAMPLE
    .\run_device.ps1
    .\run_device.ps1 -BackendHost 192.168.1.20
    .\run_device.ps1 -DeviceId emulator-5554
#>
[CmdletBinding()]
param(
    [string]$BackendHost,
    [int]$BackendPort = 5050,
    [string]$DeviceId = "RZ8NB1FRMRF"
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

if (-not $BackendHost) {
    $BackendHost = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.InterfaceAlias -match 'Wi-?Fi' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.IPAddress -notlike '127.*'
        } |
        Select-Object -First 1).IPAddress
}

if (-not $BackendHost) {
    throw "Could not auto-detect a Wi-Fi IPv4 address. Pass -BackendHost <ip> explicitly."
}

$baseUrl = "http://${BackendHost}:${BackendPort}"

Write-Host ""
Write-Host "RoadResQ device run" -ForegroundColor Cyan
Write-Host "  device  : $DeviceId"
Write-Host "  backend : $baseUrl"
Write-Host ""

# Warn, but do not block - the app may still be useful off-backend.
try {
    Invoke-WebRequest -Uri "$baseUrl/health" -UseBasicParsing -TimeoutSec 5 | Out-Null
    Write-Host "  backend health : OK" -ForegroundColor Green
}
catch {
    Write-Host "  backend health : UNREACHABLE" -ForegroundColor Yellow
    Write-Host "  start it with  : .\.venv\Scripts\python.exe backend\roadresq_backend.py" -ForegroundColor Yellow
}
Write-Host ""

flutter run -d $DeviceId "--dart-define=ROADRESQ_HOST=$baseUrl"
