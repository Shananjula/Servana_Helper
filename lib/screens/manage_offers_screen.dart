// lib/screens/manage_offers_screen.dart
//
// Manage Offers (Helper app)
// --------------------------
// - Default view shows the offers *you* (helper) have sent.
// - Second tab shows "Incoming" offers (rare in your flow; tolerant fallback).
// - Works with either:
//     A) Top-level collection: /offers
//     B) Subcollection: /tasks/{taskId}/offers
// - Normalized offer fields used by UI:
//     taskId, posterId, helperId, price, message, status, createdAt/updatedAt
//
// Actions (helper):
//   • Edit (price)  • Withdraw
// (Accept/Decline is for posters; disabled here.)
//
// Notes:
// - No FAKE placeholders: uses real ConversationScreen/TaskDetailsScreen.
// - Reads last/created timestamps defensively.
// - If both sources exist, results are merged & de-duped by id.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:servana/screens/step_2_documents.dart' as step2;

import 'package:servana/screens/task_details_screen.dart';
import 'package:servana/screens/conversation_screen.dart';

class ManageOffersScreen extends StatefulWidget {
  const ManageOffersScreen({super.key, this.taskId});

  /// Optional: scope to a specific task (shows offers tied to this task).
  final String? taskId;

  @override
  State<ManageOffersScreen> createState() => _ManageOffersScreenState();
}

class _ManageOffersScreenState extends State<ManageOffersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  String _sort = 'recent'; // 'recent' | 'price_low' | 'price_high'

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isScoped = widget.taskId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isScoped ? 'Offers for task' : 'My offers'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Sent'),
            Tab(text: 'Incoming'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Sort',
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'recent', child: Text('Recent')),
              PopupMenuItem(value: 'price_low', child: Text('Price · Low → High')),
              PopupMenuItem(value: 'price_high', child: Text('Price · High → Low')),
            ],
            icon: const Icon(Icons.sort),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _OffersTab(
            scopeTaskId: widget.taskId,
            mode: _OffersMode.sent,
            sort: _sort,
          ),
          _OffersTab(
            scopeTaskId: widget.taskId,
            mode: _OffersMode.incoming,
            sort: _sort,
          ),
        ],
      ),
    );
  }
}

enum _OffersMode { sent, incoming }

class _OffersTab extends StatelessWidget {
  const _OffersTab({
    required this.scopeTaskId,
    required this.mode,
    required this.sort,
  });

  final String? scopeTaskId;
  final _OffersMode mode;
  final String sort;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('Please sign in.'));
    }

    return StreamBuilder<List<OfferDoc>>(
      stream: _offersStream(uid, mode, sort, scopeTaskId: scopeTaskId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingList();
        }
        final offers = snap.data ?? const <OfferDoc>[];
        if (offers.isEmpty) {
          return const _EmptyState();
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: offers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final offer = offers[i];
            return _OfferCard(
              offer: offer,
              mode: mode,
            );
          },
        );
      },
    );
  }
}

