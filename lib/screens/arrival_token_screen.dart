// FILE: lib/screens/arrival_token_screen.dart
/// §38 / §39 — the 6-digit arrival token.
///
/// The crew GENERATES it (server-side, stored on the job) and shows the digits
/// plus a QR. The customer VERIFIES it on arrival. Because both sides talk to
/// the same stored value, a screenshot of a token from another job cannot be
/// reused, and the token is consumed on first success.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/theme/role_colors.dart';
import '../services/module_api.dart';
import '../widgets/rq_async.dart';

enum TokenMode { generate, verify }

class ArrivalTokenScreen extends StatefulWidget {
  const ArrivalTokenScreen({
    super.key,
    required this.mode,
    required this.requestId,
    this.mechanicId = '',
    this.issue = '',
  });

  final TokenMode mode;
  final String requestId;
  final String mechanicId;
  final String issue;

  @override
  State<ArrivalTokenScreen> createState() => _ArrivalTokenScreenState();
}

class _ArrivalTokenScreenState extends State<ArrivalTokenScreen> {
  final TextEditingController _code = TextEditingController();

  String? _token;
  String? _qrPayload;
  String? _expiresAt;
  bool _busy = false;
  bool _verified = false;
  String? _error;

  bool get _isGenerate => widget.mode == TokenMode.generate;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = await ModuleApi.generateToken(
        widget.requestId,
        mechanicId: widget.mechanicId,
      );
      if (!mounted) return;
      setState(() {
        _token = (body['token'] ?? '').toString();
        _qrPayload = (body['qrPayload'] ?? '').toString();
        _expiresAt = (body['expiresAt'] ?? '').toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = rqMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the full 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ModuleApi.verifyToken(
        requestId: widget.requestId,
        token: code,
      );
      if (!mounted) return;
      setState(() => _verified = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = rqMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isGenerate ? 'Arrival token' : 'Confirm arrival',
            style: const TextStyle(inherit: true)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _isGenerate
                ? 'Show this code to the customer. They enter (or scan) it to '
                    'confirm you have arrived.'
                : 'Ask the crew for their 6-digit arrival code. Confirming it '
                    'marks the arrival on the job.',
            style: theme.textTheme.bodySmall?.copyWith(
                inherit: true, height: 1.5, color: RoleColors.neutral),
          ),
          const SizedBox(height: 22),

          if (_isGenerate) ...[
            if (_token == null)
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: RoleColors.mechanic),
                  onPressed: _busy ? null : _generate,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.pin_outlined),
                  label: const Text('Generate token',
                      style: TextStyle(
                          inherit: true, fontWeight: FontWeight.w600)),
                ),
              )
            else ...[
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 14),
                      decoration: BoxDecoration(
                        color:
                            RoleColors.tint(RoleColors.mechanic, opacity: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _token!.split('').join(' '),
                        style: const TextStyle(
                          inherit: true,
                          fontSize: 34,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                          color: RoleColors.mechanic,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if ((_qrPayload ?? '').isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: _qrPayload!,
                          size: 168,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(
                            ClipboardData(text: _token ?? ''));
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Token copied',
                                style: TextStyle(inherit: true)),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy code',
                          style: TextStyle(inherit: true, fontSize: 12)),
                    ),
                    if ((_expiresAt ?? '').isNotEmpty)
                      Text(
                        'Expires ${_expiresAt!.split('T').first} '
                        '${_expiresAt!.split('T').length > 1 ? _expiresAt!.split('T')[1].replaceAll('Z', '') : ''}',
                        style: const TextStyle(
                            inherit: true,
                            fontSize: 11,
                            color: RoleColors.neutral),
                      ),
                    const SizedBox(height: 6),
                    const Text(
                      'Generating again replaces the previous code.',
                      style: TextStyle(
                          inherit: true,
                          fontSize: 11,
                          color: RoleColors.neutral),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _busy ? null : _generate,
                      child: const Text('Regenerate',
                          style: TextStyle(inherit: true, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ] else ...[
            if (_verified)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: RoleColors.tint(RoleColors.assistant, opacity: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.verified_user,
                        size: 42, color: RoleColors.assistant),
                    SizedBox(height: 10),
                    Text(
                      'Arrival confirmed',
                      style: TextStyle(
                          inherit: true,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: RoleColors.assistant),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'The token was accepted and consumed. The job now shows '
                      'the arrival time.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          inherit: true,
                          fontSize: 12,
                          color: RoleColors.neutral),
                    ),
                  ],
                ),
              )
            else ...[
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                    inherit: true,
                    fontSize: 28,
                    letterSpacing: 12,
                    fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                  hintText: '000000',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: RoleColors.assistant),
                  onPressed: _busy ? null : _verify,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Confirm arrival',
                          style: TextStyle(
                              inherit: true, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],

          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: RoleColors.tint(RoleColors.user, opacity: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _error!,
                style: const TextStyle(inherit: true, color: RoleColors.user),
              ),
            ),
          ],

          const SizedBox(height: 24),
          Text(
            'Job ${widget.requestId}',
            style: const TextStyle(
                inherit: true, fontSize: 11, color: RoleColors.neutral),
          ),
        ],
      ),
    );
  }
}
