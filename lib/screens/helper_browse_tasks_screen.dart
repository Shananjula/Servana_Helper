// lib/screens/helper_browse_tasks_screen.dart
//
// Helper Browse (Phase 1)
// • Only shows tasks in users/{uid}.allowedCategoryIds
// • If allowed is empty -> “Get verified” nudge
// • Writes OFFERS to tasks/{taskId}/offers/{offerId}  ✅ (aligned with backend triggers)
// • UI-gates make-offer flow; Firestore rules still enforce
//
// Upgrade:
// • If a selected category has no tasks, show a friendly empty state with a Refresh button.
// • No endless spinner: we fetch once, and let the user refresh manually (pull-to-refresh or button).
// • Map view and the rest of your flow remain intact.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servana/screens/step_2_documents.dart' as step2;
import 'package:servana/utils/ttl_cache.dart';
import 'package:servana/widgets/mini_map_card.dart';

class HelperBrowseTasksScreen extends StatefulWidget {
  const HelperBrowseTasksScreen({super.key, this.initialCategoryId});
  final String? initialCategoryId;

  @override
  State<HelperBrowseTasksScreen> createState() =>
      _HelperBrowseTasksScreenState();
}

class _HelperBrowseTasksScreenState extends State<HelperBrowseTasksScreen> {
  static const _kOnlyVerified = 'helper_browse_only_verified';
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream;
  String _search = '';
  String? _selectedCatId; // null = All verified categories
  bool _onlyVerified = true;
  final _searchCtrl = TextEditingController();
  final _countCache = TtlCache<int>(ttl: const Duration(minutes: 5));
  bool _mapMode = false;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _userStream =
        FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    _loadPrefs(); // Load preferences when the screen initializes
    _searchCtrl.addListener(
            () => setState(() => _search = _searchCtrl.text.trim().toLowerCase()));
    _selectedCatId = widget.initialCategoryId; // seed filter from chip
  }

  Future<void> _loadPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final only = sp.getBool(_kOnlyVerified);
      if (only != null && mounted) setState(() => _onlyVerified = only);
    } catch (_) {}
  }

  Future<void> _saveOnlyVerified(bool v) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kOnlyVerified, v);
    } catch (_) {}
  }

  Future<int> _countFor(String catId) async {
    final cached = _countCache.get(catId);
    if (cached != null) return cached;

    try {
      final res = await FirebaseFirestore.instance
          .collection('tasks')
          .where('categoryId', isEqualTo: catId)
          .where('status', whereIn: ['open', 'listed', 'negotiating', 'negotiation'])
          .count()
          .get();

      // Some SDK versions expose `count` as `int?`
      final int c = res.count ?? 0;
      _countCache.set(catId, c);
      return c;
    } catch (_) {
      // If rules reject or index not ready, just show 0 (UI stays friendly)
      return 0;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse tasks'),
        centerTitle: false,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userStream,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final m = snap.data!.data() ?? {};

          final allowed = (m['allowedCategoryIds'] is List)
              ? List<String>.from(m['allowedCategoryIds'])
              .map((e) => e
              .toString()
              .trim()
              .toLowerCase()
              .replaceAll(RegExp(r'\s+'), '_'))
              .toSet()
              : <String>{};

          // Optional: a “pretty” label function (or you can use your catalog if present)
          String _pretty(String id) => id
              .split('_')
              .map((p) => p.isEmpty
              ? p
              : (p.toLowerCase() == 'ac'
              ? 'AC'
              : p[0].toUpperCase() + p.substring(1)))
              .join(' ');

          final registered = (m['registeredCategories'] is List)
              ? List<String>.from(m['registeredCategories'])
              : const <String>[];

          // A category is locked if it's in the registered list but not in the allowed set.
          final lockedCategories = registered.where((regId) {
            final normalizedId = regId
                .toString()
                .trim()
                .toLowerCase()
                .replaceAll(RegExp(r'\s+'), '_');
            return !allowed.contains(normalizedId);
          }).toList();
          final int lockedCount = lockedCategories.length;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search titles…',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Row(
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                            value: false,
                            label: Text('List'),
                            icon: Icon(Icons.view_list_rounded)),
                        ButtonSegment(
                            value: true,
                            label: Text('Map'),
                            icon: Icon(Icons.map_rounded)),
                      ],
                      selected: {_mapMode},
                      onSelectionChanged: (s) =>
                          setState(() => _mapMode = s.first),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
              if (allowed.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: _VerifyNudge(onGo: () {
                    Navigator.of(context).pushNamed('/verification');
                  }),
                )
              else if (allowed.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // “All” chip
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: const Text('All'),
                            selected: _selectedCatId == null,
                            onSelected: (_) =>
                                setState(() => _selectedCatId = null),
                          ),
                        ),
                        // Verified categories
                        ...(allowed.toList()..sort()).map((id) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FutureBuilder<int>(
                            future: _countFor(id),
                            builder: (ctx, cSnap) {
                              final cnt = cSnap.data ?? 0;
                              final label =
                                  '${_pretty(id)}${cnt > 0 ? ' · $cnt' : ''}';
                              return ChoiceChip(
                                label: Text(label),
                                selected: _selectedCatId == id,
                                onSelected: (_) =>
                                    setState(() => _selectedCatId = id),
                              );
                            },
                          ),
                        )),
                      ],
                    ),
                  ),
                ),

              if (allowed.isNotEmpty && lockedCount > 0)
                _LockedBanner(
                  locked: lockedCount,
                  onOpenDocs: () {
                    // Navigate to the docs upload screen, pre-selecting the first locked category.
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => step2.Step2Documents(
                          initialCategoryId: lockedCategories.first),
                    ));
                  },
                ),
              const Divider(height: 1),
              Expanded(
                child: _mapMode
                    ? _TasksMapView(categoryId: _selectedCatId)
                    : _TasksListView(
                  allowed: allowed,
                  search: _search,
                  selectedCatId: _selectedCatId,
                  pretty: _pretty,
                  onlyVerified: _onlyVerified,
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: null,
    );
  }
}

