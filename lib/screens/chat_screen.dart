// FILE: lib/screens/chat_screen.dart
/// §18 — in-job chat between the customer and the crew.
///
/// Sending goes through REST (`POST /api/rescueRequests/<id>/messages`) so the
/// message is guaranteed to be persisted even when the socket is down.
/// Receiving is Socket.IO (`chat_message`), which the backend broadcasts after
/// it stores the message. Both paths share one list, de-duplicated by id.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/theme/role_colors.dart';
import '../services/module_api.dart';
import '../services/socket_service.dart';
import '../widgets/rq_async.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.requestId,
    required this.myId,
    required this.myRole,
    required this.myName,
    this.otherPartyName = 'Crew',
  });

  final String requestId;
  final String myId;
  final String myRole;
  final String myName;
  final String otherPartyName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _messages = <Map<String, dynamic>>[];

  SocketSubscription? _subscription;
  Timer? _poll;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();

    // Realtime first; polling is the fallback when the socket cannot connect.
    final socket = SocketService();
    socket.connect();
    _subscription = socket.onChatMessage(_onSocketMessage);

    _poll = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted && !_sending) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSocketMessage(dynamic data) {
    if (!mounted || data is! Map) return;
    if ((data['requestId'] ?? '').toString() != widget.requestId) return;
    _merge(<Map<String, dynamic>>[data.cast<String, dynamic>()]);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final rows = await ModuleApi.messages(widget.requestId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
      _merge(rows);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = rqMessage(e);
      });
    }
  }

  void _merge(List<Map<String, dynamic>> incoming) {
    final known = _messages
        .map((m) => (m['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    var added = false;
    for (final row in incoming) {
      final id = (row['id'] ?? '').toString();
      if (id.isNotEmpty && known.contains(id)) continue;
      _messages.add(row);
      added = true;
    }
    if (!added) return;

    _messages.sort((a, b) {
      final at = DateTime.tryParse((a['createdAt'] ?? '').toString());
      final bt = DateTime.tryParse((b['createdAt'] ?? '').toString());
      if (at == null || bt == null) return 0;
      return at.compareTo(bt);
    });

    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _input.clear();
    try {
      final response = await ModuleApi.sendMessage(
        requestId: widget.requestId,
        senderId: widget.myId,
        senderRole: widget.myRole,
        senderName: widget.myName,
        text: text,
      );
      final payload = response['data'];
      if (payload is Map && mounted) {
        _merge(<Map<String, dynamic>>[payload.cast<String, dynamic>()]);
      } else {
        await _load(silent: true);
      }
    } catch (e) {
      if (!mounted) return;
      // Restore the text so the user does not lose what they typed.
      _input.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(rqMessage(e), style: const TextStyle(inherit: true))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.otherPartyName,
                style: const TextStyle(inherit: true, fontSize: 16)),
            Text(
              'Job #${widget.requestId.length > 6 ? widget.requestId.substring(widget.requestId.length - 6) : widget.requestId}',
              style: const TextStyle(
                  inherit: true, fontSize: 11, color: RoleColors.neutral),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const RqLoading(label: 'Loading messages…')
                : _error != null && _messages.isEmpty
                    ? RqError(message: _error!, onRetry: _load)
                    : _messages.isEmpty
                        ? const RqEmpty(
                            icon: Icons.chat_bubble_outline,
                            title: 'No messages yet',
                            message:
                                'Say hello, share a landmark or ask how far '
                                'away the crew is.',
                          )
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.all(16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              final mine =
                                  (message['senderId'] ?? '').toString() ==
                                      widget.myId;
                              return _bubble(context, message, mine);
                            },
                          ),
          ),
          if (_error != null && _messages.isNotEmpty)
            Container(
              width: double.infinity,
              color: RoleColors.tint(RoleColors.user, opacity: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                'Reconnecting — new messages may be delayed',
                style: theme.textTheme.bodySmall
                    ?.copyWith(inherit: true, color: RoleColors.user),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      maxLength: 1000,
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        counterText: '',
                        filled: true,
                        fillColor: RoleColors.tint(RoleColors.neutral, opacity: 0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                      ),
                      style: const TextStyle(inherit: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(
      BuildContext context, Map<String, dynamic> message, bool mine) {
    final text = (message['text'] ?? '').toString();
    final created = DateTime.tryParse((message['createdAt'] ?? '').toString());
    final stamp = created == null
        ? ''
        : '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.74,
        ),
        decoration: BoxDecoration(
          color: mine
              ? RoleColors.tint(RoleColors.mechanic, opacity: 0.14)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 4),
            bottomRight: Radius.circular(mine ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  (message['senderName'] ?? 'Crew').toString(),
                  style: const TextStyle(
                    inherit: true,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: RoleColors.neutral,
                  ),
                ),
              ),
            Text(text, style: const TextStyle(inherit: true, fontSize: 14)),
            if (stamp.isNotEmpty)
              Text(
                stamp,
                style: const TextStyle(
                    inherit: true, fontSize: 9, color: RoleColors.neutral),
              ),
          ],
        ),
      ),
    );
  }
}
