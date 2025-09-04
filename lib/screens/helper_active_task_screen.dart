// lib/screens/helper_active_task_screen.dart
//
// My Jobs (Helper app, Phase 0)
// -----------------------------
// • Tabs: Assigned • Ongoing • Completed
// • Shows helper's tasks with quick actions
// • Start / Finish via shared PIN sheet (widgets/pin_sheet.dart)
// • Defensive Firestore queries (order by updatedAt -> fallback createdAt)

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:servana/utils/log_service.dart';
import 'package:servana/utils/safe_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

// ✅ use the pin sheet via an alias to avoid future name collisions
import 'package:servana/widgets/pin_sheet.dart' as pin;
import 'package:servana/widgets/status_chip.dart';
import 'package:servana/screens/task_details_screen.dart';

class HelperActiveTaskScreen extends StatefulWidget {
  const HelperActiveTaskScreen({super.key});

  @override
  State<HelperActiveTaskScreen> createState() => _HelperActiveTaskScreenState();
}

class _HelperActiveTaskScreenState extends State<HelperActiveTaskScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My jobs'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Assigned'),
            Tab(text: 'Ongoing'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _TaskList(statuses: ['assigned', 'booked', 'scheduled']),
          _TaskList(
              statuses: ['en_route', 'arrived', 'in_progress', 'started', 'ongoing']),
          _TaskList(statuses: ['completed', 'finished', 'rated', 'closed']),
        ],
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.statuses});
  final List<String> statuses;

  // ---------- Navigation Helper ----------

  Future<void> _navigateToTask(BuildContext context, Map<String, dynamic> data) async {
    // Try to extract lat/lng from common shapes
    double? lat, lng;

    // cases: top-level lat/lng
    if (data['lat'] is num && data['lng'] is num) {
      lat = (data['lat'] as num).toDouble();
      lng = (data['lng'] as num).toDouble();
    }

    // case: location as GeoPoint
    if ((lat == null || lng == null) && data['location'] != null) {
      final loc = data['location'];
      try {
        // GeoPoint from cloud_firestore
        lat ??= (loc.latitude as num?)?.toDouble();
        lng ??= (loc.longitude as num?)?.toDouble();
      } catch (_) {
        // map lat/lng
        if (loc is Map) {
          if (loc['lat'] is num && loc['lng'] is num) {
            lat = (loc['lat'] as num).toDouble();
            lng = (loc['lng'] as num).toDouble();
          }
        }
      }
    }

    // alternative nest: geo:{lat,lng}
    if ((lat == null || lng == null) && data['geo'] is Map) {
      final g = data['geo'] as Map;
      if (g['lat'] is num && g['lng'] is num) {
        lat = (g['lat'] as num).toDouble();
        lng = (g['lng'] as num).toDouble();
      }
    }

    // human-readable address (fallback)
    String? address = (data['address'] ?? data['locationText'] ?? data['mapAddress'])?.toString();
    address = (address != null && address.trim().isNotEmpty) ? address.trim() : null;

    Uri? uri;
    if (lat != null && lng != null) {
      // Universal Google Maps URL works on iOS & Android
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    } else if (address != null) {
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
    }

    if (uri == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No location found for this task.')),
        );
      }
      return;
    }

    try {
      final ok = await canLaunchUrl(uri);
      if (!ok) throw 'Cannot launch';
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open maps: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ---------- Proof Management Helpers ----------

  Future<List<String>> _readProofs(String taskId) async {
    final snap =
    await FirebaseFirestore.instance.collection('tasks').doc(taskId).get();
    final m = snap.data() ?? {};
    final list = (m['proofUrls'] is List)
        ? List<String>.from(m['proofUrls'])
        : const <String>[];
    return list;
  }

  Future<void> _addProofPhotos(BuildContext context, String taskId) async {
    try {
      // Current count (cap at 3 total)
      final existing = await _readProofs(taskId);
      if (existing.length >= 3) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('You can upload up to 3 proof photos.')));
        }
        return;
      }

      final picker = ImagePicker();
      final picked = await picker.pickMultiImage(imageQuality: 85);
      if (picked.isEmpty) return;

      final room = 3 - existing.length;
      final take = picked.take(room);

      final urls = <String>[];
      for (final x in take) {
        // quick size guard (≤ 5MB)
        final f = File(x.path);
        final sizeMB = (await f.length()) / (1024 * 1024);
        if (sizeMB > 5) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Skipped large image (>5MB): ${x.name}')),
            );
          }
          continue;
        }

        final ref = FirebaseStorage.instance.ref(
            'task_proofs/$taskId/${DateTime.now().millisecondsSinceEpoch}_${x.name}');
        await ref.putFile(f);
        final url = await ref.getDownloadURL();
        urls.add(url);
      }

      if (urls.isNotEmpty) {
        await SafeFirestore.arrayUnion('tasks', taskId, 'proofUrls', urls);

        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Proof photos added.')));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Upload failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _removeProof(
      BuildContext context, String taskId, String url) async {
    try {
      // Best-effort: remove blob (if accessible by URL)
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}

      await SafeFirestore.arrayRemove('tasks', taskId, 'proofUrls', [url]);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not remove: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _previewImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
      ),
    );
  }

  // ---------- Status Update Helpers ----------

  Future<void> _setStatus(BuildContext context, String taskId, String status, {Map<String, dynamic>? extra}) async {
    try {
      await SafeFirestore.setMerge('tasks', taskId, {
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        ...?extra,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status updated: $status')));
      }
    } catch (e, st) {
      LogService.logError('status_update_failed', where: 'helper_active_task_screen::_setStatus', error: e, stack: st, extra: {'taskId': taskId, 'status': status});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // Sugar helpers for clean transitions
  Future<void> _markEnRoute(BuildContext c, String taskId) =>
      _setStatus(c, taskId, 'en_route');
  Future<void> _markArrived(BuildContext c, String taskId) =>
      _setStatus(c, taskId, 'arrived');

  Future<void> _startWithPin(BuildContext c, String taskId) async {
    final ok = await pin.showPinSheet(c, mode: pin.PinMode.start, taskId: taskId);
    if (ok == true) {
      await _setStatus(c, taskId, 'in_progress',
          extra: {'startedAt': FieldValue.serverTimestamp()});
    }
  }

  Future<void> _finishWithPin(BuildContext c, String taskId) async {
    // Nudge if no proofs yet
    final proofs = await _readProofs(taskId);
    if (proofs.isEmpty) {
      final proceed = await showDialog<bool>(
        context: c,
        builder: (_) => AlertDialog(
          title: const Text('No proof photos'),
          content: const Text('Do you want to finish without uploading proof photos?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Add photos')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Finish anyway')),
          ],
        ),
      );
      if (proceed != true) {
        // Open add flow
        await _addProofPhotos(c, taskId);
        return;
      }
    }

    final ok =
    await pin.showPinSheet(c, mode: pin.PinMode.finish, taskId: taskId);
    if (ok == true) {
      await _setStatus(c, taskId, 'completed',
          extra: {'finishedAt': FieldValue.serverTimestamp()});
    }
  }

  // ---------- Action Button Builder ----------

  Widget _actionsFor(
      BuildContext ctx, String taskId, String status, bool isMine, Map<String, dynamic> data) {
    final s = status.toLowerCase();

    // View button is always available
    final viewButton = OutlinedButton.icon(
      icon: const Icon(Icons.remove_red_eye_outlined, size: 18),
      label: const Text('View'),
      onPressed: () => Navigator.push(
        ctx,
        MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: taskId)),
      ),
    );

    List<Widget> actionButtons = [];

    if (s == 'assigned' || s == 'scheduled' || s == 'booked') {
      actionButtons = [
        OutlinedButton.icon(
          icon: const Icon(Icons.navigation_rounded),
          label: const Text('Navigate'),
          onPressed: () => _navigateToTask(ctx, data),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.route_rounded),
          label: const Text('En route'),
          onPressed: isMine ? () => _markEnRoute(ctx, taskId) : null,
        ),
        FilledButton.icon(
          icon: const Icon(Icons.play_circle_fill_rounded),
          label: const Text('Start (PIN)'),
          onPressed: isMine ? () => _startWithPin(ctx, taskId) : null,
        ),
      ];
    } else if (s == 'en_route') {
      actionButtons = [
        OutlinedButton.icon(
          icon: const Icon(Icons.navigation_rounded),
          label: const Text('Navigate'),
          onPressed: () => _navigateToTask(ctx, data),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.pin_drop_rounded),
          label: const Text('Arrived'),
          onPressed: isMine ? () => _markArrived(ctx, taskId) : null,
        ),
        FilledButton.icon(
          icon: const Icon(Icons.play_circle_fill_rounded),
          label: const Text('Start (PIN)'),
          onPressed: isMine ? () => _startWithPin(ctx, taskId) : null,
        ),
      ];
    } else if (s == 'arrived') {
      actionButtons = [
        OutlinedButton.icon(
          icon: const Icon(Icons.navigation_rounded),
          label: const Text('Navigate'),
          onPressed: () => _navigateToTask(ctx, data),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.play_circle_fill_rounded),
          label: const Text('Start (PIN)'),
          onPressed: isMine ? () => _startWithPin(ctx, taskId) : null,
        ),
      ];
    } else if (s == 'in_progress' || s == 'ongoing' || s.contains('progress')) {
      actionButtons = [
        OutlinedButton.icon(
          icon: const Icon(Icons.navigation_rounded),
          label: const Text('Navigate'),
          onPressed: () => _navigateToTask(ctx, data),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check_circle_rounded),
          label: const Text('Finish (PIN)'),
          onPressed: isMine ? () => _finishWithPin(ctx, taskId) : null,
        ),
      ];
    }

    // Combine view button with dynamic actions
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        viewButton,
        if (actionButtons.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: actionButtons),
        ]
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('Please sign in to view your jobs.'));
    }

    Query<Map<String, dynamic>> base = FirebaseFirestore.instance
        .collection('tasks')
        .where('helperId', isEqualTo: uid)
        .where('status', whereIn: statuses);

    Query<Map<String, dynamic>> q;
    try {
      q = base.orderBy('updatedAt', descending: true).limit(120);
    } catch (_) {
      q = base.orderBy('createdAt', descending: true).limit(120);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingList();
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const _EmptyList();

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final d = docs[i];
            final m = d.data();
            final taskId = d.id;

            final title = (m['title'] ?? 'Task').toString();
            final status = (m['status'] ?? '-').toString();
            final city = (m['city'] ?? m['address'] ?? '').toString();
            final ts = m['updatedAt'] ?? m['createdAt'];
            final price = _bestBudgetText(m);

            // (Optional) Disable controls for non-assigned helpers
            final myUid = FirebaseAuth.instance.currentUser?.uid;
            final assignedHelperId =
            (m['helperId'] ?? m['assignedHelperId'] ?? '').toString();
            final isMine = myUid != null && myUid == assignedHelperId;

            final s = status.toLowerCase();
            final canEditProofs = !(s.contains('complete') || s.contains('cancel') || s.contains('disput'));

            return Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.12),
                      child: const Icon(Icons.work_outline_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: -6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (city.isNotEmpty) _ChipText(city),
                              if (price != null) _ChipText(price),
                              _TimeChip(ts),
                              StatusChip(status),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Proofs Panel
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: _ProofsPanel(
                              taskId: taskId,
                              canEdit: canEditProofs,
                              onAdd: () => _addProofPhotos(context, taskId),
                              onRemove: (url) => _removeProof(context, taskId, url),
                              onPreview: (url) => _previewImage(context, url),
                            ),
                          ),
                          // Actions
                          _actionsFor(context, d.id, status, isMine, m),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------- Small UI helpers ----------

