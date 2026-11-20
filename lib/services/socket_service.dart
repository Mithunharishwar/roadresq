// FILE: lib/services/socket_service.dart
//
// Realtime transport for RoadResQ, wrapping `socket_io_client` in a single
// app-wide connection.
//
// ── Why this file was rewritten ────────────────────────────────────────────
// Three independent defects made realtime unreliable. All three are fixed here
// and each fix carries its reason inline:
//
//  1. TRANSPORT (fatal, in AppConfig): the client listed `polling` first, which
//     made engine.io write `transport=polling` into a URI that the Dart VM
//     then opened as a *WebSocket*. Every attempt failed with
//     "was not upgraded to websocket, HTTP status code: 200". See
//     `AppConfig.socketTransports`. Result: 0 connects, ever.
//
//  2. CONNECT THRASH: `connect()` disposed and recreated the socket whenever it
//     ran while the socket was not connected. Every screen calls `connect()`
//     from `initState`, so navigating during a reconnect (or during the
//     initial handshake) destroyed a working or in-flight connection and
//     started over. `connect()` is now idempotent.
//
//  3. SHARED LISTENERS: all screens registered handlers on `_socket` directly
//     and any one screen's `dispose()` called `clearAllListeners()`, which
//     removed *every* screen's handlers app-wide. Live updates therefore
//     stopped for whichever screen was still open. Listeners are now owned by
//     a [SocketSubscription] handle and cancelling one never disturbs another.
//
// The 20-second retry timer that used to live in `connect()` is gone: it
// checked a flag (`_isConnecting`) that `onConnectError` had already cleared,
// so it could never fire, and no automatic retry ever happened on error.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/config/app_config.dart';
import 'backend_discovery.dart';

/// Handle for one listener registration.
///
/// The owner (a screen or service) keeps this and calls [cancel] from its
/// `dispose()`. Cancelling removes only the listener it was created for —
/// unlike the previous shared-listener design, where one screen's `dispose()`
/// silently unsubscribed every other screen.
class SocketSubscription {
  SocketSubscription._(this._onCancel);

  final VoidCallback _onCancel;
  bool _active = true;

  /// True until [cancel] has run (calling it twice is harmless).
  bool get isActive => _active;

  void cancel() {
    if (!_active) return;
    _active = false;
    _onCancel();
  }
}

/// One registered listener for one event name.
class _Listener {
  _Listener(this.handler);
  final void Function(dynamic data) handler;
}

class SocketService {
  SocketService._internal();
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;

  io.Socket? _socket;

  /// Event name -> listeners. Exactly ONE raw handler per event is attached to
  /// the underlying socket, and it fans out to this map. Two consequences:
  /// registrations can never accumulate duplicates on the raw socket, and
  /// removing one listener cannot remove another.
  final Map<String, List<_Listener>> _listeners =
      <String, List<_Listener>>{};

  /// Called when the backend has been unreachable for [_offlineAfter].
  final List<VoidCallback> _offlineListeners = <VoidCallback>[];

  /// Called on every connectivity transition, for diagnostics banners.
  final List<void Function(bool connected, String detail)> _stateListeners =
      <void Function(bool connected, String detail)>[];

  /// Grace period before the app tells the user the backend is unreachable.
  /// Long enough to ride out a normal reconnect, short enough to be useful.
  static const Duration _offlineAfter = Duration(seconds: 15);

  Timer? _offlineTimer;
  bool _offlineNotified = false;

  /// Consecutive failed connection attempts since the last success.
  ///
  /// Drives both log throttling (an unreachable backend used to print three
  /// identical stack traces per second, forever) and the self-heal trigger.
  int _connectErrors = 0;

  /// Attempts since the socket was created, for throttled progress logging.
  int _reconnectAttempts = 0;

  /// Guards against overlapping discovery runs during a reconnect storm.
  bool _healing = false;
  DateTime? _lastHealAttempt;

  /// After this many consecutive failures the service looks for the backend on
  /// the LAN instead of dialling the same dead address forever.
  static const int _healAfterErrors = 3;

