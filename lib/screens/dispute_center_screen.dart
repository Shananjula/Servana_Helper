// lib/screens/dispute_center_screen.dart  (Helper)
// Dispute Center: list disputes for current user, open detail, add evidence, resolve.
// Requires: cloud_firestore, firebase_auth, FirestoreService with resolve/addEvidence callables wired.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:servana/services/firestore_service.dart';

class DisputeCenterScreen extends StatelessWidget {
  const DisputeCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in.')),
      );
    }

    final query = FirebaseFirestore.instance
        .collection('disputes')
        .where('participants', arrayContains: uid)
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Dispute Center')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No disputes found.'));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final id = docs[i].id;
              final taskId = d['taskId'] ?? '-';
              final status = d['status'] ?? 'open';
              final title = d['title'] ?? 'Dispute';
              final createdAt = (d['createdAt'] as Timestamp?)?.toDate();

              return ListTile(
                title: Text(title),
                subtitle: Text('Task: $taskId • Status: $status'
                    '${createdAt != null ? ' • ${createdAt.toLocal()}' : ''}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DisputeDetailScreen(disputeId: id),
                  ));
                },
              );
            },
          );
        },
      ),
    );
  }
}

class DisputeDetailScreen extends StatefulWidget {
  final String disputeId;
  const DisputeDetailScreen({super.key, required this.disputeId});

  @override
  State<DisputeDetailScreen> createState() => _DisputeDetailScreenState();
}

class _DisputeDetailScreenState extends State<DisputeDetailScreen> {
  final _fs = FirestoreService();
  final _notesCtrl = TextEditingController();
  String _selectedResolution = 'refund_poster'; // default
  int? _posterDelta;
  int? _helperDelta;
  bool _busy = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _addEvidenceUrl() async {
    final url = await _promptText(
      context,
      title: 'Add evidence URL',
      hint: 'https://…',
    );
    if (url == null || url.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _fs.addEvidenceToDispute(widget.disputeId, url);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Evidence added')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolve() async {
    setState(() => _busy = true);
    try {
      await _fs.resolveDispute(
        widget.disputeId,
        resolution: _selectedResolution,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        posterCoinDelta: _posterDelta,
        helperCoinDelta: _helperDelta,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Dispute resolved')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disputeRef =
    FirebaseFirestore.instance.collection('disputes').doc(widget.disputeId);

    return Scaffold(
      appBar: AppBar(title: Text('Dispute #${widget.disputeId.substring(0, 6)}')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: disputeRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Dispute not found.'));
          }
          final d = snap.data!.data()!;
          final status = d['status'] ?? 'open';
          final taskId = d['taskId'] ?? '-';
          final posterId = d['posterId'] ?? '-';
          final helperId = d['helperId'] ?? '-';
          final evidence = d['evidence'] as List<dynamic>?; // optional flat array
          // Also support subcollection evidence:
          final evidenceQuery = disputeRef.collection('evidence').orderBy('createdAt', descending: true);

          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Chip(label: Text('Status: $status')),
                    const SizedBox(width: 8),
                    Chip(label: Text('Task: $taskId')),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Poster: $posterId\nHelper: $helperId'),
                const SizedBox(height: 16),

                // Notes input
                TextField(
                  controller: _notesCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // Resolution chooser
                Row(
                  children: [
                    const Text('Resolution:'),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _selectedResolution,
                      items: const [
                        DropdownMenuItem(value: 'refund_poster', child: Text('Refund Poster')),
                        DropdownMenuItem(value: 'pay_helper', child: Text('Pay Helper')),
                        DropdownMenuItem(value: 'split', child: Text('Split')),
                      ],
                      onChanged: (v) => setState(() => _selectedResolution = v!),
                    ),
                  ],
                ),

                // Optional coin deltas
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _NumberField(
                        label: 'Poster coin Δ (optional)',
                        onChanged: (v) => _posterDelta = v,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _NumberField(
                        label: 'Helper coin Δ (optional)',
                        onChanged: (v) => _helperDelta = v,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Evidence (inline array if present)
                if (evidence != null && evidence.isNotEmpty) ...[
                  const Text('Evidence (inline):', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...evidence.map((e) => SelectableText(e.toString())).toList(),
                  const SizedBox(height: 16),
                ],

                // Evidence subcollection
                const Text('Evidence', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: evidenceQuery.snapshots(),
                  builder: (context, esnap) {
                    if (esnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final edocs = esnap.data?.docs ?? [];
                    if (edocs.isEmpty) {
                      return const Text('No evidence uploaded yet.');
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: edocs.map((doc) {
                        final e = doc.data();
                        final url = e['url'] ?? '';
                        final by = e['addedBy'] ?? '';
                        final at = (e['createdAt'] as Timestamp?)?.toDate();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('• $url  (by $by${at != null ? ', ${at.toLocal()}' : ''})'),
                        );
                      }).toList(),
                    );
                  },
                ),

                const SizedBox(height: 16),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _addEvidenceUrl,
                      icon: const Icon(Icons.attachment),
                      label: const Text('Add evidence URL'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _busy ? null : _resolve,
                      icon: const Icon(Icons.gavel),
                      label: const Text('Resolve'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<String?> _promptText(BuildContext context,
      {required String title, required String hint}) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    return ctrl.text.trim();
  }
}

class _NumberField extends StatefulWidget {
  final String label;
  final void Function(int?) onChanged;
  const _NumberField({required this.label, required this.onChanged});

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (s) {
        final v = int.tryParse(s.trim());
        widget.onChanged(v);
      },
    );
  }
}
