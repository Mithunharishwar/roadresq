<#
.SYNOPSIS
    Supervise the RoadResQ backend for the life of the login session.

.DESCRIPTION
    WHY THIS EXISTS

    Registering a Windows scheduled task needs administrator rights, and this
    machine runs as a standard user ("Access is denied"). The backend therefore
    had no supervision at all: when it stopped, the phone spent the day printing

        SocketException: No route to host (OS Error 113)

    This agent starts the backend and then checks it every minute, for the whole
    session. It is launched from the Startup folder by a hidden shortcut (see
    install_backend_service.ps1), so no console window appears and no elevation
    is required.

    A named mutex keeps exactly one agent alive: two agents would race each other
    restarting the server.

.EXAMPLE
    .\backend_agent.ps1
#>
[CmdletBinding()]
param(
    [int]$IntervalSeconds = 60,
    [string]$HealthUrl = 'http://127.0.0.1:5050/health'
)

$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot

$logDir = Join-Path $PSScriptRoot 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logPath = Join-Path $logDir 'agent.log'

function Write-AgentLog([string]$Message) {
    if ((Test-Path $logPath) -and ((Get-Item $logPath).Length -gt 512KB)) {
        Move-Item -Path $logPath -Destination "$logPath.1" -Force
    }
    Add-Content -Path $logPath -Encoding UTF8 -Value (
        "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    )
}

# ── single instance ─────────────────────────────────────────────────────────
$mutex = New-Object System.Threading.Mutex($false, 'Local\RoadResQBackendAgent')
$hasHandle = $false
try {
    $hasHandle = $mutex.WaitOne(0, $false)
} catch [System.Threading.AbandonedMutexException] {
    $hasHandle = $true
}
if (-not $hasHandle) {
    Write-AgentLog 'another agent already running - exiting'
    return
}

function Test-Backend {
    try {
        $response = Invoke-WebRequest -Uri $HealthUrl -TimeoutSec 4 -UseBasicParsing
        return ($response.StatusCode -eq 200 -and $response.Content -match 'healthy')
    } catch {
        return $false
    }
}

Write-AgentLog "agent started (pid $PID, interval ${IntervalSeconds}s)"

while ($true) {
    try {
        if (-not (Test-Backend)) {
            Write-AgentLog 'backend down - starting it'
            $output = & (Join-Path $PSScriptRoot 'start_backend.ps1') 2>&1 | Out-String
            Write-AgentLog ($output.Trim() -replace "`r`n", ' | ')
        }
    } catch {
        Write-AgentLog "restart attempt failed: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $IntervalSeconds
}