  /// Minimum gap between discovery runs, escalating while the backend stays
  /// down: 30 s → 60 s → 120 s → 300 s, reset on success.
  ///
  /// A fixed 30 s meant a backend that is off for the day produced a network
  /// sweep every half minute, all day, and filled the terminal with the same
  /// lines. Backing off keeps one probe every few minutes instead.
  static const Duration _healCooldownBase = Duration(seconds: 30);
  static const Duration _healCooldownMax = Duration(minutes: 5);
  int _healBackoffStep = 0;

  Duration get _healCooldown {
    final factor = 1 << _healBackoffStep.clamp(0, 4);
    final next = _healCooldownBase * factor;
    return next > _healCooldownMax ? _healCooldownMax : next;
  }

  // ── Offline visibility ────────────────────────────────────────────────
  /// True when the socket is currently connected.
  bool get isConnected => _socket?.connected ?? false;

  /// Human-readable host, for diagnostics screens and support tickets.
  String get currentHost => socketBaseUrl;

  /// The raw client, for diagnostics only.
  io.Socket? get rawSocket => _socket;

  // ── Host resolution ───────────────────────────────────────────────────
  // Resolved by AppConfig — the same object the REST layer reads — so the two
  // layers can never point at different machines.
  static String get socketBaseUrl => AppConfig.socketBaseUrl;

  /// Retained for callers that referenced the old constant.
  static String get defaultSocketBaseUrl => AppConfig.socketBaseUrl;

  /// Point both the socket and the REST client at the Android emulator's
  /// loopback to the host machine. Call before any screen connects.
  static Future<void> useEmulator() =>
      _instance.retarget(AppConfig.androidEmulatorHost, reason: 'emulator');

  /// Drop any runtime override and fall back to the resolved platform default.
  static Future<void> useLanHost() async {
    AppConfig.clearHostOverride();
    await _instance.retarget(AppConfig.host, reason: 'lan default', force: true);
  }

  /// Point the app at a different backend and rebuild the connection.
  ///
  /// WHY THIS REBUILDS
  /// The client caches one Manager per origin, and `_socket` holds the URL it
  /// was created with. The previous version only changed `AppConfig`, so after
  /// the user typed a new server address the REST calls moved but the socket
  /// kept dialling the old machine — every attempt failing with the same
  /// `SocketException` until the app was restarted. Changing the host is exactly
  /// the moment the connection must be re-created.
  static Future<void> setSocketHost(String url) =>
      _instance.retarget(url, reason: 'manual');

  /// Switch host, adopt it for REST + persistence, and reconnect.
  Future<void> retarget(
    String url, {
    String reason = '',
    bool force = false,
  }) async {
    final cleaned = url.trim().endsWith('/')
        ? url.trim().substring(0, url.trim().length - 1)
        : url.trim();
    if (cleaned.isEmpty) return;

    final changed = cleaned != AppConfig.host;
    await AppConfig.adoptHost(cleaned);

    if (!changed && !force && _socket != null) {
      if (!_socket!.connected) _socket!.connect();
      return;
    }

    debugPrint('[socket] target -> $cleaned${reason.isEmpty ? '' : ' ($reason)'}');
    _disposeSocket();
    _connectErrors = 0;
    _reconnectAttempts = 0;
    _createSocket();
  }

  /// Tear the transport down while keeping every registered listener intact.
  ///
  /// The listener fan-out lives in [_listeners], independent of the raw socket,
  /// so screens that are already open keep receiving events after a host change.
  void _disposeSocket() {
    final socket = _socket;
    _socket = null;
    try {
      socket?.clearListeners();
      socket?.disconnect();
      socket?.dispose();
    } catch (e) {
      debugPrint('[socket] error while disposing: $e');
    }
  }