class _ProofsPanel extends StatelessWidget {
  const _ProofsPanel({
    required this.taskId,
    required this.canEdit,
    required this.onAdd,
    required this.onRemove,
    required this.onPreview,
  });

  final String taskId;
  final bool canEdit;
  final VoidCallback onAdd;
  final void Function(String url) onRemove;
  final void Function(String url) onPreview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
      FirebaseFirestore.instance.collection('tasks').doc(taskId).snapshots(),
      builder: (context, snap) {
        final m = snap.data?.data() ?? const <String, dynamic>{};
        final proofs = (m['proofUrls'] is List)
            ? List<String>.from(m['proofUrls'])
            : const <String>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Proof photos',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                if (canEdit)
                  TextButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_a_photo_rounded),
                    label: const Text('Add'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (proofs.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outline.withOpacity(0.12)),
                ),
                child: Text(
                  canEdit
                      ? 'Add 1–3 photos as proof of completion.'
                      : 'No proof photos.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              )
            else
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: proofs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final url = proofs[i];
                    return Stack(
                      children: [
                        GestureDetector(
                          onTap: () => onPreview(url),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(url,
                                height: 92, width: 120, fit: BoxFit.cover),
                          ),
                        ),
                        if (canEdit)
                          Positioned(
                            right: 4,
                            top: 4,
                            child: IconButton.filledTonal(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => onRemove(url),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

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

class _TimeChip extends StatelessWidget {
  const _TimeChip(this.ts);
  final dynamic ts;

  @override
  Widget build(BuildContext context) {
    String label = '—';
    if (ts is Timestamp) {
      label = _timeAgo(ts.toDate());
    } else if (ts is DateTime) {
      label = _timeAgo(ts);
    }
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: 6,
      itemBuilder: (_, i) {
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.work_outline)),
            title: Container(height: 12, width: 120, color: Colors.black12),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Container(height: 10, width: 60, color: Colors.black12),
                  const SizedBox(width: 8),
                  Container(height: 10, width: 80, color: Colors.black12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 44, color: cs.outline),
            const SizedBox(height: 10),
            const Text('Nothing here yet.'),
            const SizedBox(height: 4),
            const Text('Jobs you accept will appear here.'),
          ],
        ),
      ),
    );
  }
}

// ---------- Budget helpers ----------

String? _bestBudgetText(Map<String, dynamic> task) {
  final num? finalAmount = task['finalAmount'] as num?;
  final num? price = task['price'] as num?;
  final num? minB = task['budgetMin'] as num?;
  final num? maxB = task['budgetMax'] as num?;
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
