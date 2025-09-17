// lib/screens/helper_browse_tasks_screen.dart
//
// Helper → Find Work (Map v2.2 compatible)
// - Constructor: initialCategoryId, initialOnlyVerified (kept for dashboard deep-links)
// - Feed shows tasks with status in ['listed','open']
// - 'Eligible only' toggle narrows to categoryId IN allowedCategoryIds (batched <=10)
// - If a category filter is passed in, we filter by that exact categoryId
// - Each card: Apply only if helper is eligible; otherwise 'Verify to apply'
//
// Deps: cloud_firestore, firebase_auth, flutter/material

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HelperBrowseTasksScreen extends StatefulWidget {
  final String? initialCategoryId;
  final bool initialOnlyVerified;
  const HelperBrowseTasksScreen({super.key, this.initialCategoryId, this.initialOnlyVerified = false});

  @override
  State<HelperBrowseTasksScreen> createState() => _HelperBrowseTasksScreenState();
}

class _HelperBrowseTasksScreenState extends State<HelperBrowseTasksScreen> with AutomaticKeepAliveClientMixin {
  bool _eligibleOnly = false;
  String? _selectedCatId;
  String? _error;
  List<String> _allowed = const <String>[];

  @override
  void initState() {
    super.initState();
    _eligibleOnly = widget.initialOnlyVerified;
    _selectedCatId = widget.initialCategoryId;
    _loadAllowed();
  }

  Future<void> _loadAllowed() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final d = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = d.data() ?? {};
      final allowed = (data['allowedCategoryIds'] is List)
          ? List<String>.from(data['allowedCategoryIds'])
          : const <String>[];
      setState(() => _allowed = allowed);
    } catch (e) {
      setState(() => _error = 'Failed to load eligibility: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final base = FirebaseFirestore.instance
        .collection('tasks')
        .where('status', whereIn: ['listed', 'open']);

    Query<Map<String, dynamic>> query = base;
    if (_selectedCatId != null && _selectedCatId!.isNotEmpty) {
      query = query.where('categoryId', isEqualTo: _selectedCatId);
    } else if (_eligibleOnly && _allowed.isNotEmpty) {
      query = query.where('categoryId', whereIn: _allowed.take(10).toList());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find work'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Container(
            alignment: Alignment.centerLeft,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              _selectedCatId == null
                  ? (_eligibleOnly ? 'Showing: Eligible categories' : 'Showing: All categories')
                  : 'Category filter: ${_selectedCatId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        actions: [
          Row(
            children: [
              const Text('Eligible only'),
              Switch(
                value: _eligibleOnly,
                onChanged: (v) => setState(() => _eligibleOnly = v),
              ),
            ],
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query.orderBy('createdAt', descending: true).limit(50).snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  final txt = _selectedCatId == null
                      ? (_eligibleOnly ? 'No eligible tasks right now.' : 'No tasks available.')
                      : 'No tasks for this category yet.';
                  return Center(child: Text(txt));
                }
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final t = d.data();
                    final title = (t['title'] ?? 'Task').toString();
                    final desc = (t['description'] ?? '').toString();
                    final mode = (t['mode'] ?? 'online').toString();
                    final categoryId = (t['categoryId'] ?? '').toString();
                    final eligible = _allowed.contains(categoryId);

                    return ListTile(
                      title: Text(title),
                      subtitle: Text([mode, if (desc.isNotEmpty) desc].join(' • ')),
                      isThreeLine: desc.length > 60,
                      trailing: eligible
                          ? FilledButton(
                              onPressed: () => _apply(d.id, t),
                              child: const Text('Apply'),
                            )
                          : OutlinedButton(
                              onPressed: () => _goVerify(categoryId),
                              child: const Text('Verify to apply'),
                            ),
                    );
                  },
                );
              },
            ),
    );
  }

  Future<void> _apply(String taskId, Map<String, dynamic> task) async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('tasks').doc(taskId).collection('offers').add({
        'taskId': taskId,
        'helperId': uid,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer sent.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to apply: $e')));
    }
  }

  void _goVerify(String? categoryId) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Please verify the category ${categoryId ?? ""} first.')),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
