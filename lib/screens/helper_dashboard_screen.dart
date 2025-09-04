// lib/screens/helper_dashboard_screen.dart
//
// Helper Dashboard (Phase 1)
// --------------------------
// • Greets user
// • Shows verification summary: allowedCategoryIds vs registeredCategories
// • Shortcuts: Browse (gated), My Jobs, Manage Services, Wallet, Verification (Step 2 & 3)
//
// Deps: cloud_firestore, firebase_auth, flutter/material

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:servana/providers/user_provider.dart';
import 'package:servana/widgets/mini_map_card.dart';

// Shortcuts
import 'package:servana/screens/helper_browse_tasks_screen.dart';
import 'package:servana/screens/helper_active_task_screen.dart';
import 'package:servana/screens/manage_services_screen.dart';
import 'package:servana/screens/wallet_screen.dart';
import 'package:servana/screens/step_2_documents.dart' as step2;
import 'package:servana/screens/step_3_review.dart';

import '../service_categories.dart';
import '../utils/verification_nav.dart';
import 'step_1_services.dart' show Step1Services;
import '../services/verification_service.dart'; // for VerificationMode

class HelperDashboardScreen extends StatelessWidget {
  const HelperDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servana · Helper'),
        centerTitle: false,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(44),
          child: VerifiedOneRowChips(compact: true),
        ),
      ),
      body: uid == null
          ? const Center(child: Text('Please sign in.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream:
        FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final m = snap.data!.data() ?? {};
          final name = (m['displayName'] ?? '').toString().trim();
          final registered = _asList(m['registeredCategories']);
          final allowed = _asList(m['allowedCategoryIds']);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // Suggest verifying the first locked category
              if (allowed.length < registered.length) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => VerificationNav.startOnline(context),
                    icon: const Icon(Icons.verified_user_rounded),
                    label: const Text('Verify next'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _Greeting(name: name),

              // Live toggle card
              const SizedBox(height: 8),
              const _DashboardHeader(),
              const SizedBox(height: 12),

              // Needs-more-info nudge (per-category)
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('categoryEligibility')
                    .where('status', isEqualTo: 'needs_more_info')
                    .limit(20)
                    .snapshots(),
                builder: (context, nmiSnap) {
                  if (!nmiSnap.hasData || nmiSnap.data!.docs.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final items = nmiSnap.data!.docs.map((d) {
                    final m = d.data();
                    return (
                    categoryId: (m['categoryId'] ?? d.id).toString(),
                    notes: (m['notes'] ?? '').toString(),
                    );
                  }).toList();

                  return _NeedsMoreInfoCard(
                    items: items,
                    onFix: (catId) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => step2.Step2Documents(
                                initialCategoryId: catId)),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 8),

              const SizedBox(height: 12),
              _VerificationTimelineList(uid: uid),
              const SizedBox(height: 8),

              const SizedBox(height: 16),
              Text('Nearby tasks',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              MiniMapCard(mode: 'helper'),
              const SizedBox(height: 16),
              Text('Quick actions',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _QAButton(
                    icon: Icons.fact_check_outlined,
                    label: 'Review status',
                    onTap: () => VerificationNav.openProgress(context),
                  ),
                  const SizedBox(width: 12),
                  _QAButton(
                    icon: Icons.upload_file_outlined,
                    label: 'Upload docs',
                    onTap: () {
                      // choose which to open first; you can show a dialog here if needed
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const Step1Services(
                                mode: VerificationMode.physical)),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 16),
              if (registered.isNotEmpty &&
                  allowed.length < registered.length)
                _LockedHint(
                  locked: (registered.length - allowed.length)
                      .clamp(0, registered.length),
                  onDocs: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                          const step2.Step2Documents())),
                ),

              const SizedBox(height: 8),
              _Tips(),
            ],
          );
        },
      ),
    );
  }

  List<String> _asList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return const <String>[];
  }
}

class VerifiedOneRowChips extends StatelessWidget {
  const VerifiedOneRowChips({super.key, this.compact = true});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    final usersRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final proofs = FirebaseFirestore.instance.collection('category_proofs');

