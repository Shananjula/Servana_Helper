import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/activity_filter.dart';
import '../widgets/activity_filter_sheet.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with AutomaticKeepAliveClientMixin<ActivityScreen> {
  ActivityFilter _filter = ActivityFilter.defaultForHelper();

  @override
  bool get wantKeepAlive => true;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ---------- Streams (Helper perspective) ----------
  //
  // Tasks stream merges:
  //  - tasks where participantIds contains uid
  //  - tasks where assignedHelperId == uid
  //
  // We merge client-side into a List<Doc>, instead of faking a QuerySnapshot.

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _tasksStream() {
    final uid = _uid;
    if (uid == null) {
      return const Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.empty();
    }

    final statuses = _filter.statuses.take(10).toList();
    Query<Map<String, dynamic>> base =
    FirebaseFirestore.instance.collection('tasks');

    if (statuses.isNotEmpty) {
      base = base.where('status', whereIn: statuses);
    }

    final pStream = base.where('participantIds', arrayContains: uid).snapshots();
    final aStream = base.where('assignedHelperId', isEqualTo: uid).snapshots();

    return StreamZip2(pStream, aStream).map((tuple) {
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = [];
      final seen = <String>{};

      void addAll(QuerySnapshot<Map<String, dynamic>> snap) {
        for (final d in snap.docs) {
          if (seen.add(d.id)) docs.add(d);
        }
      }

      addAll(tuple.$1);
      addAll(tuple.$2);

      // Sort by updatedAt/createdAt desc if available
      docs.sort((a, b) {
        DateTime ts(QueryDocumentSnapshot<Map<String, dynamic>> d) {
          final data = d.data();
          final raw = data['updatedAt'] ?? data['createdAt'];
          if (raw is Timestamp) return raw.toDate();
          if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
          return DateTime.fromMillisecondsSinceEpoch(0);
        }

        return ts(b).compareTo(ts(a));
      });

      return docs;
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _offersStream() {
    final uid = _uid;
    if (uid == null) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }

    final statuses = _filter.statuses.take(10).toList();
    Query<Map<String, dynamic>> q =
    FirebaseFirestore.instance.collection('offers')
        .where('helperId', isEqualTo: uid);

    if (statuses.isNotEmpty) {
      q = q.where('status', whereIn: statuses);
    }
    return q.snapshots();
  }

  Stream<_UnifiedActivity> _allStream() {
    return StreamZip2(_tasksStream(), _offersStream()).map((tuple) {
      final taskDocs = tuple.$1;
      final offerSnap = tuple.$2;

      final tasks = taskDocs.map((d) => _ActivityItem.task(d)).toList();
      final offers = offerSnap.docs.map((d) => _ActivityItem.offer(d)).toList();
      final items = <_ActivityItem>[];
      items..addAll(tasks)..addAll(offers);

      items.sort((a, b) {
        final at = a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return _UnifiedActivity(items);
    });
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Activity'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'All'),
              Tab(text: 'Tasks'),
              Tab(text: 'Offers'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Filter',
              icon: const Icon(Icons.filter_alt_outlined),
              onPressed: _openFilter,
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _AllTab(stream: _allStream, onRefresh: _refresh),
            _TasksTab(stream: _tasksStream, onRefresh: _refresh),
            _OffersTab(stream: _offersStream, onRefresh: _refresh),
          ],
        ),
      ),
    );
  }

  Future<void> _openFilter() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ActivityFilterSheet(
        initial: _filter,
        onApply: (f) => setState(() => _filter = f),
        onClear: () => setState(() {
          _filter = ActivityFilter.defaultForHelper();
        }),
      ),
    );
  }

  Future<void> _refresh() async {
    // If you add caches/paging, hook it here.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

// ---------- Tabs ----------

class _AllTab extends StatelessWidget {
  final Stream<_UnifiedActivity> Function() stream;
  final Future<void> Function() onRefresh;
  const _AllTab({required this.stream, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: StreamBuilder<_UnifiedActivity>(
        stream: stream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _LoadingList();
          }
          if (snap.hasError) {
            return _ErrorView(error: snap.error);
          }
          final items = snap.data?.items ?? const <_ActivityItem>[];
          if (items.isEmpty) {
            return const _EmptyView(message: 'No activity yet.');
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => items[i].buildTile(context),
          );
        },
      ),
    );
  }
}