/// Merge top-level `/offers` and subcollection `/tasks/{id}/offers` streams,
/// filter by role and optional task scope, normalize, de-dupe, and sort.
Stream<List<OfferDoc>> _offersStream(
    String myUid,
    _OffersMode mode,
    String sort, {
      String? scopeTaskId,
    }) {
  final db = FirebaseFirestore.instance;

  // Top-level /offers queries
  Query<Map<String, dynamic>> baseTop = db.collection('offers');
  if (scopeTaskId != null) baseTop = baseTop.where('taskId', isEqualTo: scopeTaskId);
  if (mode == _OffersMode.sent) {
    baseTop = baseTop.where('helperId', isEqualTo: myUid);
  } else {
    baseTop = baseTop.where('helperId', isEqualTo: myUid); // Helper rarely receives offers, but poster may counter.
  }

  // Sorting preference for top-level
  if (sort == 'price_low') {
    baseTop = baseTop.orderBy('price', descending: false);
  } else if (sort == 'price_high') {
    baseTop = baseTop.orderBy('price', descending: true);
  } else {
    baseTop = baseTop.orderBy('createdAt', descending: true);
  }

  final topStream = baseTop.limit(200).snapshots();

  // Subcollection fallback: /tasks/{taskId}/offers
  Stream<QuerySnapshot<Map<String, dynamic>>> subStream;

  if (scopeTaskId != null) {
    // Scoped to a known task
    Query<Map<String, dynamic>> q = db.collection('tasks').doc(scopeTaskId).collection('offers');
    if (mode == _OffersMode.sent) {
      q = q.where('helperId', isEqualTo: myUid);
    } else {
      // "Incoming" for helper = offers that changed (e.g., counter). We still read all and filter later.
    }
    if (sort == 'price_low') {
      q = q.orderBy('price', descending: false);
    } else if (sort == 'price_high') {
      q = q.orderBy('price', descending: true);
    } else {
      q = q.orderBy('createdAt', descending: true);
    }
    subStream = q.limit(200).snapshots();
  } else {
    // Unscoped: pull a best-effort union by first reading recent tasks where I'm involved as helper,
    // then listening to each offers subcollection. To keep Phase-0 simple and cheap, we skip this
    // fan-out and rely on top-level /offers OR let the UI be satisfied by top-level results.
    subStream = const Stream.empty();
  }

  // Combine both sources
  return StreamZipLike([topStream, subStream]).map((snaps) {
    final out = <OfferDoc>[];

    for (final qs in snaps) {
      for (final d in qs.docs) {
        out.add(OfferDoc.from(d.id, d.data(), taskId: scopeTaskId));
      }
    }

    // Role filtering for "incoming": keep counters/accepted targeting me, but avoid duplicating "sent"
    final filtered = (mode == _OffersMode.sent)
        ? out.where((o) => o.helperId == myUid).toList()
        : out.where((o) => o.helperId == myUid && (o.status != 'pending' || o.message?.isNotEmpty == true)).toList();

    // De-dupe by (taskId, helperId, id)
    final seen = <String, OfferDoc>{};
    for (final o in filtered) {
      seen['${o.taskId}::${o.helperId}::${o.id}'] = o;
    }

    final list = seen.values.toList();

    // Sort final regardless of stream order
    list.sort((a, b) {
      if (sort == 'price_low') {
        return (a.price ?? 0).compareTo(b.price ?? 0);
      }
      if (sort == 'price_high') {
        return (b.price ?? 0).compareTo(a.price ?? 0);
      }
      final aTs = a.updatedAt ?? a.createdAt;
      final bTs = b.updatedAt ?? b.createdAt;
      return (bTs ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(aTs ?? DateTime.fromMillisecondsSinceEpoch(0));
    });

    return list;
  });
}

/// Simple "zip-like" combiner that emits a list of latest snapshots from multiple streams,
/// but also works if one of them is empty.
class StreamZipLike<T> extends Stream<List<T>> {
  StreamZipLike(this._streams);

  final List<Stream<T>> _streams;

  @override
  StreamSubscription<List<T>> listen(void Function(List<T>)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    if (_streams.isEmpty) {
      return Stream<List<T>>.value(<T>[]).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
    }

    final latest = List<T?>.filled(_streams.length, null);
    final has = List<bool>.filled(_streams.length, false);
    final controller = StreamController<List<T>>();
    final subs = <StreamSubscription<T>>[];

    void tryEmit() {
      // Emit only when at least one stream has emitted (the other may be empty)
      final any = has.any((v) => v);
      if (!any) return;
      controller.add(latest.whereType<T>().toList());
    }

    for (var i = 0; i < _streams.length; i++) {
      final s = _streams[i].listen((value) {
        has[i] = true;
        latest[i] = value;
        tryEmit();
      }, onError: controller.addError, onDone: null, cancelOnError: cancelOnError);
      subs.add(s);
    }

    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };

    return controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

// ===================== OFFER CARD =====================

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.mode});

  final OfferDoc offer;
  final _OffersMode mode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: price + status chip
            Row(
              children: [
                Text(
                  offer.price != null ? 'LKR ${offer.price!.toStringAsFixed(0)}' : 'No price',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 8),
                _StatusChip(offer.status),
                const Spacer(),
                IconButton(
                  tooltip: 'Open task',
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: offer.taskId)),
                  ),
                ),
              ],
            ),
            if ((offer.message ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(offer.message!, style: TextStyle(color: cs.onSurfaceVariant)),
            ],
            const SizedBox(height: 8),

            // Actions (helper)
            Row(
              children: [
                // Accept/Decline disabled for helper (poster-only)
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Accept'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.close),
                  label: const Text('Decline'),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: offer.status == 'pending' ? () => _editOffer(context, offer) : null,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: offer.status == 'pending' ? () => _withdrawOffer(context, offer) : null,
                  icon: const Icon(Icons.undo),
                  label: const Text('Withdraw'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _openChat(context, offer),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Chat'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openChat(BuildContext context, OfferDoc offer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          channelId: offer.channelId, // may be null; ConversationScreen can create by otherUserId
          otherUserId: offer.posterId.isNotEmpty ? offer.posterId : null,
        ),
      ),
    );
  }

  Future<void> _editOffer(BuildContext context, OfferDoc offer) async {
    final ctrl = TextEditingController(
      text: offer.price == null ? '' : offer.price!.toStringAsFixed(0),
    );
    final newText = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit offer price'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Enter new price (LKR)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (newText == null) return;

    final newPrice = num.tryParse(newText);
    if (newPrice == null) {
      _toast(context, 'Invalid price');
      return;
    }

    try {
      if (offer.isSubcollection) {
        await FirebaseFirestore.instance
            .collection('tasks')
            .doc(offer.taskId)
            .collection('offers')
            .doc(offer.id)
            .update({
          'price': newPrice.toDouble(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseFirestore.instance.collection('offers').doc(offer.id).update({
          'price': newPrice.toDouble(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      _toast(context, 'Offer updated.');
    } catch (e) {
      _toast(context, 'Could not update: $e', err: true);
    }
  }

  Future<void> _withdrawOffer(BuildContext context, OfferDoc offer) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Withdraw offer'),
        content: const Text('Withdraw this offer?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      if (offer.isSubcollection) {
        await FirebaseFirestore.instance
            .collection('tasks')
            .doc(offer.taskId)
            .collection('offers')
            .doc(offer.id)
            .update({
          'status': 'withdrawn',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseFirestore.instance.collection('offers').doc(offer.id).update({
          'status': 'withdrawn',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      _toast(context, 'Offer withdrawn.');
    } catch (e) {
      _toast(context, 'Could not withdraw: $e', err: true);
    }
  }

  void _toast(BuildContext context, String msg, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: err ? Colors.red : null),
    );
  }
}

// ===================== MODELS & UI BITS =====================

class OfferDoc {
  OfferDoc({
    required this.id,
    required this.taskId,
    required this.posterId,
    required this.helperId,
    required this.status,
    this.price,
    this.message,
    this.createdAt,
    this.updatedAt,
    this.channelId,
    this.isSubcollection = false,
  });

  final String id;
  final String taskId;
  final String posterId;
  final String helperId;
  final double? price;
  final String? message;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? channelId; // optional chat link
  final bool isSubcollection;

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static DateTime? _asDate(dynamic ts) {
    if (ts == null) return null;
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return null;
  }

  factory OfferDoc.from(String id, Map<String, dynamic> m, {String? taskId}) {
    // Normalize common shapes (`amount` vs `price`, `message` vs `note`, etc.)
    final price = _asDouble(m['price'] ?? m['amount']);
    final msg = (m['message'] ?? m['note'])?.toString();

    return OfferDoc(
      id: id,
      taskId: taskId ?? (m['taskId']?.toString() ?? ''),
      posterId: (m['posterId']?.toString() ?? ''),
      helperId: (m['helperId']?.toString() ?? ''),
      price: price,
      message: msg,
      status: (m['status']?.toString() ?? 'pending'),
      createdAt: _asDate(m['createdAt']),
      updatedAt: _asDate(m['updatedAt']),
      channelId: (m['channelId']?.toString()),
      isSubcollection: taskId != null, // when read from /tasks/{taskId}/offers
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = _statusTone(status);
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: tone.withOpacity(0.25)),
      backgroundColor: tone.withOpacity(0.10),
    );
  }

  (String, Color) _statusTone(String s) {
    switch (s) {
      case 'pending':
        return ('Pending', Colors.blue);
      case 'accepted':
        return ('Accepted', Colors.green);
      case 'declined':
        return ('Declined', Colors.red);
      case 'withdrawn':
        return ('Withdrawn', Colors.grey);
      case 'counter':
        return ('Counter', Colors.amber);
      default:
        return (s, Colors.blueGrey);
    }
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
            leading: const CircleAvatar(child: Icon(Icons.local_offer)),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
            const Text('No offers here yet.'),
            const SizedBox(height: 4),
            const Text('Create or edit offers from task details.'),
          ],
        ),
      ),
    );
  }
}
Widget _verifyBanner(BuildContext context, String categoryId) {
  return Container(
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceVariant,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        const Icon(Icons.lock_outline, size: 16),
        const SizedBox(width: 6),
        Expanded(child: Text('This category is locked for you. Verify to proceed.', maxLines: 2)),
        TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => step2.Step2Documents(initialCategoryId: categoryId))),
          child: const Text('Verify for'),
        )
      ],
    ),
  );
}
