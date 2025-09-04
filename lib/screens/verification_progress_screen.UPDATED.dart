import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/verification_service.dart';
import '../service_categories.dart';
import 'step_2_documents.dart';
import 'helper_dashboard_screen.dart';
import '../utils/verification_nav.dart';

class VerificationProgressScreen extends StatelessWidget {
  const VerificationProgressScreen({super.key, this.lockBack = false});
  final bool lockBack;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Please sign in')));

    final basicRef = FirebaseFirestore.instance.collection('basic_docs').doc(uid);
    // OLD (remove this):
    // final proofsQ  = FirebaseFirestore.instance
    //     .collection('category_proofs')
    //     .where('userId', isEqualTo: uid)
    //     .orderBy('updatedAt', descending: true)
    //     .snapshots();

    // NEW: two streams (userId == uid) OR (uid == uid)
    final proofsColl = FirebaseFirestore.instance.collection('category_proofs');
    final proofsByUserId = proofsColl.where('userId', isEqualTo: uid).snapshots();
    final proofsByUid    = proofsColl.where('uid',    isEqualTo: uid).snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Verification Progress'), automaticallyImplyLeading: false),
      body: StreamBuilder<DocumentSnapshot>(
        stream: basicRef.snapshots(),
        builder: (context, basicSnap) {
          final basic = (basicSnap.data?.data() as Map<String, dynamic>?) ?? {};
          return StreamBuilder<QuerySnapshot>(
            stream: proofsByUserId,
            builder: (context, snapA) {
              return StreamBuilder<QuerySnapshot>(
                stream: proofsByUid,
                builder: (context, snapB) {
                  // Merge & de-duplicate by document id
                  final Map<String, Map<String, dynamic>> merged = {};

                  for (final d in (snapA.data?.docs ?? <QueryDocumentSnapshot>[])) {
                    final m = d.data() as Map<String, dynamic>;
                    merged[d.id] = {'id': d.id, ...m};
                  }
                  for (final d in (snapB.data?.docs ?? <QueryDocumentSnapshot>[])) {
                    final m = d.data() as Map<String, dynamic>;
                    merged[d.id] = {'id': d.id, ...m};
                  }

                  // Sort by updatedAt desc (gracefully handle missing field)
                  int ts(Map<String, dynamic> m) {
                    final t = m['updatedAt'];
                    if (t is Timestamp) return t.millisecondsSinceEpoch;
                    if (t is DateTime)  return t.millisecondsSinceEpoch;
                    return 0;
                  }
                  final proofs = merged.values.toList()
                    ..sort((a, b) => ts(b).compareTo(ts(a)));

                  
                  // Determine if anything is approved
                  bool basicApproved = (basic['status'] ?? '') == 'approved';
                  bool anyApproved = basicApproved || proofs.any((e) => (e['status'] ?? '') == 'approved');
                  final bool hideBack = lockBack || anyApproved;

                  return WillPopScope(
                    onWillPop: () async => !hideBack,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (!hideBack) 
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => Navigator.of(context).maybePop(),
                              tooltip: 'Back',
                            ),
                          ),
                        _header('Physical — Basic Documents'),
                        _BasicCard(basic: basic),
                        const SizedBox(height: 16),
                        _header('Category Verifications'),
                        if (proofs.isEmpty)
                          const _Empty(text: 'No category proofs submitted yet.'),
                        for (final m in proofs) _ProofCard(m: m),
                        const SizedBox(height: 24),
                        if (hideBack) ...[
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(builder: (_) => const HelperDashboardScreen()),
                                (route) => false,
                              );
                            },
                            icon: const Icon(Icons.dashboard_rounded),
                            label: const Text('Go to Helper Dashboard'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              // You are already here; simply refresh the streams by rebuilding
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('You are viewing progress')),
                              );
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Check progress'),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Center(
                          child: OutlinedButton.icon(
                            onPressed: () => VerificationNav.openDocs(context),
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('Upload more documents'),
                          ),
                        ),
                      ],
                    ),
                  );

                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _header(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
  );
}

class _BasicCard extends StatelessWidget {
  final Map<String, dynamic> basic;
  const _BasicCard({required this.basic});

  @override
  Widget build(BuildContext context) {
    final status = (basic['status'] ?? 'not_submitted') as String;
    final notes  = basic['notes'] as String?;
    final uid    = FirebaseAuth.instance.currentUser!.uid;

    return _CardScaffold(
      title: 'Basic documents (NIC / Selfie / Police)',
      status: status,
      notes: notes,
      activityPath: FirebaseFirestore.instance.collection('basic_docs').doc(uid).collection('activity'),
      onStartAgain: () => VerificationNav.startPhysical(context),
      categoryId: 'basic',
    );
  }
}