    // Stream A: allowedCategoryIds
    final allowed$ = usersRef.snapshots();

    // Stream B: approved proofs, via userId or legacy uid
    final approvedByUserId$ = proofs
        .where('userId', isEqualTo: uid)
        .where('status', whereIn: ['approved', 'verified'])
        .snapshots();
    final approvedByUid$ = proofs
        .where('uid', isEqualTo: uid)
        .where('status', whereIn: ['approved', 'verified'])
        .snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: allowed$,
      builder: (context, aSnap) {
        final allowed = (() {
          final m = aSnap.data?.data() as Map<String, dynamic>?;
          return (m?['allowedCategoryIds'] is List)
              ? Set<String>.from(m!['allowedCategoryIds'])
              : <String>{};
        })();

        return StreamBuilder<QuerySnapshot>(
          stream: approvedByUserId$,
          builder: (context, bSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: approvedByUid$,
              builder: (context, cSnap) {
                // Build an order map by latest approved updatedAt
                int tsOf(Map<String, dynamic> m) {
                  final t = m['updatedAt'];
                  if (t is Timestamp) return t.millisecondsSinceEpoch;
                  if (t is DateTime) return t.millisecondsSinceEpoch;
                  return 0;
                }

                final Map<String, int> lastApprovedTs = {};
                for (final d in (bSnap.data?.docs ?? const [])) {
                  final m = d.data() as Map<String, dynamic>;
                  lastApprovedTs[m['categoryId']] =
                      (lastApprovedTs[m['categoryId']] ?? 0)
                          .clamp(0, 1 << 30); // no-op; keep type happy
                  lastApprovedTs[m['categoryId']] = tsOf(m);
                }
                for (final d in (cSnap.data?.docs ?? const [])) {
                  final m = d.data() as Map<String, dynamic>;
                  lastApprovedTs[m['categoryId']] =
                  (lastApprovedTs[m['categoryId']] ?? 0);
                  lastApprovedTs[m['categoryId']] =
                  tsOf(m) > lastApprovedTs[m['categoryId']]!
                      ? tsOf(m)
                      : lastApprovedTs[m['categoryId']]!;
                }

                // Compose list: allowed categories ordered by lastApprovedTs desc,
                // then any remaining allowed with 0 timestamp sorted alphabetically.
                final ids = allowed.toList();
                ids.sort((a, b) {
                  final ta = lastApprovedTs[a] ?? 0;
                  final tb = lastApprovedTs[b] ?? 0;
                  if (tb != ta) return tb.compareTo(ta); // newest first
                  // tie-break alphabetically by label
                  return _labelFor(a).toLowerCase().compareTo(_labelFor(b).toLowerCase());
                });

                if (ids.isEmpty) return const SizedBox.shrink();

                return SizedBox(
                  height: compact ? 40 : 44,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    scrollDirection: Axis.horizontal,
                    itemCount: ids.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final id = ids[i];
                      final label = _labelFor(id).toLowerCase();
                      return InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _openBrowseForCategory(context, id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: Theme.of(context).colorScheme.primary.withOpacity(.12),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary.withOpacity(.35),
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  static String _labelFor(String id) {
    final all = [...kOnlineCategories, ...kPhysicalCategories];
    final hit = all.where((c) => c.id == id).toList();
    return hit.isEmpty ? id.replaceAll('_', ' ') : hit.first.label;
  }

  void _openBrowseForCategory(BuildContext context, String categoryId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HelperBrowseTasksScreen(initialCategoryId: categoryId),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name});
  final String name;

  String _greet(int h) {
    if (h >= 5 && h < 12) return 'Good morning';
    if (h >= 12 && h < 17) return 'Good afternoon';
    if (h >= 17 && h < 22) return 'Good evening';
    return 'Hello';
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final text = name.isNotEmpty ? '${_greet(hour)}, $name' : _greet(hour);
    return Text(
      text,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.registeredCount,
    required this.allowedCount,
    required this.onReview,
  });

  final int registeredCount;
  final int allowedCount;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locked = (registeredCount - allowedCount).clamp(0, registeredCount);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: cs.primary.withOpacity(0.12),
                foregroundColor: cs.primary,
                child: const Icon(Icons.verified_user_outlined),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  allowedCount > 0
                      ? 'Verified in $allowedCount of $registeredCount categories'
                      : (registeredCount == 0
                      ? 'Choose your services to get started'
                      : 'You are not verified yet'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (locked > 0)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surfaceVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('$locked locked',
                      style: Theme.of(context).textTheme.labelSmall),
                ),
            ]),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReview,
                    icon: const Icon(Icons.list_alt_rounded),
                    label: const Text('Review status'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.upload_rounded),
                    label: const Text('Upload docs'),
                    onPressed: () async {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      String? initialCatId;

                      if (uid != null) {
                        final u = await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .get();
                        final m = u.data() ?? {};
                        final allowed =
                            (m['allowedCategoryIds'] as List?)?.cast<String>() ??
                                const <String>[];
                        final registered = (m['registeredCategories'] as List?)
                            ?.cast<String>() ??
                            const <String>[];
                        final pick = (allowed.isNotEmpty ? allowed : registered);
                        if (pick.isNotEmpty) {
                          // normalize: "AC Service" -> "ac_service"
                          initialCatId = pick.first
                              .trim()
                              .toLowerCase()
                              .replaceAll(RegExp(r'\s+'), '_');
                        }
                      }

                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => step2.Step2Documents(
                                initialCategoryId: initialCatId)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.items});
  final List<_QItem> items;

  @override
  Widget build(BuildContext context) {
    final cross = MediaQuery.of(context).size.width >= 720 ? 6 : 4;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: cross,
      childAspectRatio: cross >= 6 ? 1.0 : 0.78,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: items
          .map((e) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: e.onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withOpacity(0.12)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(e.icon, size: 28),
              const SizedBox(height: 8),
              Text(e.label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ))
          .toList(),
    );
  }
}

class _QItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QItem(this.icon, this.label, this.onTap);
}

