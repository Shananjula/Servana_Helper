// lib/screens/task_details_screen.dart
//
// Task details with helper-side "Suggest offer" flow.
// - Visible "Suggest offer" button ONLY when:
//     • User is in helper mode (via UserProvider)
//     • Task status == 'open'
//     • Current user is not the poster
// - Opens a bottom sheet prefilled with suggested amount + polite message
// - Writes offer to BOTH:
//     • top-level /offers
//     • legacy nested /tasks/{taskId}/offers/{offerId}
//   (keeps old triggers/notifications working)
// - Poster still sees a "Manage offers" entrypoint (route kept).
//
// Additive, null-safe, and schema-tolerant.

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:servana/screens/rating_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:servana/services/user_gate_service.dart';

// Shared UI
import 'package:servana/widgets/status_chip.dart';
import 'package:servana/widgets/amount_pill.dart';

// Role/provider
import 'package:servana/providers/user_provider.dart';

// Optional destinations
import 'package:servana/screens/manage_offers_screen.dart';

class TaskDetailsScreen extends StatefulWidget {
  const TaskDetailsScreen({super.key, required this.taskId});

  final String taskId;

  @override
  State<TaskDetailsScreen> createState() => _TaskDetailsScreenState();
}

class _TaskDetailsScreenState extends State<TaskDetailsScreen> {
  // --- Verification helpers ---
  String _canon(String s) {
    final rx = RegExp(r'[^a-z0-9]+');
    var x = s.toLowerCase().trim().replaceAll(rx, '-');
    x = x.replaceAll(RegExp(r'^-+|-+$'), '');
    return x;
  }

  Set<String> _taskCategoryIds(Map<String, dynamic> t) {
    final out = <String>{};

    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = t[k];
        if (v == null) continue;
        if (v is String && v.trim().isNotEmpty) return v;
        if (v is Map && v['id'] is String && (v['id'] as String).trim().isNotEmpty) return v['id'] as String;
        if (v is Map && v['slug'] is String && (v['slug'] as String).trim().isNotEmpty) return v['slug'] as String;
        if (v is Map && v['label'] is String && (v['label'] as String).trim().isNotEmpty) return v['label'] as String;
      }
      return null;
    }

    const singles = [
      'categoryId','mainCategoryId','primaryCategoryId',
      'category_id','main_category_id',
      'category','mainCategory','categorySlug',
    ];
    final s = pick(singles);
    if (s != null) out.add(_canon(s));

    const labels = ['mainCategoryLabel','categoryLabel','mainCategoryLabelOrId','category_name'];
    for (final k in labels) {
      final v = t[k];
      if (v is String && v.trim().isNotEmpty) out.add(_canon(v));
      if (v is Map && v['label'] is String) out.add(_canon(v['label'] as String));
    }

    const lists = ['categoryIds','categories','tagIds','mainTagIds'];
    for (final k in lists) {
      final v = t[k];
      if (v is List) {
        for (final e in v) {
          if (e == null) continue;
          if (e is String) out.add(_canon(e));
          if (e is Map) {
            if (e['id'] is String) out.add(_canon(e['id'] as String));
            if (e['slug'] is String) out.add(_canon(e['slug'] as String));
            if (e['label'] is String) out.add(_canon(e['label'] as String));
          }
        }
      }
    }
    return out;
  }

  void _showVerifyDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verification required'),
        content: const Text('You need to verify this category before sending an offer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // TODO: Navigate to your verification flow route if you have one:
              // Navigator.pushNamed(context, '/verification');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Open verification flow from here.')),
              );
            },
            child: const Text('Verify now'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Task details')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('tasks').doc(widget.taskId).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Task not found'));
          }
          final task = snap.data!.data() ?? const <String, dynamic>{};

          final posterId = (task['posterId'] as String?) ?? '';
          final status = (task['status'] as String?) ?? 'open';
          final isOpen = status.toLowerCase() == 'open';
          final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
          final amPoster = uid.isNotEmpty && uid == posterId;

          final userProv = context.read<UserProvider>();
          final canSuggest = userProv.isHelperMode && isOpen && !amPoster;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _Header(task: task),

                    const SizedBox(height: 12),
                    _MetaRow(task: task),

                    const SizedBox(height: 16),
                    _BudgetCard(task: task),

                    const SizedBox(height: 16),
                    _DescriptionCard(description: (task['description'] as String?) ?? ''),

                    if (task['location'] is GeoPoint || (task['address'] is String && task['address'].toString().isNotEmpty))
                      const SizedBox(height: 16),
                    if (task['location'] is GeoPoint || (task['address'] is String && task['address'].toString().isNotEmpty))
                      _LocationCard(task: task),

                    const SizedBox(height: 16),
                    _PosterRow(posterId: posterId, amPoster: amPoster),

                    if (amPoster) ...[
                      const SizedBox(height: 8),
                      _ManageOffersButton(taskId: widget.taskId, posterId: posterId),
                    ],
                  ],
                ),
              ),

              // Bottom action bar (only when helper, open, not poster)
              if (canSuggest)
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border: Border(top: BorderSide(color: cs.outline.withOpacity(0.12))),
                    ),
                    