class _TasksTab extends StatelessWidget {
  final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> Function() stream;
  final Future<void> Function() onRefresh;
  const _TasksTab({required this.stream, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: stream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _LoadingList();
          }
          if (snap.hasError) {
            return _ErrorView(error: snap.error);
          }
          final docs = snap.data ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          if (docs.isEmpty) {
            return const _EmptyView(message: 'No tasks found.');
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();
              return ListTile(
                leading: const Icon(Icons.work_outline),
                title: Text(data['title']?.toString() ?? 'Task'),
                subtitle: Text(
                  (data['status']?.toString() ?? '').toUpperCase(),
                ),
                onTap: () {
                  // TODO: navigate to your Task Details screen
                  // Navigator.push(...);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _OffersTab extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> Function() stream;
  final Future<void> Function() onRefresh;
  const _OffersTab({required this.stream, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _LoadingList();
          }
          if (snap.hasError) {
            return _ErrorView(error: snap.error);
          }
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return const _EmptyView(message: 'No offers yet.');
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();
              return ListTile(
                leading: const Icon(Icons.local_offer_outlined),
                title: Text(data['taskTitle']?.toString() ?? 'Offer'),
                subtitle: Text(
                  (data['status']?.toString() ?? '').toUpperCase(),
                ),
                onTap: () {
                  // TODO: navigate to your Offer / Thread
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ---------- Helpers & widgets ----------

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: 8,
      itemBuilder: (context, i) => const ListTile(
        leading: CircleAvatar(radius: 16),
        title: SizedBox(height: 16, child: DecoratedBox(decoration: BoxDecoration())),
        subtitle: SizedBox(height: 12, child: DecoratedBox(decoration: BoxDecoration())),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final String message;
  const _EmptyView({required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 64),
        Center(
          child: Column(
            children: [
              const Icon(Icons.inbox_outlined, size: 48),
              const SizedBox(height: 12),
              Text(message),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object? error;
  const _ErrorView({this.error});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 64),
        Center(
          child: Column(
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text('Something went wrong.'),
              if (error != null) Text('$error', style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

// Activity item for the "All" tab
class _ActivityItem {
  final String kind; // 'task' | 'offer'
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  const _ActivityItem._(this.kind, this.doc);

  factory _ActivityItem.task(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
      _ActivityItem._('task', d);
  factory _ActivityItem.offer(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
      _ActivityItem._('offer', d);

  DateTime? get timestamp {
    final data = doc.data();
    final ts = data['updatedAt'] ?? data['createdAt'];
    if (ts is Timestamp) return ts.toDate();
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
    return null;
  }

  Widget buildTile(BuildContext context) {
    final data = doc.data();
    switch (kind) {
      case 'task':
        return ListTile(
          leading: const Icon(Icons.work_outline),
          title: Text(data['title']?.toString() ?? 'Task'),
          subtitle: Text((data['status']?.toString() ?? '').toUpperCase()),
          onTap: () {
            // TODO: push Task Details
          },
        );
      case 'offer':
        return ListTile(
          leading: const Icon(Icons.local_offer_outlined),
          title: Text(data['taskTitle']?.toString() ?? 'Offer'),
          subtitle: Text((data['status']?.toString() ?? '').toUpperCase()),
          onTap: () {
            // TODO: push Offer / Thread
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _UnifiedActivity {
  final List<_ActivityItem> items;
  const _UnifiedActivity(this.items);
}

/// Minimal two-stream zipper (no extra deps).
/// Emits once both have produced at least one event, then on any subsequent change.
class StreamZip2<A, B> extends Stream<(A, B)> {
  final Stream<A> _a;
  final Stream<B> _b;
  const StreamZip2(this._a, this._b);

  @override
  StreamSubscription<(A, B)> listen(void Function((A, B) event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    A? lastA;
    B? lastB;
    bool hasA = false, hasB = false;
    late StreamController<(A, B)> c;
    StreamSubscription<A>? subA;
    StreamSubscription<B>? subB;

    void maybeEmit() {
      if (hasA && hasB) c.add((lastA as A, lastB as B));
    }

    c = StreamController<(A, B)>(
      onListen: () {
        subA = _a.listen((a) {
          lastA = a;
          hasA = true;
          maybeEmit();
        }, onError: c.addError, onDone: () {
          // keep alive while the other is active
        });

        subB = _b.listen((b) {
          lastB = b;
          hasB = true;
          maybeEmit();
        }, onError: c.addError, onDone: () {
          // keep alive while the other is active
        });
      },
      onPause: () {
        subA?.pause();
        subB?.pause();
      },
      onResume: () {
        subA?.resume();
        subB?.resume();
      },
      onCancel: () async {
        await subA?.cancel();
        await subB?.cancel();
      },
    );
    return c.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}