  /// Look for the backend elsewhere on the LAN after repeated failures.
  ///
  /// This is the fix for the daily "No route to host" loop: the app no longer
  /// retries a stale address forever, it finds the machine's current one and
  /// moves the socket with it.
  Future<void> _selfHeal() async {
    if (_healing || !BackendDiscovery.enabled) return;
    if (_connectErrors < _healAfterErrors) return;

    final last = _lastHealAttempt;
    final cooldown = _healCooldown;
    if (last != null && DateTime.now().difference(last) < cooldown) return;

    _healing = true;
    _lastHealAttempt = DateTime.now();
    _healBackoffStep = (_healBackoffStep + 1).clamp(0, 4);
    try {
      debugPrint('[socket] backend unreachable after $_connectErrors attempts — '
          'searching the local network for it');
      final result = await BackendDiscovery.ensureReachable(
        reason: 'socket self-heal',
        force: true,
      );
      if (result.found && result.host != AppConfig.host) {
        await retarget(result.host!, reason: 'discovered via ${result.method}');
        return;
      }
      if (result.found) {
        // Same address, still failing: force a fresh connection rather than
        // leaving the manager in a backoff loop.
        debugPrint('[socket] backend still reachable at ${result.host} — '
            'resetting the connection');
        _disposeSocket();
        _connectErrors = 0;
        _createSocket();
        return;
      }
      debugPrint('[socket] no RoadResQ backend found on this network. '
          'Start it with .\\start_backend.ps1 and check the phone is on the same Wi-Fi.');
      _notifyState(
        false,
        'No backend found on this network (${result.probed} addresses probed). '
        'Start the backend, or set the server address from the login screen.',
      );
    } catch (e) {
      debugPrint('[socket] self-heal failed: $e');
    } finally {
      _healing = false;
    }
  }

  // ── Connection ────────────────────────────────────────────────────────

  /// Ensure the realtime connection is up. Safe to call from every screen's
  /// `initState()` — repeat calls are cheap no-ops.
  void connect() {
    final existing = _socket;

    if (existing != null) {
      // Never dispose a live socket here. `Socket.connect()` is idempotent, and
      // when the manager is closed it reopens it (`io.open()`); the manager
      // additionally owns the reconnect schedule. Rebuilding the socket on
      // every call — which is what this used to do — tore down connections
      // that were open, opening, or mid-reconnect.
      if (!existing.connected) {
        existing.connect();
      }
      return;
    }

    _createSocket();
  }

  void _createSocket() {
    try {
      // `forceNew` keeps a stale Manager from being reused when AppConfig's
      // host changed at runtime; the client caches Managers per origin.
      _socket = io.io(socketBaseUrl, <String, dynamic>{
        'transports': AppConfig.socketTransports,
        'autoConnect': false,
        'reconnection': true,
        // No `reconnectionAttempts`: the library's default is infinity, which
        // is what an emergency-assistance app wants. The previous value of 20
        // meant the socket gave up permanently after 20 tries and never
        // recovered without an app restart.
        'reconnectionDelay': 1000,
        'reconnectionDelayMax': 5000,
        'randomizationFactor': 0.5,
        'forceNew': true,
        'timeout': 20000,
      });

      _attachCoreListeners(_socket!);
      debugPrint('[socket] connecting to $socketBaseUrl');
      _socket!.connect();
    } catch (e) {
      debugPrint('[socket] init error: $e');
      _notifyState(false, 'init error: $e');
    }
  }

  void _attachCoreListeners(io.Socket socket) {
    socket.onConnect((_) {
      _offlineTimer?.cancel();
      _offlineNotified = false;
      final recovered = _connectErrors > 0;
      _connectErrors = 0;
      _reconnectAttempts = 0;
      _healBackoffStep = 0;
      _lastHealAttempt = null;
      debugPrint('[socket] connected to $socketBaseUrl (id=${socket.id})'
          '${recovered ? ' after failures — recovered automatically' : ''}');
      _notifyState(true, 'Connected to $socketBaseUrl');
      socket.emit('connected', {'msg': 'client alive'});
    });

    socket.onDisconnect((data) {
      // A deliberate `disconnect()` during a host change must not be reported
      // as a fault; the new socket is already being created by then.
      if (_socket != socket) return;
      debugPrint('[socket] disconnected: $data');
      _notifyState(false, 'Disconnected: $data');
      _armOfflineWatchdog();
    });

    socket.onConnectError((data) {
      if (_socket != socket) return;
      _connectErrors++;
      _armOfflineWatchdog();

      // Throttle: the manager retries every ~1 s while a host is missing, and
      // printing three stack traces per attempt for hours is what made this
      // look like a code failure in the terminal. Keep the first few so the
      // cause is visible, then sample.
      if (_connectErrors <= _healAfterErrors || _connectErrors % 15 == 0) {
        debugPrint('[socket] connect error #$_connectErrors: $data');
      }

      // Distinguish "the server is down" from "this build was pointed at the
      // emulator alias". Those look identical on the wire — a bare timeout with
      // an empty backend log — so name it whenever we can.
      final hint = AppConfig.transportMisconfigurationHint;
      if (hint != null) {
        debugPrint('[socket] WARNING — TRANSPORT MISCONFIGURED: $hint');
      }

      _notifyState(
        false,
        'Connect error: $data${hint == null ? '' : ' — $hint'}',
      );

      // Repeated failure is the signal that the address is stale, not that the
      // code is broken. Go find the backend instead of retrying it forever.
      _selfHeal();
    });

    // `onError` repeats the same exception as `onConnectError`; surface it to
    // listeners but do not print it twice.
    socket.onError((data) {
      if (_socket != socket) return;
      _notifyState(false, 'Socket error: $data');
    });

    socket.onReconnect((data) {
      _offlineTimer?.cancel();
      _offlineNotified = false;
      _connectErrors = 0;
      _reconnectAttempts = 0;
      debugPrint('[socket] reconnected to $socketBaseUrl');
      _notifyState(true, 'Reconnected: $data');
    });

    socket.onReconnectAttempt((n) {
      if (_socket != socket) return;
      _reconnectAttempts++;
      if (_reconnectAttempts == 1 || _reconnectAttempts % 25 == 0) {
        debugPrint('[socket] reconnect attempt $_reconnectAttempts');
      }
    });

    socket.onReconnectFailed((_) {
      if (_socket != socket) return;
      debugPrint('[socket] reconnect failed');
      _notifyState(false, 'Reconnect failed');
      _armOfflineWatchdog();
      _selfHeal();
    });

    // One fan-out handler per event; see `_listeners`.
    for (final event in _eventNames) {
      socket.on(event, (data) => _dispatch(event, data));
    }
  }