child: Consumer<UserGateService>(
  builder: (context, gate, __) {
    final cats = _taskCategoryIds(task);
    final allowed = gate.allowedCategoryIds.map((e) => _canon(e.toString())).toSet();
    final verified = cats.any((c) => allowed.contains(c));

    return SizedBox(
      width: double.infinity,
      child: verified
          ? FilledButton.icon(
              onPressed: () => _openSuggestOfferSheet(context, task),
              icon: const Icon(Icons.handshake),
              label: const Text('Make an offer'),
            )
          : OutlinedButton.icon(
              onPressed: () => _showVerifyDialog(context),
              icon: const Icon(Icons.verified_user),
              label: const Text('Verify to offer'),
            ),
    );
  },
),

                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------
  // Suggest Offer Sheet
  // ------------------------------
  Future<void> _openSuggestOfferSheet(BuildContext context, Map<String, dynamic> task) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in first')));
      return;
    }

    // Heuristic suggestion based on task budget/category
    final num? one = task['finalAmount'] as num? ?? task['budget'] as num?;
    final num? minB = task['budgetMin'] as num?;
    final num? maxB = task['budgetMax'] as num?;
    final suggested = _suggestedAmount(one: one, minB: minB, maxB: maxB, category: (task['category'] as String?));

    final amountCtrl = TextEditingController(text: suggested?.round().toString() ?? '');
    final msgCtrl = TextEditingController(
      text:
      'Hi! I can help with "${(task['title'] as String? ?? 'your task')}". I\'m available soon and can complete it professionally. '
          '${suggested != null ? 'My offer is LKR ${_fmtInt(suggested.round())}.' : ''} Thanks!',
    );

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: _OfferComposer(
            amountCtrl: amountCtrl,
            msgCtrl: msgCtrl,
            onSubmit: () async {
              final raw = amountCtrl.text.trim().replaceAll(',', '');
              final amount = num.tryParse(raw);
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a valid amount')),
                );
                return;
              }
              await _submitOffer(context, task: task, amount: amount, message: msgCtrl.text.trim());
            },
          ),
        );
      },
    );

    amountCtrl.dispose();
    msgCtrl.dispose();
  }

  num? _suggestedAmount({num? one, num? minB, num? maxB, String? category}) {
    if (one != null && one > 0) return one;
    if (minB != null && maxB != null && minB > 0 && maxB > 0) {
      // Slightly competitive: 90% of midpoint
      final mid = (minB + maxB) / 2;
      return (mid * 0.9);
    }
    // Category bands (very light heuristic)
    switch ((category ?? '').toLowerCase()) {
      case 'cleaning':
        return 4000;
      case 'delivery':
        return 1500;
      case 'repairs':
        return 7000;
      case 'tutoring':
        return 2500;
      case 'design':
        return 8000;
      case 'writing':
        return 4500;
      default:
        return null;
    }
  }

  Future<void> _submitOffer(
      BuildContext context, {
        required Map<String, dynamic> task,
        required num amount,
        required String message,
      }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid!;
    if (uid == null) return;

    final taskId = widget.taskId;
    final posterId = (task['posterId'] as String?) ?? '';

    // Load helper info for denormalized display
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final u = userDoc.data() ?? const <String, dynamic>{};
    final helperName = (u['displayName'] as String?) ?? 'Helper';
    final helperAvatarUrl = (u['photoURL'] as String?) ?? (u['avatarUrl'] as String?);
    final helperPhone = (u['phoneNumber'] as String?) ?? (u['phone'] as String?);

    final taskTitle = (task['title'] as String?) ?? 'Task';

    try {
      // Prevent duplicate pending offer from same helper
      final existing = await FirebaseFirestore.instance
          .collection('offers')
          .where('taskId', isEqualTo: taskId)
          .where('helperId', isEqualTo: uid)
          .where('status', whereIn: ['pending', 'negotiating', 'accepted'])
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You already have an active offer on this task')),
        );
        return;
      }
    } catch (_) {
      // If compound query/whereIn not indexed, ignore duplicate check gracefully
    }

    // Create a unified offer payload
    final offerRef = FirebaseFirestore.instance.collection('offers').doc();
    final offerId = offerRef.id;
    final now = FieldValue.serverTimestamp();

    final offer = <String, dynamic>{
      'offerId': offerId,
      'taskId': taskId,
      'taskTitle': taskTitle,
      'posterId': posterId,
      'helperId': uid,
      'helperName': helperName,
      'helperAvatarUrl': helperAvatarUrl,
      'helperPhoneNumber': helperPhone,
      'amount': amount,
      'message': message,
      'status': 'pending',
      'createdAt': now,
      // optional denorm
      'category': task['category'],
      'city': task['city'],
    };

    // Write to top-level AND legacy nested subcollection
    await offerRef.set(offer);
    await FirebaseFirestore.instance
        .collection('tasks')
        .doc(taskId)
        .collection('offers')
        .doc(offerId)
        .set(offer);

    if (!mounted) return;
    Navigator.of(context).pop(); // close sheet
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Offer sent!')),
    );
  }

  // ------------------------------
  // Small helpers
  // ------------------------------
  String _fmtInt(num n) {
    final negative = n < 0;
    final abs = n.abs();
    final s = abs.toStringAsFixed(abs % 1 == 0 ? 0 : 2);
    final parts = s.split('.');
    String whole = parts[0];
    final frac = parts.length > 1 ? parts[1] : '';
    final reg = RegExp(r'\B(?=(\d{3})+(?!\d))');
    whole = whole.replaceAllMapped(reg, (m) => ',');
    final prefix = negative ? '−' : '';
    return frac.isEmpty ? '$prefix$whole' : '$prefix$whole.$frac';
  }
}

