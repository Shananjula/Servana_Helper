
// Replace the entire existing _OfferActions widget with this one.
// It compiles standalone and wires: safe offer payload, create/update, withdraw, and chat navigation.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:servana/services/chat_service.dart';
import 'package:servana/screens/chat_thread_screen.dart';

class _OfferActions extends StatefulWidget {
  const _OfferActions({
    required this.taskId,
    required this.task,
    this.enabled = true,
  });

  final String taskId;
  final Map<String, dynamic> task;
  final bool enabled;

  @override
  State<_OfferActions> createState() => _OfferActionsState();
}

class _OfferActionsState extends State<_OfferActions> {
  bool _busy = false;
  String? _err;
  Map<String, dynamic>? _my; // last offer by me on this task

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _offersCol =>
      FirebaseFirestore.instance.collection('tasks').doc(widget.taskId).collection('offers');

  @override
  void initState() {
    super.initState();
    _loadMy();
  }

  Future<void> _loadMy() async {
    try {
      final q = await _offersCol
          .where('helperId', isEqualTo: _uid)
          .orderBy('updatedAt', descending: true)
          .limit(1)
          .get();
      setState(() => _my = q.docs.isEmpty ? null : q.docs.first.data());
    } catch (e) {
      // ignore; section can render without it
    }
  }

  Future<void> _withdraw() async {
    setState(() => _busy = true);
    try {
      final q = await _offersCol
          .where('helperId', isEqualTo: _uid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        await q.docs.first.reference.update({
          'status': 'withdrawn',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await _loadMy();
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveOffer(double amount, String note) async {
    setState(() => _busy = true);
    try {
      final now = FieldValue.serverTimestamp();
      final t = widget.task;

      // Resolve posterId safely
      final posterIdFromTask = (t['posterId'] ?? t['poster_id'] ?? t['ownerId'] ?? t['userId'] ?? t['uid'] ?? null)?.toString();

      final payload = <String, dynamic>{
        'taskId': widget.taskId,
        'helperId': _uid,
        'price': amount,
        'amount': amount,
        'message': note,
        'status': 'pending',
        'createdAt': now,
        'updatedAt': now,
        if (posterIdFromTask != null && posterIdFromTask.isNotEmpty) 'posterId': posterIdFromTask,
      };

      // Create or update my latest offer
      final q = await _offersCol
          .where('helperId', isEqualTo: _uid)
          .orderBy('updatedAt', descending: true)
          .limit(1)
          .get();

      if (q.docs.isEmpty) {
        await _offersCol.add(payload);
      } else {
        final prev = q.docs.first.data();
        final prevStatus = (prev['status'] ?? 'pending').toString();
        if (prevStatus == 'pending' || prevStatus == 'counter') {
          await q.docs.first.reference.update({
            'price': amount,
            'amount': amount,
            'message': note,
            'status': 'pending',
            'updatedAt': now,
          });
        } else {
          await _offersCol.add(payload);
        }
      }

      // Ensure chat exists and navigate
      final posterId = posterIdFromTask ?? '';
      await ChatService().ensureChat(
        taskId: widget.taskId,
        posterId: posterId,
        helperId: _uid,
        taskPreview: {
          'title': (t['title'] ?? '').toString(),
          'category': (t['mainCategory'] ?? t['mainCategoryId'] ?? '').toString(),
          'mode': (t['isPhysical'] == true) ? 'physical' : 'online',
        },
      );
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadScreen(
          taskId: widget.taskId, posterId: posterId, helperId: _uid,
        )));
      }

      await _loadMy();
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openSheet() {
    final controller = TextEditingController(
      text: ((_my?['price'] ?? _my?['amount'])?.toString() ?? ''),
    );
    final noteC = TextEditingController(text: (_my?['message'] ?? '').toString());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Make an offer', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount (LKR)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteC,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () {
                      final amt = double.tryParse(controller.text.trim());
                      if (amt == null) return;
                      Navigator.of(ctx).pop();
                      _saveOffer(amt, noteC.text.trim());
                    },
                    child: const Text('Send offer'),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatLkr(dynamic v) {
    final n = (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return 'LKR ${n.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final dis = !widget.enabled || _busy;
    final status = (_my?['status'] ?? 'none').toString();
    final counter = _my?['counterPrice'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.handshake_outlined, size: 18),
                const SizedBox(width: 8),
                Text('Offers', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_err!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 8),
            if (!widget.enabled)
              const Text('You’re not eligible to make an offer on this task.'),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: dis ? null : _openSheet,
                  icon: const Icon(Icons.local_offer_outlined),
                  label: Text(_my == null ? 'Make offer' : 'Edit offer'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: dis || _my == null ? null : _withdraw,
                  icon: const Icon(Icons.undo_outlined),
                  label: const Text('Withdraw'),
                ),
              ],
            ),
            if (counter != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.swap_horiz, size: 16),
                  const SizedBox(width: 6),
                  Text('Counter offered: ${_formatLkr(counter)}'),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: dis ? null : () => _saveOffer((counter as num).toDouble(), (_my?['message'] ?? '').toString()),
                    child: const Text('Accept counter'),
                  ),
                ],
              ),
            ],
            if (_my != null) ...[
              const SizedBox(height: 10),
              Text('Your offer: ${_formatLkr(_my?['price'] ?? _my?['amount'])}'),
              Text('Status: $status'),
            ]
          ],
        ),
      ),
    );
  }
}