  /// Start (or restart) the countdown that ends in an "offline" notification.
  void _armOfflineWatchdog() {
    if (_offlineNotified) return;
    _offlineTimer?.cancel();
    _offlineTimer = Timer(_offlineAfter, () {
      if (isConnected || _offlineNotified) return;
      _offlineNotified = true;
      debugPrint('[socket] backend unreachable for '
          '${_offlineAfter.inSeconds}s — notifying listeners');
      for (final listener in List<VoidCallback>.from(_offlineListeners)) {
        try {
          listener();
        } catch (e) {
          debugPrint('[socket] offline listener threw: $e');
        }
      }
    });
  }

  void _notifyState(bool connected, String detail) {
    for (final listener
        in List<void Function(bool, String)>.from(_stateListeners)) {
      try {
        listener(connected, detail);
      } catch (e) {
        debugPrint('[socket] state listener threw: $e');
      }
    }
  }

  void _dispatch(String event, dynamic data) {
    final handlers = _listeners[event];
    if (handlers == null || handlers.isEmpty) return;
    for (final listener in List<_Listener>.from(handlers)) {
      try {
        listener.handler(data);
      } catch (e) {
        debugPrint('[socket] handler for "$event" threw: $e');
      }
    }
  }

  // ── Registration ──────────────────────────────────────────────────────

  /// Every server event the app consumes. Listed once so the fan-out handlers
  /// and [clearAllListeners] cannot drift apart.
  static const List<String> _eventNames = <String>[
    'connected',
    'new_request',
    'request_assigned',
    'status_updated',
    'mechanic_location_updated',
    'mechanic_online_updated',
    'mechanic_location_global_updated',
    'payment_updated',
    'assistant_assigned',
    'assistant_location_updated',
    'assistant_status_updated',
    'assistant_online_updated',
    // §18 in-job chat. Added to the fan-out list so a chat message reaches the
    // open conversation on both the customer and the crew screen.
    'chat_message',
  ];

  SocketSubscription _register(String event, void Function(dynamic) handler) {
    final list = _listeners.putIfAbsent(event, () => <_Listener>[]);
    final listener = _Listener(handler);
    list.add(listener);
    return SocketSubscription._(() {
      final current = _listeners[event];
      if (current == null) return;
      current.remove(listener);
      if (current.isEmpty) _listeners.remove(event);
    });
  }

  /// Register a handler for the server's `connected` acknowledgement.
  SocketSubscription onConnected(void Function(dynamic) handler) =>
      _register('connected', handler);

  SocketSubscription onNewRequest(void Function(dynamic) handler) =>
      _register('new_request', handler);

  SocketSubscription onRequestAssigned(void Function(dynamic) handler) =>
      _register('request_assigned', handler);