class _ProofCard extends StatelessWidget {
  final Map<String, dynamic> m;
  const _ProofCard({required this.m});

  @override
  Widget build(BuildContext context) {
    final catId = m['categoryId'] ?? '—';
    final label = _labelFor(catId);
    final status = (m['status'] ?? 'pending') as String;
    final notes = m['notes'] as String?;
    final docId = m['id'] as String;
    final mode  = (m['mode'] ?? 'online') as String;

    return _CardScaffold(
      title: '$label  •  ${mode.toUpperCase()}',
      status: status,
      notes: notes,
      activityPath: FirebaseFirestore.instance
          .collection('category_proofs').doc(docId).collection('activity'),
      onStartAgain: () {
        final vm = mode == 'online' ? VerificationMode.online : VerificationMode.physical;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => Step2Documents(mode: vm, selectedCategoryIds: [catId])),
        );
      },
      categoryId: catId,
    );
  }
}

class _CardScaffold extends StatelessWidget {
  final String title;
  final String status; // pending | processing | approved | rejected | needs_more_info | not_submitted
  final String? notes;
  final CollectionReference activityPath;
  final VoidCallback onStartAgain;
  final String categoryId;

  const _CardScaffold({
    required this.title,
    required this.status,
    required this.notes,
    required this.activityPath,
    required this.onStartAgain,
    required this.categoryId,
  });

  @override
  Widget build(BuildContext context) {
    final stage = _stageIndex(status);
    final color = _statusColor(context, status);
    final failed = status == 'rejected';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            const SizedBox(width: 8),
            Chip(label: Text(_pretty(status)), backgroundColor: color.withOpacity(.12),
                labelStyle: TextStyle(color: color)),
          ]),
          const SizedBox(height: 12),
          _Steps(current: stage, failed: failed),
          if (notes != null && notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _Reason(notes: notes!),
            const SizedBox(height: 8),
            _Guidance(categoryId: categoryId),
          ],
          const SizedBox(height: 8),
          // History (timeline)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('History', style: TextStyle(fontWeight: FontWeight.w600)),
            children: [
              _ActivityList(activityPath: activityPath),
            ],
          ),
          const SizedBox(height: 8),
          if (status == 'rejected' || status == 'needs_more_info')
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: onStartAgain,
                icon: const Icon(Icons.refresh),
                label: Text(status == 'rejected' ? 'Start again' : 'Add info'),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  final int current; // 0 submitted, 1 processing, 2 approved
  final bool failed;
  const _Steps({required this.current, required this.failed});

  @override
  Widget build(BuildContext context) {
    List<_StepData> steps = const [
      _StepData('Submitted', Icons.outbox),
      _StepData('Processing', Icons.autorenew),
      _StepData('Approved', Icons.verified),
    ];
    return Column(children: List.generate(steps.length, (i) {
      final active = i == current && !failed;
      final done = i < current;
      final icon = failed && i == current ? Icons.close_rounded
          : (done ? Icons.check_circle : (active ? steps[i].icon : Icons.radio_button_unchecked));
      final color = failed && i == current ? Colors.red
          : (done || active) ? Theme.of(context).colorScheme.primary : Colors.grey;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(steps[i].label)),
        ]),
      );
    }));
  }
}
class _StepData { final String label; final IconData icon; const _StepData(this.label, this.icon); }

class _Reason extends StatelessWidget {
  final String notes;
  const _Reason({required this.notes});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(.2)),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, color: Colors.red, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(notes, style: const TextStyle(color: Colors.red))),
      ]),
    );
  }
}

// Quick, generic guidance block; optionally reads /categories/{id}.guidelines if present.
class _Guidance extends StatelessWidget {
  final String categoryId;
  const _Guidance({required this.categoryId});
  @override
  Widget build(BuildContext context) {
    if (categoryId == 'basic') {
      return _Tips(title: 'How to pass basic verification next time', tips: const [
        'NIC/Passport: clear, full frame, no glare.',
        'Selfie: good lighting, face centered, no filters.',
        'Police clearance: full document, readable text (PDF or sharp photo).',
      ]);
    }
    // You can store tips per category in /categories/{id}.guidelines (array<string>)
    final ref = FirebaseFirestore.instance.collection('categories').doc(categoryId);
    return FutureBuilder<DocumentSnapshot>(
      future: ref.get(),
      builder: (context, snap) {
        final m = snap.data?.data() as Map<String, dynamic>?;
        final tips = (m?['guidelines'] is List) ? List<String>.from(m!['guidelines']) : const <String>[];
        if (tips.isEmpty) {
          return _Tips(title: 'How to submit proofs that get approved', tips: const [
            'Upload at least 2–3 samples that clearly show your skill for this category.',
            'Use bright, in-focus images or a single PDF bundle; avoid screenshots with watermarks.',
            'If it’s on-site work, include before/after photos or short descriptions.',
            'Keep files under 15 MB each.',
          ]);
        }
        return _Tips(title: 'Tips for this category', tips: tips);
      },
    );
  }
}

