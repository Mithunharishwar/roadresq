# RoadResQ — Socket.IO connection failure: root cause and fix

Date: 2026-10-08
Scope: `lib/` only. **The `functions/` (Cloud Functions) module was not touched.**

---

## 1. What was wrong

The Flutter app could **never** open a realtime connection. It was not
intermittent and not a network problem — every single attempt failed, and the
client retried forever, which is what surfaced as "socket connection error
occurring frequently".

### Measured, before the fix

`tool/socket_probe.dart` drives the real `socket_io_client` 2.0.3+1 with the
same option map the app built:

```
MODE=app  HOST=http://192.168.31.206:5050  transports=[polling]
[   0.054s] SOCKET CONNECT_ERROR  WebSocketException: Connection to
            'http://192.168.31.206:5050/socket.io/?EIO=4&transport=polling#'
            was not upgraded to websocket, HTTP status code: 200
...
================ SUMMARY (mode=app) ================
socket connects           : 0
socket connect_errors     : 4
manager reconnect attempts: 3
final connected           : false
```

0 connects. 4 connect errors. 3 retries. In 12 seconds.

### The root cause

A three-step mismatch inside `socket_io_client` on the Dart VM
(which is every Flutter Android/iOS build):

1. `AppConfig.socketTransports` listed **`polling` first**, and engine.io writes
   the *first* entry into the handshake query:

   ```dart
   // socket_io_client/lib/src/engine/socket.dart  (createTransport)
   query['transport'] = name;          // name = transports[0] = 'polling'
   var transport = Transports.newInstance(name, {...});
   ```

2. On the Dart VM the transport factory **ignores that name** and always
   returns a WebSocket transport:

   ```dart
   // socket_io_client/lib/src/engine/transport/io_transports.dart
   static Transport newInstance(String name, options) {
     // only support websocket here.
     return IOWebSocketTransport(options);
   }
   ```

3. So the client opened a **WebSocket to a URL that said `transport=polling`**.
   The server read it as a plain long-poll GET and answered **HTTP 200**
   instead of the **101 Switching Protocols** a WebSocket handshake requires.
   `dart:io` raised the `WebSocketException` above.

Listing `polling` first is therefore not a harmless preference — it is what
broke the connection. `polling` is also not usable on this client at all,
because the factory cannot produce a polling transport on the VM.

The server was never at fault. Its handshake correctly advertises WebSocket:

```
GET /socket.io/?EIO=4&transport=polling
0{"sid":"DK6-P_WZvBCvaDuDAAAA","upgrades":["websocket"],
  "pingTimeout":20000,"pingInterval":25000,"maxPayload":1000000}
```

---

## 2. Fixes applied

### 2.1 The connection failure (fatal)

`lib/core/config/app_config.dart` — `socketTransports` is now
`['websocket']`, with the full chain documented in place so it cannot be
"tidied" back to `polling`.

Verified after the fix (`tool/socket_probe.dart wsonly`, 150 s):

```
================ SUMMARY (mode=wsonly) ================
socket connects           : 1
socket disconnects        : 0
socket connect_errors     : 0
manager reconnect attempts: 0
engine errors             : 0
longest continuous uptime : 149s
final connected           : true
final transport           : websocket
```

Connection established in **~85 ms**; 49 location round-trips delivered.
1 connect, 0 errors, 149 s continuous.

### 2.2 Connect thrash (would have caused dropouts after the fix)

`connect()` disposed and rebuilt the socket whenever it ran while the socket
was not connected. Every screen calls `connect()` from `initState`, so any
navigation during a handshake or a reconnect destroyed a live or in-flight
connection and started over.

`lib/services/socket_service.dart` — `connect()` is now idempotent: it reuses
the existing socket and lets `socket_io_client`'s own manager own reconnection.
`reconnectionAttempts` is no longer pinned to `20` (the library default is
infinity), so the socket can no longer give up permanently and require an app
restart.

### 2.3 Shared-listener clobbering (would have silently killed live updates)

All screens registered handlers directly on the shared socket, and **any** one
screen's `dispose()` called `SocketService.clearAllListeners()`, removing
*every* screen's handlers app-wide. `request_location_screen` did this while
registering no listeners of its own, and `LiveTrackingService.stopTracking()`
did the same on every tracking stop.

`lib/services/socket_service.dart` — listeners are now owned by a
`SocketSubscription` handle; cancelling one never disturbs another. The service
attaches exactly one fan-out handler per event, so registrations can no longer
accumulate duplicates.

Updated call sites:

| File | Change |
|---|---|
| `lib/screens/mechanic_home_screen.dart` | 4 listeners + offline listener scoped |
| `lib/screens/assistant_home_screen.dart` | 3 listeners + offline listener scoped |
| `lib/screens/admin_dashboard_page.dart` | 9 listeners + offline listener scoped |
| `lib/screens/user_tracking_screen.dart` | 6 listeners scoped |
| `lib/screens/request_status_screen.dart` | 6 listeners scoped |
| `lib/screens/request_location_screen.dart` | removed the app-wide clear |
| `lib/services/live_tracking_service.dart` | 3 listeners scoped |
| `lib/services/crew_job_service.dart` | job-request listeners now cancellable |

### 2.4 Lost emits