class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.locked, required this.onOpenDocs});
  final int locked;
  final VoidCallback onOpenDocs;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
              '$locked categor${locked == 1 ? "y" : "ies"} locked — upload required documents to unlock.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onOpenDocs,
            child: const Text('Upload'),
          ),
        ],
      ),
    );
  }
}

class _VerifyNudge extends StatelessWidget {
  const _VerifyNudge({required this.onGo});
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: cs.primary.withOpacity(0.12),
            foregroundColor: cs.primary,
            child: const Icon(Icons.verified_user_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Get verified in the categories you can work in to see matching tasks.',
              style: TextStyle(color: cs.onSurface),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(onPressed: onGo, child: const Text('Get verified')),
        ],
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.title, this.hint, this.onRefresh});
  final String title;
  final String? hint;
  final VoidCallback? onRefresh;

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
            Text(title, textAlign: TextAlign.center),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 14),
            if (onRefresh != null)
              ElevatedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
          ],
        ),
      ),
    );
  }
}

class _TasksListView extends StatefulWidget {
  const _TasksListView({
    required this.search,
    required this.selectedCatId,
    required this.pretty,
    required this.allowed,
    required this.onlyVerified,
  });

  final String search;
  final String? selectedCatId;
  final String Function(String) pretty;
  final Set<String> allowed;
  final bool onlyVerified;

  @override
  State<_TasksListView> createState() => _TasksListViewState();
}

class _TasksListViewState extends State<_TasksListView> {
  bool _loading = false;
  String? _error;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      Query<Map<String, dynamic>> q =
      FirebaseFirestore.instance.collection('tasks');

      // If a chip is selected, filter by that category id
      if (widget.selectedCatId != null) {
        q = q.where('categoryId', isEqualTo: widget.selectedCatId);
      }

      // Enforce rule-compliant filters: status must be one of the public marketplace states.
// Optional category scoping:
//   • If a chip is selected -> equality
//   • Else -> if 'only verified' is on -> whereIn with first 10 allowed cats
const allowedStatuses = ['open','listed','negotiating','negotiation'];
q = q.where('status', whereIn: allowedStatuses);

if (widget.selectedCatId != null) {
  // Already applied above – nothing else needed
} else if (widget.onlyVerified) {
  final cats = widget.allowed.take(10).toList();
  if (cats.isEmpty) {
    // Nothing to show; bail out early to avoid a whereIn([]) error.
    setState(() => _docs = const []);
    return;
  }
  q = q.where('categoryId', whereIn: cats);
}

// No Firestore orderBy to keep indices simple; do client-side sort after fetch.
q = q.limit(100);

final snap = await q.get();
      var docs = snap.docs;

      // Client-side filter: only show tasks in allowed categories when flag is set
      if (widget.onlyVerified) {
        docs = docs.where((doc) {
          final data = doc.data();
          final rawCat =
          (data['categoryId'] ?? data['category'] ?? '').toString();
          final catId = rawCat
              .trim()
              .toLowerCase()
              .replaceAll(RegExp(r'\s+'), '_');
          // Keep task if its category is in the allowed set, or if it has no category.
          return catId.isEmpty || widget.allowed.contains(catId);
        }).toList();
      }

