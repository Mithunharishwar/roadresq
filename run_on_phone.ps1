<#
.SYNOPSIS
    Run RoadResQ on the attached Android phone with a working backend host.

.DESCRIPTION
    Two failure modes produced the misleading terminal output this replaces:

      1. `adb.exe: device offline`
         `flutter run` binds a 3-5 minute Gradle build to a single install
         moment. If the phone sleeps or the USB link blips during the build,
         the build succeeds and the install dies. Fix: keep the screen awake
         while charging, and fail fast with one message if the device is not
         in the `device` state before anything is compiled.

      2. `[socket] connect error: timeout` in logcat, empty backend log
         A build without --dart-define=ROADRESQ_HOST resolves to
         http://10.0.2.2:5050 (the Android EMULATOR alias), which is
         unroutable on real hardware. Fix: pass the PC's current LAN address
         explicitly, detected here at run time instead of hardcoded.

    The script therefore: restarts adb, waits for a real `device` state, keeps
    the phone awake, ensures the backend answers /health, then runs Flutter with
    the correct --dart-define. Nothing is compiled until the device is ready.

.PARAMETER Serial
    Device serial. Defaults to the first authorized device.

.PARAMETER HostIp
    Backend LAN address to compile in. Defaults to the PC's primary IPv4.

.PARAMETER Port
    Backend port. Defaults to 5050.

.PARAMETER Diagnose
    Print the diagnosis only; do not build or launch.

.PARAMETER TimeoutSeconds
    How long to wait for the device. Defaults to 120.

.EXAMPLE
    .\run_on_phone.ps1
    .\run_on_phone.ps1 -Diagnose
    .\run_on_phone.ps1 -HostIp 192.168.1.20
#>
[CmdletBinding()]
param(
    [string]$Serial,
    [string]$HostIp,
    [int]$Port = 5050,
    [switch]$Diagnose,
    [int]$TimeoutSeconds = 120
)

# adb writes its daemon banner to stderr; PowerShell turns that into a
# terminating error under 'Stop'. Handle failures explicitly instead.
$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot

function Invoke-Adb {
    param([string[]]$AdbArgs)
    return (& adb @AdbArgs 2>$null)
}

function Get-AdbLines {
    (& adb devices 2>$null) | Where-Object { $_ -match '^\S+\s+(device|offline|unauthorized|recovery|sideload)$' }
}

function Write-State($state, $serial) {
    switch ($state) {
        'device'       { Write-Host "  $serial : ready" -ForegroundColor Green }
        'unauthorized' { Write-Host "  $serial : UNAUTHORIZED - unlock the phone and tap Allow ('Always allow from this computer')" -ForegroundColor Yellow }
        'offline'      { Write-Host "  $serial : OFFLINE - adbd is not answering (USB debugging off, screen locked, or bad cable)" -ForegroundColor Yellow }
        default        { Write-Host "  $serial : $state" -ForegroundColor Yellow }
    }
}

function Get-LanIp {
    $candidates = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.PrefixOrigin -ne 'WellKnown' }
    $routed = $candidates | Where-Object {
        (Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue).InterfaceIndex -contains $_.InterfaceIndex
    }
    $pick = if ($routed) { $routed | Select-Object -First 1 } else { $candidates | Select-Object -First 1 }
    if ($pick) { return $pick.IPAddress }
    return $null
}

# ── 1. adb + device ──────────────────────────────────────────────────────────
# Never kill the server here. `adb kill-server` leaves this phone's USB endpoint
# in a state where Windows stops enumerating it entirely ("device not found"),
# which is strictly worse than the offline state we came to fix. Only start the
# server when no daemon is running.
Write-Host "Checking adb server..." -ForegroundColor Cyan
$daemonUp = $false
try {
    $version = (& adb version 2>$null) -join ' '
    $daemonUp = ($version -match 'Android Debug Bridge version')
} catch { $daemonUp = $false }

if (-not $daemonUp) {
    Invoke-Adb @('start-server') | Out-Null
    Start-Sleep -Seconds 2
} else {
    Write-Host "  adb daemon already running - leaving it alone" -ForegroundColor DarkGray
}

if (-not $Serial) {
    $existing = Get-AdbLines | Where-Object { $_ -match '\soffline$' }
    foreach ($line in $existing) {
        $s = ($line -split '\s+')[0]
        Write-Host "  kicking offline transport $s" -ForegroundColor DarkGray
        Invoke-Adb @('-s', $s, 'reconnect', 'offline') | Out-Null
    }
}

if ($Serial) { Invoke-Adb @('-s', $Serial, 'reconnect', 'offline') | Out-Null }

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$ready = $null
$lastState = $null

while ((Get-Date) -lt $deadline) {
    $lines = Get-AdbLines
    if ($Serial) {
        $target = $lines | Where-Object { $_ -match "^$([regex]::Escape($Serial))\s" } | Select-Object -First 1
    } else {
        $target = $lines | Where-Object { $_ -match '\sdevice$' } | Select-Object -First 1
    }

    if ($target) {
        $parts = $target -split '\s+'
        $state = $parts[1]
        $name  = $parts[0]
    } else {
        $state = 'none'
        $name  = $null
    }

    if ($state -ne $lastState) {
        if ($state -eq 'none') { Write-Host "  no device seen - check the USB cable/port" -ForegroundColor Yellow }
        else { Write-State $state $name }
        $lastState = $state
    }

    if ($state -eq 'device') { $ready = $name; break }
    if ($state -eq 'offline' -and $name) { Invoke-Adb @('-s', $name, 'reconnect', 'offline') | Out-Null }
    Start-Sleep -Seconds 2
}

