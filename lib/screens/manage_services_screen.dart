// lib/screens/manage_services_screen.dart
//
// Manage Services (Helper app, Phase 0)
// -------------------------------------
// • Registered categories (chips) → users/{uid}.registeredCategories
// • Service radius (1–15 km)      → users/{uid}.serviceRadiusKm
// • Services CRUD in /services
// • Add/Edit uses AddEditServiceScreen
//
// Firestore shapes (tolerant):
//   users/{uid} {
//     registeredCategories: [String],
//     allowedCategoryIds: [String],
//     serviceRadiusKm: number
//   }
//   services/{serviceId} {
//     helperId: uid, title, category, price, isActive(bool), description?, imageUrl?,
//     createdAt, updatedAt
//   }

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:servana/screens/step_2_documents.dart' as step2;

import 'package:servana/screens/add_edit_service_screen.dart';

class ManageServicesScreen extends StatefulWidget {
  const ManageServicesScreen({super.key});

  @override
  State<ManageServicesScreen> createState() => _ManageServicesScreenState();
}

class _ManageServicesScreenState extends State<ManageServicesScreen> {
  static const List<String> _kCategories = <String>[
    'Cleaning',
    'Delivery',
    'Repairs',
    'Tutoring',
    'Design',
    'Writing',
  ];

  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _loaded = false;
  List<String> _registered = <String>[];
  List<String> _allowed = <String>[];
  double _radiusKm = 4; // default 4 km

  @override
  void initState() {
    super.initState();
    _prime();
  }

  Future<void> _prime() async {
    if (_uid.isEmpty) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final u = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      final m = u.data() ?? {};
      final reg = (m['registeredCategories'] as List?)?.cast<String>() ?? <String>[];
      final r = (m['serviceRadiusKm'] is num) ? (m['serviceRadiusKm'] as num).toDouble() : 4.0;
      _allowed = (m['allowedCategoryIds'] is List) ? List<String>.from(m['allowedCategoryIds']) : const <String>[];
      setState(() {
        _registered = List<String>.from(reg);
        _radiusKm = r.clamp(1.0, 15.0);
        _loaded = true;
      });
    } catch (_) {
      setState(() => _loaded = true);
    }
  }

  Future<void> _saveRegistered() async {
    if (_uid.isEmpty) return;
    await FirebaseFirestore.instance.collection('users').doc(_uid).set(
      {'registeredCategories': _registered, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Categories updated.')));
  }

  Future<void> _saveRadius(double r) async {
    if (_uid.isEmpty) return;
    setState(() => _radiusKm = r);
    await FirebaseFirestore.instance.collection('users').doc(_uid).set(
      {'serviceRadiusKm': r, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  void _openEdit(String? serviceId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddEditServiceScreen(serviceId: serviceId)),
    );
  }

  Future<void> _deleteService(String serviceId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete service?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance.collection('services').doc(serviceId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service deleted.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleActive(DocumentReference ref, bool next) async {
    try {
      await ref.set({'isActive': next, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _manageCategoriesDialog() async {
    final selected = Set<String>.from(_registered);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Select your categories'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final c in _kCategories)
                    CheckboxListTile(
                      dense: true,
                      title: Text(c),
                      value: selected.contains(c),
                      onChanged: (v) {
                        if (v == true) {
                          selected.add(c);
                        } else {
                          selected.remove(c);
                        }
                        setStateDialog(() {}); // rebuild dialog
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogCtx, selected), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() => _registered = result.toList());
    await _saveRegistered();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final q = FirebaseFirestore.instance
        .collection('services')
        .where('helperId', isEqualTo: _uid)
        .orderBy('updatedAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage services'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          // Registered categories
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Registered categories', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  if (_registered.isEmpty)
                    const Text('No categories yet. Choose what types of tasks you want to see.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _registered.map((c) {
                        final id = c.toLowerCase();
                        final isAllowed = _allowed.contains(id);
                        return Chip(
                          label: Text(isAllowed ? 'Verified • ${c.replaceAll('_',' ')}'
                              : 'Locked • ${c.replaceAll('_',' ')}'),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: isAllowed
                              ? Colors.green.withOpacity(0.12)
                              : Theme.of(context).colorScheme.surfaceVariant,
                          side: BorderSide(
                            color: isAllowed
                                ? Colors.green.withOpacity(0.2)
                                : Theme.of(context).colorScheme.outlineVariant,
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: _manageCategoriesDialog,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Manage'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_registered.any((c) => !_allowed.contains(c.toLowerCase())))
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () {
                          final locked = _registered.where((c) => !_allowed.contains(c.toLowerCase())).toList();
                          if (locked.isEmpty) return;
                          final nextCat = locked.first.toLowerCase();
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => step2.Step2Documents(initialCategoryId: nextCat),
                          ));
                        },
                        icon: const Icon(Icons.verified_user_rounded),
                        label: const Text('Verify next'),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Service radius
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Service radius', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          min: 1,
                          max: 15,
                          divisions: 14,
                          label: '${_radiusKm.toStringAsFixed(0)} km',
                          value: _radiusKm,
                          onChanged: (v) => setState(() => _radiusKm = v),
                          onChangeEnd: (v) => _saveRadius(v),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text('${_radiusKm.toStringAsFixed(0)} km', textAlign: TextAlign.end),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'We use this to show nearby tasks and recommendations.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Services list
          Text('Your services', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.limit(200).snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Card(
                  child: SizedBox(height: 88, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Card(
                  child: ListTile(
                    leading: Icon(Icons.miscellaneous_services_outlined),
                    title: Text('No services yet'),
                    subtitle: Text('Tap “Add service” to list what you offer.'),
                  ),
                );
              }

              return Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final m = d.data();
                    final isActive = m['isActive'] != false;
                    final title = (m['title'] ?? 'Service') as String;
                    final cat = (m['category'] ?? '-') as String;
                    final price = m['price'];

                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(title.isNotEmpty ? title[0].toUpperCase() : '?'),
                      ),
                      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text([cat, if (price != null) 'LKR $price'].join(' · ')),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          Switch(
                            value: isActive,
                            onChanged: (v) => _toggleActive(d.reference, v),
                          ),
                          IconButton(
                            tooltip: 'Edit',
                            onPressed: () => _openEdit(d.id),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () => _deleteService(d.id),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      onTap: () => _openEdit(d.id),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(null),
        icon: const Icon(Icons.add),
        label: const Text('Add service'),
      ),
    );
  }
}