`emit()` returned early while the socket was down, which defeated
`socket_io_client`'s own `sendBuffer` replay. A command emitted immediately
after `connect()` — `crew_online`, or `accept_request` during a blip — was
dropped with no error. `emit()` now hands the packet to the library so it is
replayed on connect, except for position samples (`update_location` and
friends), which are deliberately dropped when down because a stale position is
worthless.

### 2.5 Dead retry timer

The old 20-second retry timer checked `_isConnecting`, which `onConnectError`
had already set to `false`, so it could never fire and no automatic retry ever
happened on error. It is replaced by a 15-second offline watchdog that actually
drives the screens' "Backend offline" SnackBar — which previously never
appeared.

---

## 3. Verification

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found!** (5.5s) |
| Real service vs. live backend | `flutter test test/socket_service_test.dart` | **All tests passed!** (5/5) |
| Probe, old config | `dart run tool/socket_probe.dart app ... 12` | 0 connects, 4 connect errors |
| Probe, new config | `dart run tool/socket_probe.dart wsonly ... 150` | 1 connect, 0 errors, 149s uptime |
| Backend terminal | scan of backend stdout/stderr | 0 Traceback / ERROR / Exception / 500 |

`test/socket_service_test.dart` exercises the **real** `SocketService`, not a
replica, and asserts:

1. the configured transports put `websocket` first;
2. it connects and stays connected over a `websocket` transport;
3. five repeated `connect()` calls reuse the same live socket object;
4. cancelling one subscription leaves the other subscriber receiving events
   (full client → server → client round trip);
5. `clearAllListeners()` stops delivery app-wide.

---

## 4. Still open (unchanged by this work)

- **The backend was not running when this work started** (nothing was listening
  on 5050). It is running now on pid `4940`, bound to `0.0.0.0:5050`.
- The app must be **rebuilt**: this fix is Dart code, so a running APK will not
  pick it up. The LAN host still has to be supplied at build time:
  `flutter run --dart-define=ROADRESQ_HOST=http://192.168.31.206:5050`
- Cloud Functions / billing / SHA-1 registration / SMS provider — all still as
  reported previously, and untouched here.

---

## 5. Update 2026-11-05 — the *recurring* socket error (root cause found)

The 2026-10-08 fixes above were real, but they addressed why a *transport* could
not connect. The error the user saw **every day** was a different failure:

```text
[socket] connect error: SocketException: No route to host
(OS Error: No route to host, errno = 113), address = 10.11.189.61
```

Captured from the attached phone with `adb logcat`. Three facts, measured:

| Fact | Evidence |
|---|---|
| The phone was dialling `10.11.189.61` | logcat, 64 reconnect attempts in a row |
| The PC is now `10.11.93.48` | `Get-NetIPAddress` (Wi-Fi, `eec.edu`) |
| The backend was healthy the whole time | `GET /health` → `{"success": true}` from both the PC and the phone |

So the app was not failing to speak Socket.IO — it was dialling a machine that
no longer exists on the network. `errno 113` is the kernel saying "no route to
that host", not a protocol error.

**Why it came back every day:** the address was fixed at build time
(`run_on_phone.ps1` compiled in the PC's then-current LAN IP). A DHCP lease
renewal, a reboot, or a different Wi-Fi network invalidates it permanently.
"Fixing" it meant recompiling with a new IP — which is why the same complaint
returned the next day.

Two secondary defects kept it alive:

1. `SocketService.setSocketHost()` changed `AppConfig` but never rebuilt the
   socket. The REST calls moved to a new address, the socket kept dialling the
   old one, until the app was restarted.
2. `start_backend.ps1` aborted (`Set-Content` on a log file still held open by
   the previous server) whenever the old process had not exited, leaving no
   server running — indistinguishable, from the phone, from a socket fault.

### The fix — discovery instead of a compiled-in IP

- `lib/services/backend_discovery.dart` (new): finds the backend at runtime.
  1. probe the known addresses (current / saved / build-time / emulator /
     `adb reverse` loopback),
  2. listen for the backend's UDP beacon on port 5051,
  3. bounded sweep of the local subnet for `/health`.
  The winner is adopted by `AppConfig`, so REST and Socket.IO move together and
  the address is remembered across restarts.
- `backend/beacon.py` (new): broadcasts
  `{"service":"roadresq","port":5050,...}` every 2 s; started by the backend.
- `SocketService`: `retarget()` rebuilds the connection when the address changes
  (listeners are preserved); after 3 consecutive connect errors it runs
  discovery itself, so a stale address self-heals without a rebuild or a restart.
- Log throttling: three stack traces per second became 1 log line, then a sample
  every 15 attempts. The terminal is readable during an outage.
- `start_backend.ps1`: detects the real interpreter behind the venv shim,
  waits for the port to be released, survives locked log files, restarts a
  half-dead server, and prints the current LAN URLs.
- `run_on_phone.ps1`: sets `adb reverse tcp:5050 tcp:5050` and falls back to the
  USB loopback when the Wi-Fi network blocks phone → PC traffic.

### Verification

| Check | Result |
|---|---|
| `flutter analyze lib` | No issues found |
| `GET /health` from the phone over LAN | `{"success":true}` |
| UDP beacon received | `{"service": "roadresq", "port": 5050, ...}` from `10.11.93.48` |
| App built with the *dead* address `10.11.189.61` | connects to the discovered address, 0 `No route to host` |
