
// lib/screens/helper_browse_tasks_screen.dart
//
// Helper → Find Work (Apply only if eligible; otherwise Verify CTA)
// Implements Map v2.2:
//  - Feed shows tasks with status in ['listed','open']
//  - Optional 'Eligible only' toggle to narrow by categoryId IN allowedCategoryIds
//  - Each card: Apply button only if helper is eligible for task.categoryId; else 'Verify to apply'
//  - Fixes Timestamp const usage issues (never use `const Timestamp(...)`)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HelperBrowseTasksScreen extends StatefulWidget {
  const HelperBrowseTasksScreen({super.key});

  @override
  State<HelperBrowseTasksScreen> createState() => _HelperBrowseTasksScreenState();
}

class _HelperBrowseTasksScreenState extends State<HelperBrowseTasksScreen> with AutomaticKeepAliveClientMixin {
  bool _eligibleOnly = false;
  String? _error;
  List<String> _allowed = const <String>[];

  @override
  void initState() {
    super.initState();
    _loadAllowed();
  }

  Future<void> _loadAllowed() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    setState(() {
      _allowed = (data['allowedCategoryIds'] is List)
          ? List<String>.from(data['allowedCategoryIds'])
          : const <String>[];
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final base = FirebaseFirestore.instance
        .collection('tasks')
        .where('status', whereIn: ['listed', 'open']);

    final query = _eligibleOnly && _allowed.isNotEmpty
        ? base.where('categoryId', whereIn: _allowed.take(10).toList()) // Firestore whereIn <= 10
        : base;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find work'),
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
            return const Center(child: Text('No tasks available.'));
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

  Future<void> _apply(String taskId, Map<String, dynamic> t) async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      // Offer doc under tasks/{taskId}/offers (rules ensure eligibility server-side)
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
    // Navigate to your verification flow; placeholder:
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Please verify the category ${categoryId ?? ""} first.')),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
