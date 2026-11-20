// FILE: lib/screens/mechanic_documents_screen.dart
/// §33 — licence, ID and photo upload for mechanic verification.
///
/// Files are uploaded to `POST /api/uploads` (multipart) and the returned URL is
/// stored on the mechanic document by `PUT /api/mechanic/<id>/profile`. The
/// verification flag itself is admin-only — this screen never sets it.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/session/app_session.dart';
import '../core/theme/role_colors.dart';
import '../services/module_api.dart';
import '../widgets/rq_async.dart';

class MechanicDocumentsScreen extends StatefulWidget {
  const MechanicDocumentsScreen({super.key, this.mechanicId});

  final String? mechanicId;

  @override
  State<MechanicDocumentsScreen> createState() =>
      _MechanicDocumentsScreenState();
}

class _MechanicDocumentsScreenState extends State<MechanicDocumentsScreen> {
  static const List<(String, String, IconData)> _required =
      <(String, String, IconData)>[
    ('license', 'Driving licence', Icons.badge_outlined),
    ('id', 'Government ID', Icons.credit_card_outlined),
    ('photo', 'Profile photo', Icons.face_outlined),
  ];

  String get _id => widget.mechanicId ?? AppSession.id ?? '';

  Map<String, dynamic> _profile = const {};
  bool _loading = true;
  String? _error;
  String? _uploadingKind;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_id.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No mechanic is signed in.';
      });
      return;
    }
    try {
      final profile = await ModuleApi.mechanicProfile(_id);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = rqMessage(e);
      });
    }
  }

  List<Map<String, dynamic>> get _documents {
    final raw = _profile['documents'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((d) => d.cast<String, dynamic>())
        .toList();
  }

  String? _urlFor(String kind) {
    for (final doc in _documents) {
      if ((doc['kind'] ?? '') == kind) return (doc['url'] ?? '').toString();
    }
    return null;
  }

  Future<void> _pick(String kind) async {
    final picker = ImagePicker();
    XFile? file;
    try {
      file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1600,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the picker: $e',
            style: const TextStyle(inherit: true),
          ),
        ),
      );
      return;
    }
    if (file == null) return;

    setState(() => _uploadingKind = kind);
    try {
      final url = await ModuleApi.upload(filePath: file.path, kind: 'document');

      final updated = <Map<String, dynamic>>[
        ..._documents.where((d) => (d['kind'] ?? '') != kind),
        {
          'kind': kind,
          'url': url,
          'addedAt': DateTime.now().toIso8601String(),
        },
      ];

      final fields = <String, dynamic>{'documents': updated};
      if (kind == 'photo') fields['photoUrl'] = url;
      await ModuleApi.saveMechanicProfile(_id, fields);

      if (!mounted) return;
      setState(() {
        _profile = <String, dynamic>{
          ..._profile,
          'documents': updated,
          if (kind == 'photo') 'photoUrl': url,
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Uploaded. An admin still has to verify it.',
              style: TextStyle(inherit: true)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(rqMessage(e), style: const TextStyle(inherit: true))),
      );
    } finally {
      if (mounted) setState(() => _uploadingKind = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verified = _profile['verified'] == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents', style: TextStyle(inherit: true)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const RqLoading(label: 'Loading your documents…')
          : _error != null
              ? RqError(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: RoleColors.tint(
                            verified ? RoleColors.assistant : RoleColors.garage,
                            opacity: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            verified
                                ? Icons.verified_user
                                : Icons.pending_actions,
                            color: verified
                                ? RoleColors.assistant
                                : RoleColors.garage,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              verified
                                  ? 'Verified. Your documents are on file.'
                                  : 'Not verified yet. Upload the three items '
                                      'below and an admin will review them.',
                              style: const TextStyle(
                                  inherit: true, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    for (final item in _required) ...[
                      _documentCard(item.$1, item.$2, item.$3),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'Images are stored on the RoadResQ backend under '
                      'backend/uploads and served from /api/uploads. Only the '
                      'URL is stored on your profile.',
                      style: TextStyle(
                          inherit: true,
                          fontSize: 11,
                          color: RoleColors.neutral),
                    ),
                  ],
                ),
    );
  }

  Widget _documentCard(String kind, String label, IconData icon) {
    final url = _urlFor(kind);
    final uploading = _uploadingKind == kind;

    return RqCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: RoleColors.tint(
                url != null ? RoleColors.assistant : RoleColors.neutral,
                opacity: 0.12),
            child: Icon(icon,
                color: url != null
                    ? RoleColors.assistant
                    : RoleColors.neutral),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        inherit: true, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  url == null ? 'Not uploaded' : 'Uploaded',
                  style: TextStyle(
                    inherit: true,
                    fontSize: 11,
                    color: url == null
                        ? RoleColors.user
                        : RoleColors.assistant,
                  ),
                ),
              ],
            ),
          ),
          if (uploading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            TextButton.icon(
              onPressed: () => _pick(kind),
              icon: Icon(url == null ? Icons.upload : Icons.swap_horiz,
                  size: 16),
              label: Text(url == null ? 'Upload' : 'Replace',
                  style: const TextStyle(inherit: true, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