class _LockedHint extends StatelessWidget {
  const _LockedHint({required this.locked, required this.onDocs});
  final int locked;
  final VoidCallback onDocs;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_rounded, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$locked category${locked == 1 ? '' : 'ies'} locked — upload required documents to unlock.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(onPressed: onDocs, child: const Text('Upload')),
        ],
      ),
    );
  }
}

class _Tips extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(Icons.info_outline_rounded, color: cs.onSurfaceVariant),
        title: const Text('Tip'),
        subtitle:
        const Text('Clear photos of original documents are reviewed faster.'),
      ),
    );
  }
}

class _NeedsMoreInfoCard extends StatelessWidget {
  const _NeedsMoreInfoCard({
    required this.items,
    required this.onFix,
  });

  // items: list of (categoryId, notes)
  final List<({String categoryId, String notes})> items;
  final void Function(String categoryId) onFix;

  String _pretty(String id) {
    final parts = id.split('_').map((p) {
      if (p.toLowerCase() == 'ac') return 'AC';
      return p.isEmpty ? p : (p[0].toUpperCase() + p.substring(1));
    }).toList();
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.rule_folder_rounded, color: cs.onSurface),
              const SizedBox(width: 8),
              Text('Action required',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            Text(
              'A reviewer requested more information for the categories below.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Column(
              children: items.take(6).map((it) {
                final label = _pretty(it.categoryId);
                final hasNotes = it.notes.trim().isNotEmpty;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outline.withOpacity(0.12)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Needs more info • $label',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            if (hasNotes) ...[
                              const SizedBox(height: 4),
                              Text(
                                it.notes,
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () => onFix(it.categoryId),
                        child: const Text('Fix now'),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            if (items.length > 6)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+${items.length - 6} more categories',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VerificationTimelineList extends StatelessWidget {
  const _VerificationTimelineList({required this.uid});
  final String uid;

  String _pretty(String id) {
    final parts = id.split('_').map((p) {
      if (p.toLowerCase() == 'ac') return 'AC';
      return p.isEmpty ? p : (p[0].toUpperCase() + p.substring(1));
    }).toList();
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('categoryEligibility')
        .orderBy('updatedAt', descending: true)
        .limit(10)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty)
          return const SizedBox.shrink();
        final rows = snap.data!.docs.map((d) {
          final m = d.data();
          final id = (m['categoryId'] ?? d.id).toString();
          final st = (m['status'] ?? 'submitted').toString();
          final note = (m['notes'] ?? '').toString();
          final ts = (m['updatedAt'] as Timestamp?)?.toDate();
          return (id: id, status: st, notes: note, time: ts);
        }).toList();

        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.timeline_rounded, color: cs.onSurface),
                  const SizedBox(width: 8),
                  Text('Verification timeline',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 8),
                Column(
                  children: rows.map((r) {
                    final color = switch (r.status) {
                      'approved' => Colors.green.shade700,
                      'verified' => Colors.green.shade700,
                      'needs_more_info' => Colors.orange.shade800,
                      'rejected' => Colors.red.shade700,
                      _ => cs.onSurfaceVariant,
                    };
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Icon(Icons.fiber_manual_record,
                                size: 12, color: color),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${_pretty(r.id)} • ${r.status.replaceAll('_', ' ')}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                if (r.notes.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Text(r.notes,
                                        style: TextStyle(
                                            color: cs.onSurfaceVariant)),
                                  ),
                                if (r.time != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Text(r.time!.toLocal().toString(),
                                        style: TextStyle(
                                            color: cs.onSurfaceVariant,
                                            fontSize: 12)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LiveToggleCard extends StatelessWidget {
  const _LiveToggleCard();

  @override
  Widget build(BuildContext context) {
    final userProv = context.watch<UserProvider>();
    final cs = Theme.of(context).colorScheme;
    final isLive = userProv.isLive;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isLive
                  ? Colors.green.withOpacity(0.14)
                  : cs.surfaceVariant.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isLive ? Icons.podcasts_rounded : Icons.podcasts_rounded,
              color: isLive ? Colors.green.shade800 : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLive ? 'You are live' : 'You are offline',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  isLive
                      ? 'You’ll appear in nearby searches and can receive urgent pings.'
                      : 'Go live to appear in nearby searches and get urgent task alerts.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: Icon(isLive
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_fill_rounded),
            label: Text(isLive ? 'Go offline' : 'Go live'),
            onPressed: () async {
              try {
                await context.read<UserProvider>().setLive(!isLive);
                // optional: small toast/snack
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            isLive ? 'You are now offline' : 'You are now live')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Failed: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

class _HelperTasksMapScreen extends StatelessWidget {
  const _HelperTasksMapScreen();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks near you')),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: MiniMapCard(mode: 'helper'), // re-use full size
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text('Tap a pin to open the task.',
                style: TextStyle(color: cs.onSurfaceVariant)),
          )
        ],
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>? ?? {};
        final isLive = (data['isLive'] == true);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // ONLY status text now (no greeting line here)
                Expanded(
                  child: Text(
                    isLive ? 'You are online' : 'You are offline',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isLive ? const Color(0xFF00A86B) : Colors.grey,
                    ),
                  ),
                ),
                SizedBox(
                  height: 36, // small pill
                  child: isLive
                      ? OutlinedButton.icon(
                    onPressed: () => _setLive(uid, false),
                    icon: const Icon(Icons.podcasts_outlined, size: 16),
                    label: const Text('Go offline'),
                  )
                      : ElevatedButton.icon(
                    onPressed: () => _setLive(uid, true),
                    icon: const Icon(Icons.podcasts_outlined, size: 16),
                    label: const Text('Go live'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _setLive(String uid, bool value) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'isLive': value,
      'liveUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

class _QAButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QAButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color:
            Theme.of(context).colorScheme.surfaceVariant.withOpacity(.25),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

