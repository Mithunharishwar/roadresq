// Socket.IO reliability probe.
//
// Purpose: measure FLUTTER-SIDE Socket.IO stability against the running
// RoadResQ backend, using the same `socket_io_client` library and the same
// option map that `lib/services/socket_service.dart` builds.
//
// Run:
//   dart run tool/socket_probe.dart app <host> <seconds>   # transports: ['polling']  (current app config)
//   dart run tool/socket_probe.dart ws  <host> <seconds>   # polling + websocket upgrade
//
// It prints a timeline of every transport-level event and a summary at the
// end, so connection drops can be attributed to a cause instead of guessed.

import 'dart:async';
import 'dart:io';

import 'package:socket_io_client/socket_io_client.dart' as io;

final Stopwatch _clock = Stopwatch()..start();
String _t() {
  final ms = _clock.elapsedMilliseconds;
  return '${(ms ~/ 1000).toString().padLeft(4)}.${(ms % 1000).toString().padLeft(3, '0')}s';
}

void log(String message) => stdout.writeln('[${_t()}] $message');

Future<void> main(List<String> args) async {
  final mode = args.isNotEmpty ? args[0] : 'app';
  final host = args.length > 1 ? args[1] : 'http://192.168.31.206:5050';
  final seconds = args.length > 2 ? int.parse(args[2]) : 150;

  // On the Dart VM, socket_io_client's transport factory ignores the transport
  // NAME and always builds an IOWebSocketTransport. The engine still writes
  // query['transport'] = transports[0]. So whatever is listed FIRST must be
  // 'websocket', or the WebSocket handshake is sent to a URL claiming
  // transport=polling and the server answers HTTP 200 instead of 101.
  final List<String> transports;
  switch (mode) {
    case 'wsonly':
      transports = <String>['websocket'];
      break;
    case 'ws':
      transports = <String>['polling', 'websocket'];
      break;
    default:
      transports = <String>['polling'];
  }

  log('MODE=$mode  HOST=$host  DURATION=${seconds}s  transports=$transports');
  log('client library: socket_io_client 2.0.3+1');

  var connects = 0;
  var disconnects = 0;
  var connectErrors = 0;
  var managerReconnectAttempts = 0;
  var engineCloses = 0;
  var engineErrors = 0;
  var pongs = 0;
  var packetsSeen = 0;
  DateTime? connectedSince;
  final List<String> dropReasons = <String>[];
  Duration longestUp = Duration.zero;

  // Identical option map to SocketService.connect().
  final socket = io.io(host, <String, dynamic>{
    'transports': transports,
    'autoConnect': false,
    'reconnection': true,
    'reconnectionAttempts': 20,
    'reconnectionDelay': 1000,
    'reconnectionDelayMax': 5000,
    'forceNew': true,
    'timeout': 20000,
  });

  String transportName() => socket.io.engine?.transport?.name ?? 'unknown';

  socket.onConnect((_) {
    connects++;
    connectedSince = DateTime.now();
    log('SOCKET CONNECT  id=${socket.id}  engineTransport=${transportName()}');
  });

  socket.onDisconnect((data) {
    disconnects++;
    final since = connectedSince;
    final up = since == null ? Duration.zero : DateTime.now().difference(since);
    if (up > longestUp) longestUp = up;
    if (up > Duration.zero) dropReasons.add('${up.inSeconds}s uptime, reason=$data');
    connectedSince = null;
    log('SOCKET DISCONNECT  reason=$data  (uptime ${up.inSeconds}s)');
  });

  socket.onConnectError((data) {
    connectErrors++;
    log('SOCKET CONNECT_ERROR  $data');
  });

  socket.onError((data) => log('SOCKET ERROR  $data'));

  socket.onReconnect((data) {
    connectedSince = DateTime.now();
    log('SOCKET RECONNECTED  $data');
  });
  socket.onReconnectAttempt((n) {
    managerReconnectAttempts++;
    log('manager reconnect_attempt #$n');
  });
  socket.onReconnectError((e) => log('manager reconnect_error  $e'));
  socket.onReconnectFailed((e) => log('manager reconnect_failed  $e'));

  // Manager (engine.io) level — this is where transport drops show up.
  socket.io.on('open', (_) => log('engine OPEN'));
  socket.io.on('close', (d) {
    engineCloses++;
    log('engine CLOSE  $d');
  });
  socket.io.on('error', (e) {
    engineErrors++;
    log('engine ERROR  $e');
  });

  // Underlying engine socket: every engine.io packet + heartbeat.
  try {
    final engine = socket.io.engine;
    engine?.on('packet', (p) {
      packetsSeen++;
      final type = (p is Map ? p['type'] : null) ?? p;
      if (type != 'pong' && type != 'ping') {
        log('engine packet: $type');
      }
    });
    engine?.on('pong', (_) {
      pongs++;
      log('engine PONG #$pongs');
    });
    engine?.on('heartbeat', (_) => log('engine HEARTBEAT timer reset'));
    engine?.on('close', (d) {
      engineCloses++;
      log('engine-socket CLOSE  $d');
    });
    engine?.on('error', (e) {
      engineErrors++;
      log('engine-socket ERROR  $e');
    });
  } catch (e) {
    log('could not attach engine listeners: $e');
  }

  // Server -> client events the app cares about.
  socket.on('connected', (d) => log('EVENT connected  $d'));
  socket.on('mechanic_online_updated', (d) => log('EVENT mechanic_online_updated  $d'));
  socket.on('mechanic_location_updated', (d) => log('EVENT mechanic_location_updated  $d'));

  log('--- calling connect() (mimics a screen initState) ---');
  socket.connect();

  // Mimic the app: a second screen mounting and calling connect() again
  // while the first connection is still being established.
  Timer(const Duration(seconds: 2), () {
    log('--- second screen calls connect() (socket.connected=${socket.connected}) ---');
    if (!socket.connected) {
      log('  -> app code would DISPOSE and recreate the socket here');
    }
  });

  // Mimic mechanic_home_screen emitting an online heartbeat every 10s and a
  // GPS fix every 3s (crew_job_service.streamLocation).
  var emitSeq = 0;
  final emitTimer = Timer.periodic(const Duration(seconds: 3), (t) {
    emitSeq++;
    final connected = socket.connected;
    if (emitSeq % 3 == 1) {
      socket.emit('mechanic_online', {
        'mechanicId': 'probe-mechanic',
        'name': 'Probe',
        'online': true,
      });
      log('emit mechanic_online      (connected=$connected)');
    }
    socket.emit('update_location', {
      'crewId': 'probe-mechanic',
      'requestId': 'probe-request',
      'lat': 12.9716,
      'lng': 77.5946,
    });
    log('emit update_location #$emitSeq (connected=$connected)');
  });

  await Future<void>.delayed(Duration(seconds: seconds));
  emitTimer.cancel();

  if (connectedSince != null) {
    final since = connectedSince!;
    final up = DateTime.now().difference(since);
    if (up > longestUp) longestUp = up;
  }

  log('');
  log('================ SUMMARY (mode=$mode) ================');
  log('socket connects           : $connects');
  log('socket disconnects        : $disconnects');
  log('socket connect_errors     : $connectErrors');
  log('manager reconnect attempts: $managerReconnectAttempts');
  log('engine closes             : $engineCloses');
  log('engine errors             : $engineErrors');
  log('engine pongs received     : $pongs');
  log('engine packets seen       : $packetsSeen');
  log('longest continuous uptime : ${longestUp.inSeconds}s');
  log('final connected           : ${socket.connected}');
  log('final transport           : ${transportName()}');
  if (dropReasons.isNotEmpty) {
    log('drop reasons:');
    for (final r in dropReasons) {
      log('  - $r');
    }
  }
  log('=====================================================');

  socket.dispose();
  exit(0);
}
