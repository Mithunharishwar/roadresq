<#
.SYNOPSIS
    Make the RoadResQ backend start at logon and stay running.

.DESCRIPTION
    WHY THIS EXISTS

    Every recurrence of "the socket error is back" ended at the same root: the
    backend process was not running. It only ever ran because someone typed
    .\start_backend.ps1, so a reboot, a crash or a logoff took the app offline
    for the rest of the day and the terminal filled with

        SocketException: No route to host (OS Error 113)

    Two ways to fix that, tried in order:

      1. Windows scheduled tasks (at logon + a repeating watchdog). Needs admin.
      2. Startup-folder shortcut running backend_agent.ps1 hidden. Works as a
         standard user, which is the case on this machine.

    Either path starts the server now, so the phone has something to connect to
    immediately. Re-running the script is safe; it replaces what it installed.

.PARAMETER Uninstall
    Remove the startup entry and stop the backend.

.EXAMPLE
    .\install_backend_service.ps1
#>
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [int]$IntervalMinutes = 5,
    [int]$AgentIntervalSeconds = 60
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$startTask = 'RoadResQ Backend'
$watchTask = 'RoadResQ Backend Watchdog'
$startScript = Join-Path $PSScriptRoot 'start_backend.ps1'
$agentScript = Join-Path $PSScriptRoot 'backend_agent.ps1'

$startupDir = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupDir 'RoadResQ Backend.lnk'

function Remove-TaskIfExists([string]$Name) {
    $existing = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($existing) {
        try {
            Unregister-ScheduledTask -TaskName $Name -Confirm:$false
            Write-Host "  removed task: $Name" -ForegroundColor DarkGray
        } catch {
            Write-Host "  could not remove task $Name (needs admin)" -ForegroundColor DarkYellow
        }
    }
}

function Remove-StartupShortcut {
    if (Test-Path $shortcutPath) {
        Remove-Item $shortcutPath -Force
        Write-Host "  removed startup entry" -ForegroundColor DarkGray
    }
}

function Test-Backend {
    try {
        $response = Invoke-WebRequest -Uri 'http://127.0.0.1:5050/health' -TimeoutSec 4 -UseBasicParsing
        return ($response.StatusCode -eq 200 -and $response.Content -match 'healthy')
    } catch { return $false }
}

function Get-AgentProcesses {
    # pwsh.exe on this machine, powershell.exe on a stock Windows install.
    Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -in @('powershell.exe', 'pwsh.exe') -and
            $_.CommandLine -like '*backend_agent.ps1*'
        }
}

if ($Uninstall) {
    Remove-StartupShortcut
    Remove-TaskIfExists $watchTask
    Remove-TaskIfExists $startTask
    Get-AgentProcesses | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
    & $startScript -Stop | Out-Null
    Write-Host "RoadResQ auto-start removed and backend stopped." -ForegroundColor Yellow
    return
}

if (-not (Test-Path $startScript)) { throw "Missing $startScript" }
if (-not (Test-Path $agentScript)) { throw "Missing $agentScript" }

$psExe = (Get-Process -Id $PID).Path
if (-not $psExe) { $psExe = 'powershell.exe' }

# ── Path 1: scheduled tasks (needs admin) ───────────────────────────────────
$taskRegistered = $false
try {
    Remove-TaskIfExists $startTask
    Remove-TaskIfExists $watchTask

    $startAction = New-ScheduledTaskAction -Execute $psExe `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startScript`"" `
        -WorkingDirectory $PSScriptRoot
    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn
    $startSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName $startTask -Action $startAction `
        -Trigger $logonTrigger -Settings $startSettings `
        -Description 'Starts the RoadResQ backend when the user logs in.' -ErrorAction Stop | Out-Null

    $watchAction = New-ScheduledTaskAction -Execute $psExe `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$agentScript`"" `
        -WorkingDirectory $PSScriptRoot
    $watchTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
        -RepetitionDuration ([TimeSpan]::FromDays(3650))
    $watchSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $watchTask -Action $watchAction `
        -Trigger $watchTrigger -Settings $watchSettings `
        -Description 'Restarts the RoadResQ backend if /health stops answering.' -ErrorAction Stop | Out-Null

    # A non-terminating error still returns here, so confirm the tasks exist.
    $taskRegistered = [bool](Get-ScheduledTask -TaskName $startTask -ErrorAction SilentlyContinue)
    Remove-StartupShortcut
    Write-Host "  registered scheduled tasks" -ForegroundColor Green
} catch {
    Write-Host "  scheduled tasks unavailable: $($_.Exception.Message)" -ForegroundColor DarkYellow
    Write-Host "  falling back to the Startup folder (no admin needed)" -ForegroundColor DarkYellow
}

# ── Path 2: Startup shortcut + supervising agent (standard user) ────────────
if (-not $taskRegistered) {
    if (-not (Test-Path $startupDir)) {
        New-Item -ItemType Directory -Path $startupDir -Force | Out-Null
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $psExe
    $shortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$agentScript`" -IntervalSeconds $AgentIntervalSeconds"
    $shortcut.WorkingDirectory = $PSScriptRoot
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'Starts and supervises the RoadResQ backend.'
    $shortcut.Save()
    Write-Host "  installed startup entry: $shortcutPath" -ForegroundColor Green

    if (-not (Get-AgentProcesses)) {
        Start-Process -FilePath $psExe `
            -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$agentScript`" -IntervalSeconds $AgentIntervalSeconds" `
            -WindowStyle Hidden | Out-Null
        Write-Host "  agent started" -ForegroundColor Green
    } else {
        Write-Host "  agent already running" -ForegroundColor DarkGray
    }
}

# ── Make sure it is up right now ────────────────────────────────────────────
if (-not (Test-Backend)) { & $startScript | Out-Null }
Start-Sleep -Seconds 1

Write-Host ""
if (Test-Backend) {
    Write-Host "RoadResQ backend is running and will restart itself." -ForegroundColor Cyan
} else {
    Write-Host "Backend did not answer /health - check logs\backend_stderr.log" -ForegroundColor Red
}
Write-Host "  health : http://127.0.0.1:5050/health"
Write-Host "  logs   : logs\agent.log"
Write-Host "  remove : .\install_backend_service.ps1 -Uninstall"
