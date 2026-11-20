<#
.SYNOPSIS
    Start (or stop) the RoadResQ Flask backend as a detached process.

.DESCRIPTION
    The backend is a long-running server, so it must not be tied to the lifetime
    of whatever terminal launched it.

    This script is written to be the one command that always leaves a working
    server behind, because its failure mode was indistinguishable from the app's
    "socket error": the phone retries a port nothing is listening on, and the
    terminal only shows the client side.

    Three things it now handles, each of which previously left no server running:

      1. A stale instance. `python.exe` in the venv is a launcher shim that
         spawns the real interpreter, so the PID holding port 5050 is not the
         one the venv advertises. Detection is therefore done by TCP connect and
         by command line, not by image name or a single PID.
      2. Locked log files. The previous run's stdout/stderr redirect stays open
         while that process lives, and `Set-Content` on a locked file threw,
         aborting the start under `$ErrorActionPreference = "Stop"`. Logs are
         now opened defensively.
      3. A port that answers TCP but not /health (half-dead server). That is
         restarted rather than reported as healthy.

.PARAMETER Port
    Backend port. Defaults to 5050 (AppConfig.backendPort).

.PARAMETER Stop
    Stop every RoadResQ backend process instead of starting one.

.PARAMETER Restart
    Stop, then start. Use after changing backend code.

.EXAMPLE
    .\start_backend.ps1
    .\start_backend.ps1 -Restart
    .\start_backend.ps1 -Stop
#>
[CmdletBinding()]
param(
    [int]$Port = 5050,
    [switch]$Stop,
    [switch]$Restart
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

$python = Join-Path $PSScriptRoot "backend\.venv\Scripts\python.exe"
$script = Join-Path $PSScriptRoot "backend\roadresq_backend.py"
$logDir = Join-Path $PSScriptRoot "logs"
$outLog = Join-Path $logDir "backend_stdout.log"
$errLog = Join-Path $logDir "backend_stderr.log"

function Get-BackendProcesses {
    <# Every process running the backend entry point, including the venv shim
       and the real interpreter it spawns. #>
    Get-CimInstance Win32_Process -Filter "Name like 'python%'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*roadresq_backend.py*" }
}

function Test-BackendPort {
    param([int]$TimeoutMs = 800)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync("127.0.0.1", $Port)
        if (-not $task.Wait($TimeoutMs)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Test-BackendHealth {
    param([int]$TimeoutSec = 3)
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec $TimeoutSec
        return ($r.success -eq $true)
    } catch {
        return $false
    }
}

function Stop-Backend {
    $procs = @(Get-BackendProcesses)
    $portOwner = (Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty OwningProcess)

    if ($procs.Count -eq 0 -and -not $portOwner) {
        Write-Host "Nothing is running on port $Port." -ForegroundColor Yellow
        return
    }

    foreach ($p in $procs) {
        Write-Host "  stopping pid $($p.ProcessId)"
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    if ($portOwner -and ($procs.ProcessId -notcontains $portOwner)) {
        Write-Host "  stopping port owner pid $portOwner"
        Stop-Process -Id $portOwner -Force -ErrorAction SilentlyContinue
    }

    # Wait for the socket to be released, so the next bind cannot hit
    # "address already in use" and die on startup.
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-BackendPort -TimeoutMs 300)) { break }
        Start-Sleep -Milliseconds 300
    }
    Write-Host "Backend stopped." -ForegroundColor Green
}

# ── Stop / restart ───────────────────────────────────────────────────────────
if ($Stop) {
    Stop-Backend
    return
}

if ($Restart) {
    Stop-Backend
}

# ── Already running ──────────────────────────────────────────────────────────
if (Test-BackendPort) {
    if (Test-BackendHealth) {
        $owner = (Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty OwningProcess)
        Write-Host "Backend already healthy on port $Port (pid $owner)." -ForegroundColor Green
        Write-Host "  restart : .\start_backend.ps1 -Restart"
        Write-Host "  stop    : .\start_backend.ps1 -Stop"
        return
    }
    Write-Host "Port $Port is held but /health does not answer — restarting." -ForegroundColor Yellow
    Stop-Backend
}

if (-not (Test-Path $python)) {
    throw "Python venv not found: $python. Create it with: python -m venv backend\.venv"
}
if (-not (Test-Path $script)) {
    throw "Backend entry point not found: $script"
}

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# Truncate previous logs so a stale error cannot be mistaken for a new one.
# A file still held open by a dying process must not abort the start — that is
# exactly how the server ended up not running while the app showed socket errors.
function Reset-LogFile {
    param([string]$Path, [string]$FallbackName)
    try {
        Set-Content -Path $Path -Value "" -Encoding UTF8 -ErrorAction Stop
        return $Path
    } catch {
        $alt = Join-Path $logDir ("{0}-{1}.log" -f $FallbackName, (Get-Date -Format "yyyyMMdd-HHmmss"))
        Set-Content -Path $alt -Value "" -Encoding UTF8
        return $alt
    }
}
$outLog = Reset-LogFile -Path $outLog -FallbackName "backend_stdout"
$errLog = Reset-LogFile -Path $errLog -FallbackName "backend_stderr"

# ── Start ────────────────────────────────────────────────────────────────────
Start-Process -FilePath $python `
    -ArgumentList $script `
    -WorkingDirectory $PSScriptRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput $outLog `
    -RedirectStandardError $errLog

# ── Wait for /health ─────────────────────────────────────────────────────────
$deadline = (Get-Date).AddSeconds(30)
$healthy = $false
$lastError = $null

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 750
    if (Test-BackendHealth -TimeoutSec 2) { $healthy = $true; break }
    if (-not (Test-BackendPort -TimeoutMs 300)) {
        # Not listening yet; keep waiting briefly, but fail fast if the process
        # is gone rather than sitting out the whole deadline.
        if (@(Get-BackendProcesses).Count -eq 0) { break }
    }
}

if ($healthy) {
    $owner = (Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty OwningProcess)
    Write-Host ""
    Write-Host "RoadResQ backend running" -ForegroundColor Cyan
    Write-Host "  port   : $Port (pid $owner)"
    Write-Host "  health : OK"
    Write-Host "  logs   : $errLog"
    Write-Host "  stop   : .\start_backend.ps1 -Stop"
    Write-Host ""
    Write-Host "LAN addresses (the app also discovers these automatically):" -ForegroundColor Cyan
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
        ForEach-Object { Write-Host "  http://$($_.IPAddress):$Port" }
    Write-Host ""
} else {
    Write-Host "Backend did not answer /health on port $Port." -ForegroundColor Red
    if ($lastError) { Write-Host "  last error : $lastError" -ForegroundColor Red }
    if (Test-Path $errLog) {
        Write-Host "  --- stderr (tail) ---" -ForegroundColor Yellow
        Get-Content $errLog -Tail 30
    }
    exit 1
}
