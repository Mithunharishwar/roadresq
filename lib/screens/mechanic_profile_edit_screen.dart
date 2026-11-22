// FILE: lib/screens/mechanic_profile_edit_screen.dart
/// §29 — editable mechanic profile: name, contact, skills, experience, bio.
///
/// Reads and writes `GET/PUT /api/mechanic/<id>/profile`. Verification, rating
/// and completed-job counts are shown read-only because the backend refuses to
/// let a client set them.
library;

import 'package:material_ui/material_ui.dart';

import '../core/session/app_session.dart';
import '../core/theme/role_colors.dart';
import '../services/module_api.dart';
import '../widgets/rq_async.dart';
import 'mechanic_documents_screen.dart';
import 'mechanic_ratings_screen.dart';

class MechanicProfileEditScreen extends StatefulWidget {
  const MechanicProfileEditScreen({super.key, this.mechanicId});

  final String? mechanicId;

  @override
  State<MechanicProfileEditScreen> createState() =>
      _MechanicProfileEditScreenState();
}

class _MechanicProfileEditScreenState
    extends State<MechanicProfileEditScreen> {
  static const List<String> _allSkills = <String>[
    'Flat Tyre',
    'Battery Problem',
    'Fuel Delivery',
    'Engine Trouble',
    'Towing',
    'General Service',
  ];

  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _experience = TextEditingController();
  final TextEditingController _bio = TextEditingController();

  final Set<String> _skills = <String>{};
  Map<String, dynamic> _profile = const {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String get _id => widget.mechanicId ?? AppSession.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _experience.dispose();
    _bio.dispose();
    super.dispose();
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
        _name.text = (profile['name'] ?? '').toString();
        _phone.text = (profile['phone'] ?? '').toString();
        _experience.text = (profile['experienceYears'] ?? '').toString();
        _bio.text = (profile['bio'] ?? '').toString();
        _skills
          ..clear()
          ..addAll(((profile['skills'] as List?) ?? const [])
              .map((s) => s.toString())
              .where((s) => s.isNotEmpty));
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

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A name is required.',
              style: TextStyle(inherit: true)),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ModuleApi.saveMechanicProfile(_id, <String, dynamic>{
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'experienceYears': _experience.text.trim(),
        'bio': _bio.text.trim(),
        'skills': _skills.toList(),
      });
      await AppSession.updateName(_name.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved.', style: TextStyle(inherit: true)),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(rqMessage(e), style: const TextStyle(inherit: true))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verified = _profile['verified'] == true;
    final rating = (_profile['rating'] as num?)?.toDouble() ?? 0.0;
    final ratingCount = (_profile['ratingCount'] as num?)?.toInt() ?? 0;
    final completed = (_profile['completedJobs'] as num?)?.toInt() ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mechanic profile',
            style: TextStyle(inherit: true)),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save', style: TextStyle(inherit: true)),
          ),
        ],
      ),
      body: _loading
          ? const RqLoading(label: 'Loading profile…')
          : _error != null
              ? RqError(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: RoleColors.tint(RoleColors.mechanic,
                              opacity: 0.15),
                          backgroundImage:
                              (_profile['photoUrl'] ?? '').toString().isNotEmpty
                                  ? NetworkImage(_profile['photoUrl'].toString())
                                  : null,
                          child:
                              (_profile['photoUrl'] ?? '').toString().isEmpty
                                  ? const Icon(Icons.person,
                                      size: 30, color: RoleColors.mechanic)
                                  : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    verified ? 'Verified mechanic' : 'Unverified',
                                    style: TextStyle(
                                      inherit: true,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: verified
                                          ? RoleColors.assistant
                                          : RoleColors.garage,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ratingCount == 0
                                    ? 'No ratings yet · $completed jobs completed'
                                    : '${rating.toStringAsFixed(1)} ★ '
                                        '($ratingCount) · $completed jobs completed',
                                style: const TextStyle(
                                    inherit: true,
                                    fontSize: 12,
                                    color: RoleColors.neutral),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _name,
                      style: const TextStyle(inherit: true),
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(inherit: true),
                      decoration: const InputDecoration(
                        labelText: 'Phone (shown to customers)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _experience,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(inherit: true),
                      decoration: const InputDecoration(
                        labelText: 'Years of experience',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bio,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 400,
                      style: const TextStyle(inherit: true),
                      decoration: const InputDecoration(
                        labelText: 'About your work',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Skills / services',
                        style: theme.textTheme.labelLarge?.copyWith(
                            inherit: true, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _allSkills.map((skill) {
                        final selected = _skills.contains(skill);
                        return FilterChip(
                          label: Text(skill,
                              style: const TextStyle(
                                  inherit: true, fontSize: 12)),
                          selected: selected,
                          onSelected: (on) => setState(() {
                            if (on) {
                              _skills.add(skill);
                            } else {
                              _skills.remove(skill);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    RqCard(
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.folder_outlined),
                            title: const Text('Documents & verification',
                                style: TextStyle(inherit: true)),
                            subtitle: Text(
                              '${((_profile['documents'] as List?) ?? const []).length} uploaded',
                              style: const TextStyle(
                                  inherit: true,
                                  fontSize: 11,
                                  color: RoleColors.neutral),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MechanicDocumentsScreen(
                                    mechanicId: _id),
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.star_outline),
                            title: const Text('Ratings & reviews',
                                style: TextStyle(inherit: true)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MechanicRatingsScreen(
                                    mechanicId: _id),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
