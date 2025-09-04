// lib/screens/task_details_screen.dart
//
// Task Details (Helper app, Phase 1)
// ----------------------------------
// • Streams the task by id
// • Uses EligibilityService to gate "Make offer" by verified category
// • If locked: shows an unlock banner → deep-links to Step 2 (documents)
// • Schema tolerant: categoryId|category, price|budget, etc.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:servana/widgets/status_chip.dart';
import 'package:servana/screens/step_2_documents.dart' as step2;
import 'package:servana/services/eligibility_service.dart' as elig;

class TaskDetailsScreen extends StatelessWidget {
  const TaskDetailsScreen({super.key, required this.taskId});
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('tasks').doc(taskId);
    return Scaffold(
      appBar: AppBar(title: const Text('Task details')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (!snap.data!.exists) return const Center(child: Text('Task not found'));

          final t = snap.data!.data() ?? {};
          final title = (t['title'] ?? 'Task').toString();
          final status = (t['status'] ?? t['state'] ?? 'open').toString();
          final description = (t['description'] ?? '').toString();
          final address = (t['address'] ?? t['locationText'] ?? '').toString();
          final city = (t['city'] ?? '').toString();

          // Category: prefer categoryId; else normalize "category" label
          final rawCat = (t['categoryId'] ?? t['category'] ?? '-').toString();
          final categoryId = (t['categoryId'] != null)
              ? rawCat
              : elig.normalizeCategoryId(rawCat);
          final categoryLabel = (t['category'] ?? rawCat).toString();

          final price = _bestBudgetText(t);
          final createdAt = _toDate(t['createdAt']);
          final scheduledAt = _toDate(t['scheduledAt']);

          return FutureBuilder<elig.CategoryEligibility>(
            future: elig.EligibilityService().checkHelperEligibility(categoryId),
            builder: (context, eligSnap) {
              final elig.CategoryEligibility eligibility = eligSnap.data ??
                  const elig.CategoryEligibility(
                    categoryId: '',
                    isRegistered: false,
                    status: 'not_started',
                    isAllowed: false,
                  );

              final verifiedForCategory = eligibility.canMakeOffer;
              final categoryDisplay = (categoryLabel.isEmpty ? categoryId : categoryLabel);

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusChip(status),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Meta chips
                  Wrap(
                    spacing: 8,
                    runSpacing: -6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      verifiedForCategory
                          ? _VerifiedChip('Verified • $categoryDisplay')
                          : _ChipText(categoryDisplay),
                      if (city.isNotEmpty) _ChipText(city),
                      if (address.isNotEmpty) _ChipText(address),
                      if (price != null) _ChipText(price),
                      if (createdAt != null) _ChipText('Posted ${_timeAgo(createdAt)}'),
                      if (scheduledAt != null) _ChipText('Scheduled ${scheduledAt.toLocal()}'),
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Unlock banner when not eligible
                  if (!verifiedForCategory)
                    _UnlockBanner(
                      categoryId: categoryId,
                      status: eligibility.status,
                      notes: eligibility.notes,
                    ),

                  // Description
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Description',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(description),
                  ],

                  // --- Offer Section ---
                  _buildOfferSection(
                    context: context,
                    taskId: taskId,
                    taskData: t,
                    eligibility: eligibility,
                    taskStatus: status,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildOfferSection({
    required BuildContext context,
    required String taskId,
    required Map<String, dynamic> taskData,
    required elig.CategoryEligibility eligibility,
    required String taskStatus,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _OfferActions(
        enabled: false,
        taskId: taskId,
        task: taskData,
      );
    }

    // This widget shows the user's existing offer card (View/Edit/Withdraw)
    final myOfferSection = _MyOfferSection(taskId: taskId, helperId: uid);

    // This widget decides whether to show the "Make Offer" button
    final offerComposer =
    (eligibility.canMakeOffer && _isOfferableStatus(taskStatus))
        ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('offers')
          .where('taskId', isEqualTo: taskId)
          .where('helperId', isEqualTo: uid)
          .limit(1)
          .snapshots(),
      builder: (context, top) {
        final topHasActive = () {
          if (!top.hasData || top.data!.docs.isEmpty) return false;
          final m = top.data!.docs.first.data();
          return _isActiveOfferStatus((m['status'] ?? 'pending').toString());
        }();

        if (topHasActive) {
          return Text('You’ve already sent an offer for this task.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
        }

        // Fallback to subcollection under the task
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('tasks')
              .doc(taskId)
              .collection('offers')
              .where('helperId', isEqualTo: uid)
              .limit(1)
              .snapshots(),
          builder: (context, sub) {
            final subHasActive = () {
              if (!sub.hasData || sub.data!.docs.isEmpty) return false;
              final m = sub.data!.docs.first.data();
              return _isActiveOfferStatus((m['status'] ?? 'pending').toString());
            }();

            if (subHasActive) {
              return Text('You’ve already sent an offer for this task.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
            }

            // No active offer → show "Make offer"
            return _OfferActions(
              enabled: true,
              taskId: taskId,
              task: taskData,
            );
          },
        );
      },
    )
        : _OfferActions(
      enabled: false,
      taskId: taskId,
      task: taskData,
    );

    return Column(
      children: [
        const SizedBox(height: 12),
        myOfferSection,
        const SizedBox(height: 16),
        offerComposer,
      ],
    );
  }

  bool _isOfferableStatus(String s) {
    final t = s.toLowerCase();
    return t == 'open' || t == 'listed' || t == 'negotiating' || t == 'negotiation';
  }
}

// ---------- UI bits ----------

class _ChipText extends StatelessWidget {
  const _ChipText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text, overflow: TextOverflow.ellipsis),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _UnlockBanner extends StatelessWidget {
  const _UnlockBanner({required this.categoryId, required this.status, this.notes});
  final String categoryId;
  final String status;
  final String? notes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String title;
    String subtitle;
    IconData icon;
    Color bg;
    Color fg;

    switch (status) {
      case 'pending':
        title = 'Verification pending';
        subtitle = 'Your documents for this category are under review.';
        icon = Icons.hourglass_top_rounded;
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        break;
      case 'rejected':
        title = 'Verification rejected';
        subtitle = 'Please review the notes and resubmit documents.';
        icon = Icons.error_outline_rounded;
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        break;
      case 'needs_more_info':
        title = 'More information required';
        subtitle = 'Please add the requested documents and resubmit.';
        icon = Icons.rule_folder_outlined;
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        break;
      case 'not_started':
      default:
        title = 'Unlock this category';
        subtitle = 'Upload required documents to get verified and make offers.';
        icon = Icons.verified_user_outlined;
        bg = cs.surfaceVariant;
        fg = cs.onSurface;
        break;
    }

    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: fg, fontWeight: FontWeight.w800),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(subtitle, style: TextStyle(color: fg)),
            if (notes != null && notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: fg.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Reviewer notes: $notes', style: TextStyle(color: fg)),
              ),

          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => step2.Step2Documents(initialCategoryId: categoryId)));
              },
              icon: const Icon(Icons.verified_user_rounded),
              label: Text('Verify for ' + (categoryId.isEmpty ? 'category' : categoryId.replaceAll('_',' '))),
            ),
          ),
],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => step2.Step2Documents(initialCategoryId: categoryId),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open documents'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferActions extends StatelessWidget {
  const _OfferActions({required this.enabled, required this.taskId, required this.task});
  final bool enabled;
  final String taskId;
  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: (!enabled || uid == null) ? null : () => _openOfferSheet(context, uid),
            icon: const Icon(Icons.local_offer_outlined),
            label: const Text('Make offer'),
          ),
        ),
      ],
    );
  }

  Future<void> _openOfferSheet(BuildContext context, String uid) async {
    final priceCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Make an offer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              FutureBuilder<List<int>>(
                future: _suggestOfferAmounts(task),
                builder: (context, snap) {
                  final sugg = snap.data ?? const <int>[];
                  if (sugg.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: -6,
                      children: sugg.map((v) => ChoiceChip(
                        label: Text('LKR ${_fmtLkr(v)}'),
                        selected: false,
                        onSelected: (_) => priceCtrl.text = v.toString(),
                      )).toList(),
                    ),
                  );
                },
              ),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount (LKR)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Note to poster (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Send offer'),
                      onPressed: () => Navigator.pop(context, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return;

    final price = num.tryParse(priceCtrl.text.trim());
    if (price == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
      }
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('offers').add({
        'taskId': taskId,
        'posterId': task['posterId'] ?? '',
        'helperId': uid,
        'price': price,
        'message': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Offer sent')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// Finds and shows the helper's own offer for this task from either:
//   /offers (top-level)  OR  /tasks/{taskId}/offers
class _MyOfferSection extends StatelessWidget {
  const _MyOfferSection({required this.taskId, required this.helperId});

  final String taskId;
  final String helperId;

  @override
  Widget build(BuildContext context) {
    final topLevel = FirebaseFirestore.instance
        .collection('offers')
        .where('taskId', isEqualTo: taskId)
        .where('helperId', isEqualTo: helperId)
        .limit(1)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: topLevel,
      builder: (context, top) {
        if (top.hasData && top.data!.docs.isNotEmpty) {
          final d = top.data!.docs.first;
          return _MyOfferTile(ref: d.reference, data: d.data());
        }

        // Fallback: subcollection
        final sub = FirebaseFirestore.instance
            .collection('tasks')
            .doc(taskId)
            .collection('offers')
            .where('helperId', isEqualTo: helperId)
            .limit(1)
            .snapshots();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: sub,
          builder: (context, subSnap) {
            if (!subSnap.hasData || subSnap.data!.docs.isEmpty) {
              // No offer – render nothing
              return const SizedBox.shrink();
            }
            final d = subSnap.data!.docs.first;
            return _MyOfferTile(ref: d.reference, data: d.data());
          },
        );
      },
    );
  }
}

class _MyOfferTile extends StatelessWidget {
  const _MyOfferTile({required this.ref, required this.data});
  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> data;

  String _statusLabel(String s) {
    switch (s.toLowerCase()) {
      case 'pending': return 'Pending';
      case 'accepted': return 'Accepted';
      case 'declined': return 'Declined';
      case 'withdrawn': return 'Withdrawn';
      case 'counter': return 'Counter';
      default: return s;
    }
  }

  bool get _canEdit {
    final s = (data['status'] ?? 'pending').toString().toLowerCase();
    return s == 'pending' || s == 'counter';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final price = data['price'] ?? data['amount'];
    final status = (data['status'] ?? 'pending').toString();
    final note = (data['message'] ?? data['note'] ?? '').toString();
    final counter = data['counterPrice'];
    final isCounter = status.toLowerCase() == 'counter';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: amount + status
            Row(
              children: [
                Text(
                  price == null ? 'Your offer' : 'Your offer: LKR ${_fmt(num.tryParse(price.toString()) ?? 0)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(_statusLabel(status)),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: cs.outline.withOpacity(0.25)),
                  backgroundColor: cs.surfaceVariant,
                ),
              ],
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(note, style: TextStyle(color: cs.onSurfaceVariant)),
            ],
            if (isCounter && counter != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withOpacity(0.35)),
                ),
                child: Text(
                  'Poster countered: LKR ${_fmt(num.tryParse(counter.toString()) ?? 0)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
            const SizedBox(height: 8),

            // Actions
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_rounded),
                  label: const Text('View'),
                  onPressed: () => _preview(context),
                ),
                const SizedBox(width: 8),

                if (isCounter && counter != null) ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Accept counter'),
                    onPressed: () => _acceptCounter(context, counter),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('Decline counter'),
                    onPressed: () => _declineCounter(context),
                  ),
                  const SizedBox(width: 8),
                  // Still allow edit to propose a different value
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                    onPressed: () => _edit(context),
                  ),
                ] else ...[
                  if (_canEdit)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                      onPressed: () => _edit(context),
                    ),
                  const SizedBox(width: 8),
                  if (_canEdit)
                    TextButton.icon(
                      icon: const Icon(Icons.undo),
                      label: const Text('Withdraw'),
                      onPressed: () => _withdraw(context),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _preview(BuildContext context) {
    final price = data['price'] ?? data['amount'];
    final note = (data['message'] ?? data['note'] ?? '').toString();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Your offer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (price != null) Text('Amount: LKR ${price.toString()}'),
            const SizedBox(height: 6),
            Text('Status: ${(data['status'] ?? 'pending').toString()}'),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Note: $note'),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final priceCtrl = TextEditingController(text: (data['price'] ?? data['amount'] ?? '').toString());
    final noteCtrl  = TextEditingController(text: (data['message'] ?? data['note'] ?? '').toString());

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Edit your offer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount (LKR)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Note to poster (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Save changes'),
                      onPressed: () => Navigator.pop(context, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return;

    final newPrice = num.tryParse(priceCtrl.text.trim());
    if (newPrice == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
      }
      return;
    }

    try {
      await ref.set({
        'price': newPrice,
        'message': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        'status': 'pending',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer updated')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _withdraw(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Withdraw offer?'),
        content: const Text('You can send a new offer later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.set({
        'status': 'withdrawn',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer withdrawn')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _acceptCounter(BuildContext context, dynamic counterPrice) async {
    try {
      final acceptedPrice = num.tryParse(counterPrice.toString());
      await ref.set({
        'price': acceptedPrice,
        'status': 'pending',                    // back to pending for poster to accept
        'counterAcceptedByHelper': true,
        'counterPrice': null,                   // clear counter field
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Counter accepted — waiting for poster')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _declineCounter(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Decline counter?'),
        content: const Text('You can edit your offer or withdraw instead.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Decline')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.set({
        'status': 'withdrawn',                  // end the counter thread
        'counterAcceptedByHelper': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Counter declined')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// ---------- helpers ----------

Future<List<int>> _suggestOfferAmounts(Map<String, dynamic> task) async {
  // Heuristic: use task budget if present, else derive from category
  final cat = (task['categoryId'] ?? task['category'] ?? '').toString().toLowerCase();
  final baseBudget = (() {
    final n = task['budget'] ?? task['price'] ?? task['finalAmount'];
    if (n is num) return n.toDouble();
    final s = (n ?? '').toString().replaceAll(',', '');
    return double.tryParse(s) ?? 0.0;
  })();

  double anchor;
  if (baseBudget > 0) {
    anchor = baseBudget;
  } else {
    // very light category anchors (tweak as you like)
    if (cat.contains('plumb')) anchor = 6000;
    else if (cat.contains('elect')) anchor = 7000;
    else if (cat.contains('clean')) anchor = 4500;
    else if (cat.contains('deliver')) anchor = 3000;
    else if (cat.contains('repair')) anchor = 6500;
    else if (cat.contains('tutor')) anchor = 2500;
    else anchor = 5000;
  }

  // Build a small band around the anchor
  final s = <int>{
    (anchor * 0.9).round(),
    (anchor * 1.0).round(),
    (anchor * 1.1).round(),
    if (anchor >= 4000) (anchor * 1.25).round(),
  }.where((v) => v > 0).toList()
    ..sort();

  return s.take(4).toList();
}

String _fmtLkr(num n) {
  final s = n.abs().toStringAsFixed(n % 1 == 0 ? 0 : 2);
  final parts = s.split('.');
  final reg = RegExp(r'\B(?=(\d{3})+(?!\d))');
  final whole = parts[0].replaceAllMapped(reg, (m) => ',');
  return parts.length == 1 ? '$whole' : '$whole.${parts[1]}';
}

String? _bestBudgetText(Map<String, dynamic> t) {
  final num? finalAmount = t['finalAmount'] as num?;
  final num? price = t['price'] as num?;
  final num? minB = t['budgetMin'] as num?;
  final num? maxB = t['budgetMax'] as num?;
  if (finalAmount != null) return _fmt(finalAmount);
  if (price != null) return _fmt(price);
  if (minB != null && maxB != null) return '${_fmt(minB)}–${_fmt(maxB)}';
  if (minB != null) return 'From ${_fmt(minB)}';
  if (maxB != null) return 'Up to ${_fmt(maxB)}';
  return null;
}

String _fmt(num n) {
  final negative = n < 0;
  final abs = n.abs();
  final isWhole = abs % 1 == 0;
  final raw = isWhole ? abs.toStringAsFixed(0) : abs.toStringAsFixed(2);
  final parts = raw.split('.');
  String whole = parts[0];
  final frac = parts.length > 1 ? parts[1] : '';
  final reg = RegExp(r'\B(?=(\d{3})+(?!\d))');
  whole = whole.replaceAllMapped(reg, (m) => ',');
  final sign = negative ? '−' : '';
  return frac.isEmpty ? 'LKR $sign$whole' : 'LKR $sign$whole.$frac';
}

DateTime? _toDate(dynamic ts) {
  if (ts is Timestamp) return ts.toDate();
  if (ts is DateTime) return ts;
  try {
    final i = int.parse(ts.toString());
    return DateTime.fromMillisecondsSinceEpoch(i);
  } catch (_) {}
  return null;
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final weeks = (diff.inDays / 7).floor();
  return '${weeks}w ago';
}

bool _isActiveOfferStatus(String s) {
  final t = s.toLowerCase();
  return t == 'pending' || t == 'counter';
}

class _VerifiedChip extends StatelessWidget {
  const _VerifiedChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.verified_rounded, size: 18, color: Colors.green),
      label: Text(text, overflow: TextOverflow.ellipsis),
      visualDensity: VisualDensity.compact,
      backgroundColor: Colors.green.withOpacity(0.12),
      side: BorderSide(color: Colors.green.withOpacity(0.25)),
      labelStyle: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w800),
    );
  }
}