if (-not $ready) {
    Write-Host ""
    Write-Host "Device never reached the 'device' state - nothing was built." -ForegroundColor Red
    Write-Host "Fix on the phone, then re-run:" -ForegroundColor Yellow
    Write-Host "  1. Unlock the screen; Developer options > Stay awake = ON."
    Write-Host "  2. Settings > Developer options > USB debugging = ON."
    Write-Host "  3. Unplug/replug, choose 'File transfer / Android Auto'."
    Write-Host "  4. Tap Allow on 'Allow USB debugging?' and tick 'Always allow from this computer'."
    Write-Host "  5. Still offline? Revoke USB debugging authorizations, then replug."
    Write-Host "  6. Still offline? Try another cable and a rear USB port directly on the PC."
    exit 1
}

# ── 2. keep the phone from sleeping mid-build ────────────────────────────────
Invoke-Adb @('-s', $ready, 'shell', 'svc', 'power', 'stayon', 'true') | Out-Null

# ── 2b. USB fallback for the backend ─────────────────────────────────────────
# `adb reverse` publishes the PC's port 5050 on the phone's own loopback. The
# app already tries 127.0.0.1:5050 during discovery, so this keeps it working
# even on a Wi-Fi network that blocks phone -> PC traffic (campus/corporate APs
# with client isolation), where no amount of retrying the LAN address helps.
Invoke-Adb @('-s', $ready, 'reverse', "tcp:$Port", "tcp:$Port") | Out-Null
Write-Host "USB port forward: phone 127.0.0.1:$Port -> PC $Port" -ForegroundColor DarkGray

# ── 3. backend reachable from the phone ──────────────────────────────────────
if (-not $HostIp) { $HostIp = Get-LanIp }
if (-not $HostIp) {
    Write-Host "Could not determine the PC's LAN address. Pass -HostIp <address>." -ForegroundColor Red
    exit 1
}
$backendUrl = "http://${HostIp}:$Port"

Write-Host ""
Write-Host "Device : $ready ($(Invoke-Adb @('-s', $ready, 'shell', 'getprop', 'ro.product.model')))"
Write-Host "Backend: $backendUrl"

$healthy = $false
try {
    $resp = Invoke-WebRequest -Uri "$backendUrl/health" -UseBasicParsing -TimeoutSec 4
    $healthy = ($resp.StatusCode -eq 200)
} catch { $healthy = $false }

if (-not $healthy) {
    Write-Host "Backend not answering - starting it..." -ForegroundColor Yellow
    & "$PSScriptRoot\start_backend.ps1" -Port $Port | Out-Null
    try {
        $resp = Invoke-WebRequest -Uri "$backendUrl/health" -UseBasicParsing -TimeoutSec 6
        $healthy = ($resp.StatusCode -eq 200)
    } catch { $healthy = $false }
}

if (-not $healthy) {
    Write-Host "Backend still not healthy on $backendUrl - fix that first." -ForegroundColor Red
    exit 1
}
Write-Host "Backend: healthy" -ForegroundColor Green

# The phone must reach the PC over LAN; ICMP is often blocked while TCP is fine,
# so probe the actual endpoint from the device shell rather than pinging.
$probe = (Invoke-Adb @('-s', $ready, 'shell', 'curl', '-s', '-m', '4', "$backendUrl/health")) -join ' '
if ($probe -notmatch 'healthy') {
    # The LAN path is blocked. This is common on campus/corporate Wi-Fi with
    # client isolation, and it is not fixable from the PC. The USB forward set
    # up above is a complete substitute, so use it instead of aborting a build
    # the user is waiting for.
    $usbUrl = "http://127.0.0.1:$Port"
    $usbProbe = (Invoke-Adb @('-s', $ready, 'shell', 'curl', '-s', '-m', '4', "$usbUrl/health")) -join ' '
    if ($usbProbe -match 'healthy') {
        Write-Host "Phone cannot reach $backendUrl over Wi-Fi (blocked by the network)." -ForegroundColor Yellow
        Write-Host "Using the USB forward instead: $usbUrl" -ForegroundColor Green
        $backendUrl = $usbUrl
    } else {
        Write-Host "Phone cannot reach the backend over Wi-Fi or USB." -ForegroundColor Red
        Write-Host "  LAN probe: $probe" -ForegroundColor DarkGray
        Write-Host "  USB probe: $usbProbe" -ForegroundColor DarkGray
        Write-Host "  Check: .\start_backend.ps1 -Restart, and the USB cable is connected." -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "Phone -> backend: reachable" -ForegroundColor Green
}

if ($Diagnose) { exit 0 }

# ── 4. build with the host compiled in, then launch ──────────────────────────
# The define is now only a starting hint: the app probes it, and when it does not
# answer it finds the backend itself (beacon / subnet sweep) and moves both REST
# and Socket.IO onto the address it found. That is what stops a new DHCP lease
# from turning into a day of "SocketException: No route to host".
Write-Host ""
Write-Host "Running app with --dart-define=ROADRESQ_HOST=$backendUrl ..." -ForegroundColor Cyan
Write-Host "(the app will re-discover the backend automatically if this address changes)"
flutter run -d $ready "--dart-define=ROADRESQ_HOST=$backendUrl"