// -------------------------------------------------
// Sub-widgets (structure-first, schema tolerant)
// -------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.task});
  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final title = (task['title'] as String?)?.trim();
    final status = (task['status'] as String?) ?? 'open';

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.work_outline_rounded),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title?.isNotEmpty == true ? title! : 'Task',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, height: 1.15),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              StatusChip(status),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.task});
  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final category = (task['category'] as String?)?.trim();
    final type = (task['type'] as String?)?.trim(); // 'online' | 'physical'
    final createdAt = task['createdAt'];

    String? timeAgo;
    if (createdAt is Timestamp) {
      final dt = createdAt.toDate();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) {
        timeAgo = 'just now';
      } else if (diff.inMinutes < 60) {
        timeAgo = '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        timeAgo = '${diff.inHours}h ago';
      } else if (diff.inDays < 7) {
        timeAgo = '${diff.inDays}d ago';
      } else {
        timeAgo = '${(diff.inDays / 7).floor()}w ago';
      }
    }

    Chip _chip(IconData icon, String text) {
      return Chip(
        label: Text(text),
        avatar: Icon(icon, size: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: cs.outline.withOpacity(0.25)),
        ),
        backgroundColor: cs.surfaceVariant.withOpacity(0.35),
        labelStyle: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (category != null && category.isNotEmpty) _chip(Icons.category_rounded, category),
        if (type != null && type.isNotEmpty)
          _chip(type == 'online' ? Icons.public_rounded : Icons.place_rounded,
              type[0].toUpperCase() + type.substring(1)),
        if (timeAgo != null) _chip(Icons.access_time_rounded, timeAgo),
      ],
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.task});
  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final num? finalAmount = task['finalAmount'] as num?;
    final num? budget = task['budget'] as num?;
    final num? minB = task['budgetMin'] as num?;
    final num? maxB = task['budgetMax'] as num?;

    String? text;
    num? amount;

    if (finalAmount != null) {
      amount = finalAmount;
    } else if (budget != null) {
      amount = budget;
    } else if (minB != null && maxB != null) {
      text = 'LKR ${_fmt(minB)}–${_fmt(maxB)}';
    } else if (minB != null) {
      text = 'From LKR ${_fmt(minB)}';
    } else if (maxB != null) {
      text = 'Up to LKR ${_fmt(maxB)}';
    } else {
      text = '—';
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.12)),
      ),
      child: ListTile(
        leading: const Icon(Icons.payments_rounded),
        title: const Text('Budget'),
        subtitle: const Text('Requested amount or range'),
        trailing: AmountPill(amount: amount, text: text),
      ),
    );
  }

  String _fmt(num n) {
    final s = n.toStringAsFixed(n % 1 == 0 ? 0 : 2);
    final parts = s.split('.');
    String whole = parts[0];
    final reg = RegExp(r'\B(?=(\d{3})+(?!\d))');
    whole = whole.replaceAllMapped(reg, (m) => ',');
    final frac = parts.length > 1 ? parts[1] : '';
    return frac.isEmpty ? whole : '$whole.$frac';
  }
}

