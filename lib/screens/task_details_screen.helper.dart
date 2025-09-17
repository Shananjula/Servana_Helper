// Servana_Helper/lib/screens/task_details_screen.dart
// Helper side — Task details with "Make Offer" and auto-open chat after submit.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:servana/services/chat_navigation.dart';

class TaskDetailsScreen extends StatefulWidget {
  final String taskId;
  final Map<String, dynamic>? initialTask; // optional preloaded task map

  const TaskDetailsScreen({
    super.key,
    required this.taskId,
    this.initialTask,
  });

  @override
  State<TaskDetailsScreen> createState() => _TaskDetailsScreenState();
}

class _TaskDetailsScreenState extends State<TaskDetailsScreen> {
  late final String _uid = FirebaseAuth.instance.currentUser!.uid;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.doc('tasks/${widget.taskId}').snapshots(),
      builder: (context, snap) {
        final data = (snap.data?.data() ?? widget.initialTask ?? const {}) as Map<String, dynamic>;
        final title = (data['title'] ?? data['taskTitle'] ?? 'Task').toString();
        final desc = (data['description'] ?? '').toString();
        final posterId = (data['posterId']
              ?? data['poster_id']
              ?? data['ownerId']
              ?? data['userId']
              ?? data['uid'])?.toString();
        final isOnline = (data['mode'] ?? data['serviceMode'] ?? 'online').toString().toLowerCase().contains('online');

        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: -6,
                  children: [
                    Chip(label: Text(isOnline ? 'Online' : 'Physical'), visualDensity: VisualDensity.compact),
                    if (data['city'] != null) Chip(label: Text(data['city'].toString()), visualDensity: VisualDensity.compact),
                  ],
                ),
                const Spacer(),
                SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _composeOffer(context, data, posterId),
                      icon: const Icon(Icons.local_offer_outlined),
                      label: Text(_busy ? 'Submitting…' : 'Make Offer'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _composeOffer(BuildContext context, Map<String, dynamic> task, String? posterId) async {
    final priceCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final res = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Your offer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Price'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, {
            'price': priceCtrl.text.trim(),
            'note': noteCtrl.text.trim(),
          }), child: const Text('Send')),
        ],
      ),
    );

    if (res == null) return;
    final price = num.tryParse(res['price'] ?? '');
    final note = (res['note'] ?? '').trim();
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid price.')));
      return;
    }

    await _saveOffer(price.toDouble(), note, task, posterId);
  }

  Future<void> _saveOffer(double amount, String note, Map<String, dynamic> task, String? posterId) async {
    setState(() => _busy = true);
    try {
      final now = FieldValue.serverTimestamp();
      final taskId = widget.taskId;

      // Resolve posterId robustly
      final posterIdResolved = (posterId
        ?? task['posterId']
        ?? task['poster_id']
        ?? task['ownerId']
        ?? task['userId']
        ?? task['uid']
        ?? '').toString();

      final payload = <String, dynamic>{
        'taskId': taskId,
        'helperId': _uid,
        'price': amount,
        'amount': amount,
        'message': note,
        'status': 'pending',
        'origin': 'public',
        'title': (task['title'] ?? task['taskTitle'] ?? '').toString(),
        'posterId': posterIdResolved.isNotEmpty ? posterIdResolved : null,
        'createdAt': now,
        'updatedAt': now,
      }..removeWhere((k, v) => v == null);

      // Write into subcollection (canonical)
      final ref = FirebaseFirestore.instance.collection('tasks/$taskId/offers').doc();
      await ref.set(payload);

      // ✅ Jump to chat with poster
      if (posterIdResolved.isNotEmpty) {
        await openChatWith(
          context: context,
          posterId: posterIdResolved,
          helperId: _uid,
          taskId: taskId,
        );
      } else {
        // Fallback: try to open by resolving poster from task
        await openChatWith(
          context: context,
          taskId: taskId,
          helperId: _uid,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer sent.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send offer: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
