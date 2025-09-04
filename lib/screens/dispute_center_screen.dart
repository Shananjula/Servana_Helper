// lib/screens/dispute_center_screen.dart
//
// Dispute Center (Helper app)
// ---------------------------
// • Lists disputes where the current user is a participant
// • Detail sheet shows status, notes, basic fields, and evidence URLs
// • Add evidence (URL) → disputes/{id}.evidenceUrls (arrayUnion)
// • Tolerant to schemas that store participants or poster/helper ids
//
// Firestore shapes (tolerant):
//   disputes/{id} {
//     taskId, title?, reason?, status: 'open'|'in_review'|'resolved'|'rejected',
//     posterId?, helperId?, participants?: [uid],
//     resolution?, resolutionNotes?,
//     evidenceUrls?: [string],
//     createdAt, updatedAt
//   }

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DisputeCenterScreen extends StatelessWidget {
  const DisputeCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Please sign in.')));
    }

    // Primary: participants array; fallback: helperId/posterId
    final base = FirebaseFirestore.instance.collection('disputes');
    final stream = base
        .where('participants', arrayContains: uid)
        .orderBy('updatedAt', descending: true)
        .limit(200)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Dispute Center')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }

          var docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            // Fallback if array field not present: union of helperId/posterId filters (best-effort)
            final alt = FirebaseFirestore.instance
                .collection('disputes')
                .where('helperId', isEqualTo: uid)
                .orderBy('updatedAt', descending: true)
                .limit(200)
                .snapshots();
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: alt,
              builder: (context, altSnap) {
                final d2 = altSnap.data?.docs ?? const [];
                if (altSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                }
                if (d2.isEmpty) {
                  return const Center(child: Text('No disputes.'));
                }
                return _DisputeList(docs: d2);
              },
            );
          }

          return _DisputeList(docs: docs);
        },
      ),
    );
  }
}

class _DisputeList extends StatelessWidget {
  const _DisputeList({required this.docs});
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final d = docs[i];
        final m = d.data();
        final title = (m['title'] ?? 'Dispute').toString();
        final status = (m['status'] ?? 'open').toString();
        final taskId = (m['taskId'] ?? '').toString();

        return Card(
          child: ListTile(
            leading: const Icon(Icons.report_gmailerrorred_outlined),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text([
              'Status: ${status.toUpperCase()}',
              if (taskId.isNotEmpty) 'Task: $taskId',
            ].join(' • ')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showModalBottomSheet(
              context: _,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _DisputeDetailSheet(disputeId: d.id),
            ),
          ),
        );
      },
    );
  }
}

class _DisputeDetailSheet extends StatefulWidget {
  const _DisputeDetailSheet({required this.disputeId});
  final String disputeId;

  @override
  State<_DisputeDetailSheet> createState() => _DisputeDetailSheetState();
}

class _DisputeDetailSheetState extends State<_DisputeDetailSheet> {
  bool _adding = false;

  Future<void> _addEvidenceUrl() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add evidence URL'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'https://…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    final url = ctrl.text.trim();
    if (url.isEmpty) return;

    setState(() => _adding = true);
    try {
      await FirebaseFirestore.instance.collection('disputes').doc(widget.disputeId).set({
        'evidenceUrls': FieldValue.arrayUnion([url]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Evidence added.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ref = FirebaseFirestore.instance.collection('disputes').doc(widget.disputeId);

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: ref.snapshots(),
          builder: (context, snap) {
            final m = snap.data?.data() ?? const <String, dynamic>{};

            final title = (m['title'] ?? 'Dispute').toString();
            final status = (m['status'] ?? 'open').toString();
            final reason = (m['reason'] ?? '').toString();
            final resolution = (m['resolution'] ?? '').toString();
            final resolutionNotes = (m['resolutionNotes'] ?? '').toString();
            final evidence = (m['evidenceUrls'] is List)
                ? List<String>.from(m['evidenceUrls'] as List)
                : const <String>[];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    _StatusChip(status: status),
                  ],
                ),
                const SizedBox(height: 8),

                if (reason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(reason),
                  ),

                if (resolution.isNotEmpty || resolutionNotes.isNotEmpty)
                  Card(
                    color: cs.surfaceContainerHigh,
                    child: ListTile(
                      leading: const Icon(Icons.rule_folder_outlined),
                      title: Text('Resolution: ${resolution.isEmpty ? '—' : resolution}'),
                      subtitle: resolutionNotes.isEmpty ? null : Text(resolutionNotes),
                    ),
                  ),

                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.icon(
                      icon: _adding
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Add evidence'),
                      onPressed: _adding ? null : _addEvidenceUrl,
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Text('Evidence', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),

                Expanded(
                  child: evidence.isEmpty
                      ? Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outline.withOpacity(0.12)),
                    ),
                    child: const Text('No evidence yet.'),
                  )
                      : ListView.separated(
                    controller: controller,
                    itemCount: evidence.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => SelectableText(
                      evidence[i],
                      maxLines: 2,
                      style: const TextStyle(decoration: TextDecoration.underline),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = status.toLowerCase();
    Color bg = cs.surfaceVariant, fg = cs.onSurfaceVariant;
    String text = s.toUpperCase();
    if (s.contains('open')) {
      bg = cs.secondaryContainer; fg = cs.onSecondaryContainer; text = 'OPEN';
    } else if (s.contains('review')) {
      bg = Colors.amber.withOpacity(0.18); fg = Colors.amber.shade900; text = 'IN REVIEW';
    } else if (s.contains('resolve')) {
      bg = Colors.green.withOpacity(0.18); fg = Colors.green.shade900; text = 'RESOLVED';
    } else if (s.contains('reject')) {
      bg = cs.errorContainer; fg = cs.onErrorContainer; text = 'REJECTED';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outline.withOpacity(0.12)),
      ),
      child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
    );
  }
}