class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({required this.description});
  final String description;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline.withOpacity(0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Description',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              description.isNotEmpty ? description : 'No description provided.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.task});
  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gp = task['location'] as GeoPoint?;
    final addr = (task['address'] as String?) ?? '';

    final subtitle = addr.isNotEmpty
        ? addr
        : (gp != null ? 'Lat ${gp.latitude.toStringAsFixed(4)}, Lng ${gp.longitude.toStringAsFixed(4)}' : '—');

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline.withOpacity(0.12)),
      ),
      child: ListTile(
        leading: const Icon(Icons.place_rounded),
        title: const Text('Location'),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _PosterRow extends StatelessWidget {
  const _PosterRow({required this.posterId, required this.amPoster});
  final String posterId;
  final bool amPoster;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline.withOpacity(0.12)),
      ),
      child: ListTile(
        leading: const Icon(Icons.person_rounded),
        title: Text(amPoster ? 'You posted this task' : 'Task by'),
        subtitle: amPoster
            ? const Text('Manage your offers and updates')
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').doc(posterId).snapshots(),
          builder: (context, snap) {
            final name = (snap.data?.data()?['displayName'] as String?) ?? 'Poster';
            return Text(name);
          },
        ),
      ),
    );
  }
}

class _ManageOffersButton extends StatelessWidget {
  const _ManageOffersButton({required this.taskId, required this.posterId});
  final String taskId;
  final String posterId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ManageOffersScreen(taskId: taskId, posterId: posterId)),
          );
        },
        icon: const Icon(Icons.local_offer_outlined),
        label: const Text('Manage offers'),
      ),
    );
  }
}

