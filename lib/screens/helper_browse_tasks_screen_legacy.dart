// lib/screens/helper_browse_tasks_screen.dart (LEGACY-STYLE UI)
//
// Matches your existing UI (All/Physical/Online + "All categories"/"Only verified")
// but fixes the Firestore query so it ALWAYS gates by the helper's allowedCategoryIds.
// "All categories" now means "all categories I'm allowed for".
// -----------------------------------------------------------------------------

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'task_details_screen.dart';

enum Mode { all, physical, online }

class HelperBrowseTasksScreen extends StatefulWidget {
  const HelperBrowseTasksScreen({super.key});
  @override
  State<HelperBrowseTasksScreen> createState() => _HelperBrowseTasksScreenState();
}

class _HelperBrowseTasksScreenState extends State<HelperBrowseTasksScreen> {
  final TextEditingController _search = TextEditingController();
  Mode _mode = Mode.all;

  // Chip state
  bool _onlyVerified = false; // this chip becomes purely visual now
  bool _allCategories = true; // this chip just shows that we're using "all allowed"

  bool _loading = true;
  String? _error;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  List<String> _allowed = [];

  static const List<String> _publicStatuses = <String>[
    'open', 'listed', 'negotiating', 'negotiation', 'active', 'published'
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() { _loading = true; _error = null; });
    try {
      // ensure user
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.authStateChanges().firstWhere((u) => u != null);
      }
      await _reload();
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _reload() async {
    setState(() { _loading = true; _error = null; _docs = []; });
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userSnap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final List<String> allowed = (userSnap.data()?['allowedCategoryIds'] is List)
          ? List<String>.from(userSnap.data()!['allowedCategoryIds'])
          : const <String>[];
      _allowed = allowed;

      if (allowed.isEmpty) {
        setState(() { _loading = false; _docs = []; });
        return;
      }

      // Build queries: ALWAYS gate by allowed categories (even when UI shows "All categories")
      final gate = _allowed; // "All categories" => all ALLOWED categories
      final chunks = <List<String>>[];
      for (int i = 0; i < gate.length; i += 10) {
        chunks.add(gate.sublist(i, (i + 10 > gate.length) ? gate.length : i + 10));
      }

      final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
      for (final cats in chunks) {
        Query<Map<String, dynamic>> q1 = FirebaseFirestore.instance
            .collection('tasks')
            .where('status', whereIn: _publicStatuses)
            .where('mainCategoryId', whereIn: cats);
        Query<Map<String, dynamic>> q2 = FirebaseFirestore.instance
            .collection('tasks')
            .where('status', whereIn: _publicStatuses)
            .where('categoryIds', arrayContainsAny: cats);

        if (_mode == Mode.physical) {
          q1 = q1.where('isPhysical', isEqualTo: true);
          q2 = q2.where('isPhysical', isEqualTo: true);
        } else if (_mode == Mode.online) {
          q1 = q1.where('isPhysical', isEqualTo: false);
          q2 = q2.where('isPhysical', isEqualTo: false);
        }

        futures.add(q1.limit(50).get());
        futures.add(q2.limit(50).get());
      }

      final results = await Future.wait(futures);
      final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> byId = {};
      for (final qs in results) {
        for (final d in qs.docs) {
          byId[d.id] = d;
        }
      }

      final list = byId.values.where((d) {
        final m = d.data();
        final text = ((_search.text).trim()).toLowerCase();
        if (text.isEmpty) return true;
        final title = (m['title'] ?? m['name'] ?? '').toString().toLowerCase();
        final desc = (m['description'] ?? '').toString().toLowerCase();
        return (title.contains(text) || desc.contains(text));
      }).toList();

      list.sort((a, b) {
        final ta = _ts(a.data()['createdAt'])?.millisecondsSinceEpoch ?? 0;
        final tb = _ts(b.data()['createdAt'])?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });

      setState(() { _loading = false; _docs = list; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Work'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _segmented(),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              onChanged: (_) => _reload(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search tasks...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilterChip(
                  selected: _allCategories,
                  onSelected: (v) => setState(() {
                    _allCategories = true; // visual only
                    _onlyVerified = false;
                    _reload();
                  }),
                  label: const Text('All categories'),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  selected: _onlyVerified,
                  onSelected: (v) => setState(() {
                    _onlyVerified = true; // visual only
                    _allCategories = false;
                    _reload();
                  }),
                  label: const Text('Only verified'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _segmented() {
    return LayoutBuilder(builder: (context, _) {
      return Row(
        children: [
          Expanded(child: _segBtn('All', Icons.check, Mode.all)),
          const SizedBox(width: 8),
          Expanded(child: _segBtn('Physical', Icons.handyman, Mode.physical)),
          const SizedBox(width: 8),
          Expanded(child: _segBtn('Online', Icons.podcasts, Mode.online)),
        ],
      );
    });
  }

  Widget _segBtn(String label, IconData icon, Mode value) {
    final selected = _mode == value;
    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: () => setState(() { _mode = value; _reload(); }),
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: selected ? Theme.of(context).colorScheme.primary.withOpacity(0.12) : null,
          foregroundColor: selected ? Theme.of(context).colorScheme.primary : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Text(_error!, textAlign: TextAlign.center),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_allowed.isEmpty) {
      return const Center(child: Text('You are not verified for any categories yet.'));
    }
    if (_docs.isEmpty) return const Center(child: Text('No tasks found.'));
    return ListView.builder(
      itemCount: _docs.length,
      itemBuilder: (_, i) {
        final d = _docs[i];
        final t = d.data();
        return Card(
          child: ListTile(
            title: Text((t['title'] ?? t['name'] ?? 'Untitled').toString()),
            subtitle: Text((t['city'] ?? t['description'] ?? '').toString()),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TaskDetailsScreen(taskId: d.id, task: t),
              ));
            },
          ),
        );
      },
    );
  }
}