  SocketSubscription onStatusUpdated(void Function(dynamic) handler) =>
      _register('status_updated', handler);

  SocketSubscription onMechanicLocationUpdated(void Function(dynamic) handler) =>
      _register('mechanic_location_updated', handler);

  SocketSubscription onMechanicOnlineUpdated(void Function(dynamic) handler) =>
      _register('mechanic_online_updated', handler);

  SocketSubscription onMechanicLocationGlobalUpdated(
          void Function(dynamic) handler) =>
      _register('mechanic_location_global_updated', handler);

  SocketSubscription onPaymentUpdated(void Function(dynamic) handler) =>
      _register('payment_updated', handler);

  // ── Assistant (Milestone 1) ───────────────────────────────────────────
  SocketSubscription onAssistantAssigned(void Function(dynamic) handler) =>
      _register('assistant_assigned', handler);

  SocketSubscription onAssistantLocationUpdated(
          void Function(dynamic) handler) =>
      _register('assistant_location_updated', handler);

  SocketSubscription onAssistantStatusUpdated(void Function(dynamic) handler) =>
      _register('assistant_status_updated', handler);

  SocketSubscription onAssistantOnlineUpdated(void Function(dynamic) handler) =>
      _register('assistant_online_updated', handler);

  // ── Chat (§18) ────────────────────────────────────────────────────────
  /// A chat message was sent or received on a job.
  SocketSubscription onChatMessage(void Function(dynamic) handler) =>
      _register('chat_message', handler);

  /// Called when the backend has been unreachable for [_offlineAfter].
  SocketSubscription addOfflineListener(VoidCallback listener) {
    _offlineListeners.add(listener);
    return SocketSubscription._(() => _offlineListeners.remove(listener));
  }

  /// Called on every connectivity transition (connected/disconnected).
  SocketSubscription addConnectionStateListener(
      void Function(bool connected, String detail) listener) {
    _stateListeners.add(listener);
    return SocketSubscription._(() => _stateListeners.remove(listener));
  }

  /// Remove EVERY listener registered through this service.
  ///
  /// Only for app shutdown or a full logout. Individual screens must cancel
  /// their own [SocketSubscription] handles instead — calling this from one
  /// screen's `dispose()` is what used to break realtime for every other
  /// screen, so no screen calls it any more.
  void clearAllListeners() {
    _listeners.clear();
    debugPrint('[socket] cleared all listeners (app-wide)');
  }

  // ── Sending ───────────────────────────────────────────────────────────

  /// Events carrying a position sample. A stale position is worthless — the
  /// next sample supersedes it — so these are dropped while the socket is
  /// down rather than queued.
  static const Set<String> _volatileEvents = <String>{
    'update_location',
    'mechanic_location_update',
    'assistant_location_update',
  };

  /// Send an event.
  ///
  /// When the socket is momentarily down this no longer discards the message:
  /// `socket_io_client` buffers outgoing packets in `sendBuffer` and replays
  /// them on connect. The old guard returned early while disconnected, which
  /// defeated that buffer — so a command emitted right after `connect()`
  /// (such as `crew_online`, or an `accept_request` during a network blip) was
  /// lost without any error.
  void emit(String event, dynamic data) {
    // An emit before any screen has connected used to be silently dropped.
    if (_socket == null) {
      _createSocket();
    }

    final socket = _socket;
    if (socket == null) {
      debugPrint('[socket] cannot emit "$event": no socket');
      return;
    }

    if (!socket.connected && _volatileEvents.contains(event)) {
      debugPrint('[socket] dropping stale "$event" (socket down)');
      return;
    }

    debugPrint('[socket] emit $event');
    socket.emit(event, data);
  }

  // ── Teardown ──────────────────────────────────────────────────────────

  void disconnect() {
    debugPrint('[socket] disconnecting');
    _offlineTimer?.cancel();
    _offlineTimer = null;
    _offlineNotified = false;
    _connectErrors = 0;
    _reconnectAttempts = 0;
    _disposeSocket();
  }

  /// One-line connectivity summary for diagnostics screens.
  String describeConnectivity() =>
      'socket: ${isConnected ? 'connected' : 'down'} • host: $socketBaseUrl • '
      'transport: ${AppConfig.socketTransports.join(',')}';
}