class _OfferComposer extends StatelessWidget {
  const _OfferComposer({
    required this.amountCtrl,
    required this.msgCtrl,
    required this.onSubmit,
  });

  final TextEditingController amountCtrl;
  final TextEditingController msgCtrl;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Suggest your offer',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextField(
            controller: amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount (LKR)',
              hintText: 'e.g., 5000',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: msgCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Message to poster',
              hintText: 'Introduce yourself briefly and mention availability.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSubmit,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send offer'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your offer will be visible to the poster. You can edit or withdraw it later if needed.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}


// ------------------------------
// Timeline (events)
// ------------------------------
class _TimelineSection extends StatelessWidget {
  const _TimelineSection({required this.task});
  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context) {
    final List<dynamic> tl = (task['timeline'] is List) ? List<dynamic>.from(task['timeline']) : const <dynamic>[];
    if (tl.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.timeline_outlined),
          title: const Text('Timeline'),
          subtitle: const Text('No events yet.'),
        ),
      );
    }
    IconData _iconFor(String type) {
      switch (type) {
        case 'start_key_issued': return Icons.qr_code_2_outlined;
        case 'started': return Icons.play_arrow_rounded;
        case 'completed_confirmed': return Icons.check_circle_outline;
        case 'cancel_requested': return Icons.report_gmailerrorred_outlined;
        default: return Icons.bolt_outlined;
      }
    }
    String _labelFor(String type) {
      switch (type) {
        case 'start_key_issued': return 'Start code issued';
        case 'started': return 'Work started';
        case 'completed_confirmed': return 'Completion confirmed';
        case 'cancel_requested': return 'Cancellation requested';
        default: return type.replaceAll('_', ' ');
      }
    }
    String _fmt(dynamic ts) {
      try {
        if (ts is Timestamp) return ts.toDate().toLocal().toString();
        if (ts is DateTime) return ts.toLocal().toString();
      } catch (_) {}
      return '';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [Icon(Icons.timeline_outlined), SizedBox(width: 8), Text('Timeline', style: TextStyle(fontWeight: FontWeight.w700))]),
            const SizedBox(height: 8),
            for (final e in tl)
              Builder(builder: (_) {
                final m = (e is Map) ? Map<String, dynamic>.from(e) : const <String, dynamic>{};
                final type = (m['type'] ?? '').toString();
                final at = m['at'];
                return ListTile(
                  dense: true,
                  leading: Icon(_iconFor(type)),
                  title: Text(_labelFor(type)),
                  subtitle: Text(_fmt(at)),
                );
              }),
          ],
        ),
      ),
    );
  }
}

// ------------------------------
// Rate CTA
// ------------------------------
class _RateCtaSection extends StatelessWidget {
  const _RateCtaSection({required this.taskId, required this.task});
  final String taskId;
  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final posterId = (task['posterId'] ?? '').toString();
    final helperId = (task['helperId'] ?? '').toString();
    final status = (task['status'] ?? '').toString();
    if (status != 'completed') return const SizedBox.shrink();
    final reviewedByPoster = task['reviewedByPoster'] == true;
    final reviewedByHelper = task['reviewedByHelper'] == true;

    final isPoster = uid.isNotEmpty && uid == posterId;
    final isHelper = uid.isNotEmpty && uid == helperId;

    if (isPoster && helperId.isNotEmpty && !reviewedByPoster) {
      return FilledButton.icon(
        icon: const Icon(Icons.rate_review_outlined),
        label: const Text('Rate helper'),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => RatingScreen(
              revieweeId: helperId,
              revieweeRole: 'helper',
              taskId: taskId,
            ),
          ));
        },
      );
    } else if (isHelper && posterId.isNotEmpty && !reviewedByHelper) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.rate_review_outlined),
        label: const Text('Rate poster'),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => RatingScreen(
              revieweeId: posterId,
              revieweeRole: 'poster',
              taskId: taskId,
            ),
          ));
        },
      );
    }
    return const SizedBox.shrink();
  }
}