class _Tips extends StatelessWidget {
  final String title;
  final List<String> tips;
  const _Tips({required this.title, required this.tips});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        for (final t in tips) Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('•  '),
            Expanded(child: Text(t)),
          ]),
        ),
      ]),
    );
  }
}

class _ActivityList extends StatelessWidget {
  final CollectionReference activityPath;
  const _ActivityList({required this.activityPath});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: activityPath.orderBy('ts', descending: true).limit(100).snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No activity yet.', style: TextStyle(color: Colors.grey)),
          );
        }

        IconData iconFor(Map<String, dynamic> m) {
          final t = (m['type'] ?? '').toString();
          final s = (m['status'] ?? m['to'] ?? '').toString();
          switch (s) {
            case 'approved': return Icons.verified;
            case 'rejected': return Icons.block;
            case 'needs_more_info': return Icons.help_outline;
            case 'processing': return Icons.autorenew;
            case 'pending': return Icons.outbox;
            default:
              return t == 'note' ? Icons.sticky_note_2_outlined : Icons.timeline;
          }
        }

        Color colorFor(BuildContext c, Map<String, dynamic> m) {
          final s = (m['status'] ?? m['to'] ?? '').toString();
          switch (s) {
            case 'approved': return Colors.green;
            case 'rejected': return Colors.red;
            case 'needs_more_info': return Colors.orange;
            case 'processing': return Theme.of(c).colorScheme.primary;
            case 'pending': default: return Colors.grey;
          }
        }

        String labelFor(Map<String, dynamic> m) {
          final t = (m['type'] ?? '').toString();
          if (t == 'submitted') return 'Submitted';
          if (t == 'note') return 'Note';
          if (t == 'status_change') {
            final f = (m['from'] ?? '').toString().replaceAll('_', ' ');
            final to = (m['to'] ?? '').toString().replaceAll('_', ' ');
            return 'Status: $f → $to';
          }
          final s = (m['status'] ?? '').toString().replaceAll('_', ' ');
          return s.isEmpty ? 'Update' : s[0].toUpperCase() + s.substring(1);
        }

        String whenOf(Timestamp? ts) {
          if (ts == null) return '';
          final d = ts.toDate();
          String two(int x) => x.toString().padLeft(2, '0');
          return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
        }

        return Column(
          children: docs.map((d) {
            final m = d.data() as Map<String, dynamic>;
            final ts = m['ts'] as Timestamp?;
            final who = (m['by'] ?? '').toString();
            final notes = (m['notes'] ?? m['note'] ?? '').toString();
            final color = colorFor(context, m);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(iconFor(m), size: 20, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: DefaultTextStyle.of(context).style,
                            children: [
                              TextSpan(text: labelFor(m), style: TextStyle(fontWeight: FontWeight.w600, color: color)),
                              if (who.isNotEmpty) TextSpan(text: '  •  by $who', style: const TextStyle(color: Colors.grey)),
                              if (ts != null) TextSpan(text: '  •  ${whenOf(ts)}', style: const TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: color.withOpacity(0.2)),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Text(notes),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// helpers
String _labelFor(String id) {
  final all = [...kOnlineCategories, ...kPhysicalCategories];
  final hit = all.where((c) => c.id == id).toList();
  return hit.isEmpty ? id : hit.first.label;
}
String _pretty(String s) => s.replaceAll('_', ' ').trim();

int _stageIndex(String s) {
  switch (s) {
    case 'approved': return 2;
    case 'processing': return 1;
    case 'pending':
    case 'not_submitted':
    case 'needs_more_info':
    case 'rejected':  return 0;  // Submitted stage
    default: return 0;
  }
}

Color _statusColor(BuildContext context, String s) {
  switch (s) {
    case 'approved': return Colors.green;
    case 'rejected': return Colors.red;
    case 'needs_more_info': return Colors.orange;
    case 'processing': return Theme.of(context).colorScheme.primary;
    case 'pending':
    default: return Theme.of(context).colorScheme.primary.withOpacity(.8);
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(text, style: const TextStyle(color: Colors.grey)),
      ),
    );
  }
}