      // Client-side search over title
      final search = widget.search.trim().toLowerCase();
      if (search.isNotEmpty) {
        docs = docs.where((d) {
          final title =
          (d.data()['title'] ?? '').toString().toLowerCase();
          return title.contains(search);
        }).toList();
      }

      if (!mounted) return;
      setState(() => _docs = docs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void didUpdateWidget(covariant _TasksListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If filters changed, reload
    if (oldWidget.selectedCatId != widget.selectedCatId ||
        oldWidget.search != widget.search ||
        oldWidget.onlyVerified != widget.onlyVerified ||
        oldWidget.allowed.length != widget.allowed.length) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.allowed.isEmpty) {
      return _EmptyList(
        title: 'No categories verified',
        hint: 'Choose categories and upload proofs to unlock tasks.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: _buildList(context),
    );
  }

  Widget _buildList(BuildContext context) {
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 64),
          _EmptyList(
            title: 'Couldn’t load tasks',
            hint: _error,
            onRefresh: _loading ? null : _load,
          ),
          const SizedBox(height: 48),
        ],
      );
    }

    if (_docs.isEmpty) {
      // Empty state — no endless spinner
      final selected = widget.selectedCatId;
      final catText = selected == null
          ? 'your verified categories'
          : widget.pretty(selected);
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 64),
          _EmptyList(
            title: 'No tasks right now',
            hint: 'No tasks in $catText.\nCome back later or tap Refresh to check for new tasks.',
            onRefresh: _loading ? null : _load,
          ),
          const SizedBox(height: 48),
        ],
      );
    }

    // Optional tiny header with refresh control
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _docs.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Row(
            children: [
              Text(
                '${_docs.length} task${_docs.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _loading ? null : _load,
                icon: _loading
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          );
        }

        final d = _docs[i - 1];
        final t = d.data();

        final title = (t['title'] ?? 'Task').toString();
        final city = (t['city'] ?? t['address'] ?? '').toString();
        final price = _bestBudgetText(t);

        final rawCat = (t['categoryId'] ?? t['category'] ?? '-').toString();
        final catId =
        rawCat.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
        final catLabel = (t['category'] ?? rawCat).toString();
        final isVerifiedForThis = widget.allowed.contains(catId);

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                  Theme.of(context).colorScheme.primary.withOpacity(0.12),
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
                          isVerifiedForThis
                              ? Chip(
                            avatar: const Icon(Icons.verified_rounded,
                                size: 18, color: Colors.green),
                            label: Text(
                                'Verified • ${catLabel.isEmpty ? catId : catLabel}'),
                            visualDensity: VisualDensity.compact,
                            backgroundColor:
                            Colors.green.withOpacity(0.12),
                            side: BorderSide(
                                color: Colors.green.withOpacity(0.25)),
                            labelStyle: TextStyle(
                                color: Colors.green.shade900,
                                fontWeight: FontWeight.w800),
                          )
                              : Chip(
                            label: Text(
                                catLabel.isEmpty ? catId : catLabel),
                            visualDensity: VisualDensity.compact,
                          ),
                          if (city.isNotEmpty) _ChipText(city),
                          if (price != null) _ChipText(price),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.local_offer_outlined, size: 18),
                  label: const Text('Make offer'),
                  onPressed: () => _openOfferSheet(context,
                      taskId: d.id, task: t),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openOfferSheet(BuildContext context,
      {required String taskId, required Map<String, dynamic> task}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sign in first.')));
      return;
    }
    final priceCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding:
        EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Make an offer',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Amount (LKR)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Note to poster (optional)',
                    border: OutlineInputBorder()),
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid amount.')));
      return;
    }

    try {
      // ✅ Write to tasks/{taskId}/offers so your backend triggers & notifications fire
      await FirebaseFirestore.instance
          .collection('tasks')
          .doc(taskId)
          .collection('offers')
          .add({
        'taskId': taskId,
        'posterId': task['posterId'] ?? '',
        'helperId': uid,
        'price': price,
        'message':
        noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Offer sent')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'), backgroundColor: Colors.red));
    }
  }
}

class _TasksMapView extends StatelessWidget {
  const _TasksMapView({this.categoryId});
  final String? categoryId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.surfaceVariant, cs.surface],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: MiniMapCard(mode: 'helper', categoryId: categoryId), // reuse
          ),
        ],
      ),
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
