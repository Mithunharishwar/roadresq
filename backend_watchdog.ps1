<#
.SYNOPSIS
    Keep the RoadResQ backend alive.

.DESCRIPTION
    WHY THIS EXISTS

    The phone's "socket error" that kept coming back was, twice over, simply the
    backend not running: after a reboot, after a crash, after a logged-off
    session. The app retries forever and the terminal fills with

        SocketException: No route to host (OS Error 113)

    while the actual fault is a server that is not up. Nothing in the client can
    fix that.

    This script is the server side of the answer: if /health does not answer, it
    starts the backend. Run it from Task Scheduler every few minutes (see
    install_backend_service.ps1) and the server survives reboots, crashes and
    logoffs without anyone running a command.

.EXAMPLE
    .\backend_watchdog.ps1
#>
[CmdletBinding()]
param(
    [string]$HealthUrl = 'http://127.0.0.1:5050/health',
    [string]$LogPath = (Join-Path $PSScriptRoot 'logs\watchdog.log')
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$logDir = Split-Path -Parent $LogPath
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# Keep the log bounded: a watchdog that runs every 5 minutes forever must not
# grow an unbounded file on the user's disk.
if ((Test-Path $LogPath) -and ((Get-Item $LogPath).Length -gt 512KB)) {
    Move-Item -Path $LogPath -Destination "$LogPath.1" -Force
}

function Write-WatchdogLog([string]$Message) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

function Test-Backend {
    try {
        $response = Invoke-WebRequest -Uri $HealthUrl -TimeoutSec 4 -UseBasicParsing
        return ($response.StatusCode -eq 200 -and $response.Content -match 'healthy')
    } catch {
        return $false
    }
}

if (Test-Backend) {
    # Healthy. Stay quiet unless something interesting happened recently.
    exit 0
}

Write-WatchdogLog 'health check failed - starting backend'

try {
    $output = & (Join-Path $PSScriptRoot 'start_backend.ps1') 2>&1 | Out-String
    Write-WatchdogLog ($output.Trim() -replace "`r`n", ' | ')
} catch {
    Write-WatchdogLog "start failed: $($_.Exception.Message)"
    exit 1
}

Start-Sleep -Seconds 3
if (Test-Backend) {
    Write-WatchdogLog 'backend is healthy again'
    exit 0
}

Write-WatchdogLog 'backend still unhealthy after start'
exit 1
