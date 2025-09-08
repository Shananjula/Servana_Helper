// lib/screens/helper_browse_tasks_screen.dart
//
// Helper “Find Work” — robust Verified gating (slug-based), Physical/Online toggle, Map pins
// -------------------------------------------------------------------------------------------

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'task_details_screen.dart';

enum TaskTypeFilter { all, physical, online }

class HelperBrowseTasksScreen extends StatefulWidget {
  const HelperBrowseTasksScreen({
    super.key,
    this.initialCategoryId,
    this.initialOnlyVerified = false,
    this.initialMapMode = false,
    this.initialSearch,
    this.initialType = TaskTypeFilter.all,
  });

  final String? initialCategoryId;
  final bool initialOnlyVerified;
  final bool initialMapMode;
  final String? initialSearch;
  final TaskTypeFilter initialType;

  @override
  State<HelperBrowseTasksScreen> createState() => _HelperBrowseTasksScreenState();
}

class _HelperBrowseTasksScreenState extends State<HelperBrowseTasksScreen> {
  late final TextEditingController _searchCtrl;
  late String _search;
  String? _selectedCatId;
  late bool _onlyVerified;
  late bool _mapMode;
  late TaskTypeFilter _type;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream;

  bool _loading = false;
  String? _error;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = const [];

  // map state
  LatLng? _userLatLng;

  @override
  void initState() {
    super.initState();
    _search = (widget.initialSearch ?? '').trim();
    _searchCtrl = TextEditingController(text: _search);
    _selectedCatId = widget.initialCategoryId;
    _onlyVerified = widget.initialOnlyVerified;
    _mapMode = widget.initialMapMode;
    _type = widget.initialType;

    _searchCtrl.addListener(() {
      final next = _searchCtrl.text;
      if (next != _search) {
        setState(() => _search = next);
        _reload();
      }
    });

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _userStream = FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    }

    _getUserLocation();
    _reload();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) return;
      final p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() => _userLatLng = LatLng(p.latitude, p.longitude));
    } catch (_) {}
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _readCategories() async {
    final snap = await FirebaseFirestore.instance.collection('categories').get();
    return snap.docs;
  }

  String _slug(String s) {
    final lower = s.toLowerCase();
    final replaced = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final squashed = replaced.replaceAll(RegExp(r'_+'), '_');
    final trimmed = squashed.replaceAll(RegExp(r'^_|_$'), '');
    return trimmed;
  }

  Set<String> _canonSet(dynamic v) {
    final out = <String>{};
    if (v is String && v.trim().isNotEmpty) out.add(_slug(v));
    if (v is Iterable) {
      for (final x in v) {
        final s = x?.toString() ?? '';
        if (s.trim().isNotEmpty) out.add(_slug(s));
      }
    }
    return out;
  }

  Set<String> _taskCandidates(Map<String, dynamic> t) {
    final s = <String>{};
    s.addAll(_canonSet(t['categoryId']));
    s.addAll(_canonSet(t['category']));
    s.addAll(_canonSet(t['categoryIds']));
    s.addAll(_canonSet(t['categoryTokens']));
    return s;
  }

  Set<String> _allowedFromUser(Map<String, dynamic> u) {
    final s = <String>{};
    s.addAll(_canonSet(u['allowedCategoryIds']));
    // tolerate a legacy field that might store labels instead of ids
    s.addAll(_canonSet(u['allowedCategoryLabels']));
    return s;
  }

  void _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _docs = const [];
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final userSnap = (uid != null) ? await FirebaseFirestore.instance.collection('users').doc(uid).get() : null;
      final allowedRaw = userSnap?.data() ?? const <String, dynamic>{};
      final allowed = _allowedFromUser(allowedRaw);

      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('tasks')
          .where('status', whereIn: ['open', 'listed', 'negotiating', 'negotiation'])
          .orderBy('createdAt', descending: true);

      if (_selectedCatId != null) {
        q = q.where('categoryId', isEqualTo: _selectedCatId);
      } else if (_onlyVerified && allowed.isNotEmpty) {
        final first10 = allowed.take(10).toList();
        q = q.where('categoryId', whereIn: first10);
      }

      if (_type == TaskTypeFilter.physical) {
        q = q.where('type', isEqualTo: 'physical');
      } else if (_type == TaskTypeFilter.online) {
        q = q.where('type', isEqualTo: 'online');
      }

      final snap = await q.limit(200).get();
      var docs = snap.docs;

      final term = _search.trim().toLowerCase();
      if (term.isNotEmpty) {
        docs = docs.where((d) {
          final m = d.data();
          final title = (m['title'] ?? '').toString().toLowerCase();
          final desc = (m['description'] ?? '').toString().toLowerCase();
          return title.contains(term) || desc.contains(term);
        }).toList();
      }

      setState(() => _docs = docs);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    final weeks = d.inDays ~/ 7;
    if (weeks < 5) return '${weeks}w ago';
    final months = d.inDays ~/ 30;
    if (months < 12) return '${months}mo ago';
    final years = d.inDays ~/ 365;
    return '${years}y ago';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream,
      builder: (context, usnap) {
        final u = usnap.data?.data() ?? const <String, dynamic>{};
        final allowed = _allowedFromUser(u);

        return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          future: _readCategories(),
          builder: (context, csnap) {
            final categories = csnap.data ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final catLabelMap = {for (final d in categories) d.id: (d.data()['label'] ?? d.id).toString()};

            return Scaffold(
              appBar: AppBar(
                title: const Text('Find Work'),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SegmentedButton<TaskTypeFilter>(
                      segments: const [
                        ButtonSegment(value: TaskTypeFilter.all, icon: Icon(Icons.all_inclusive), label: Text('All')),
                        ButtonSegment(value: TaskTypeFilter.physical, icon: Icon(Icons.handyman), label: Text('Physical')),
                        ButtonSegment(value: TaskTypeFilter.online, icon: Icon(Icons.wifi_tethering), label: Text('Online')),
                      ],
                      selected: {_type},
                      onSelectionChanged: (s) {
                        setState(() => _type = s.first);
                        _reload();
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: _mapMode ? 'List' : 'Map',
                    onPressed: () => setState(() => _mapMode = !_mapMode),
                    icon: Icon(_mapMode ? Icons.view_list_rounded : Icons.map_rounded),
                  ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(64),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Search tasks…',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ),
              body: Column(
                children: [
                  SizedBox(
                    height: 56,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      scrollDirection: Axis.horizontal,
                      children: [
                        FilterChip(
                          label: const Text('All categories'),
                          selected: _selectedCatId == null,
                          onSelected: (sel) {
                            setState(() => _selectedCatId = null);
                            _reload();
                          },
                        ),
                        const SizedBox(width: 6),
                        for (final d in categories)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(catLabelMap[d.id]!.replaceAll('_',' ')),
                              selected: _selectedCatId == d.id,
                              onSelected: (sel) {
                                setState(() => _selectedCatId = sel ? d.id : null);
                                _reload();
                              },
                            ),
                          ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Only verified'),
                          selected: _onlyVerified,
                          onSelected: (sel) {
                            setState(() => _onlyVerified = sel);
                            _reload();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _mapMode
                        ? _TasksMapView(
                            docs: _docs,
                            userLatLng: _userLatLng,
                            onOpen: (taskId) => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: taskId))),
                          )
                        : _buildList(catLabelMap, allowed),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildList(Map<String, String> catLabelMap, Set<String> allowed) {
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center)));
    }
    if (_loading && _docs.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_docs.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 120),
        Icon(Icons.work_outline, size: 40),
        SizedBox(height: 8),
        Center(child: Text('No tasks found')),
        SizedBox(height: 200),
      ]);
    }

    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView.builder(
        itemCount: _docs.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Icon(_loading ? Icons.downloading_rounded : Icons.list_alt_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text('${_docs.length} task${_docs.length == 1 ? '' : 's'}'),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _loading ? null : _reload,
                    icon: _loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            );
          }

          final d = _docs[i - 1];
          final t = d.data();
          final cand = _taskCandidates(t);
          final isVerified = cand.any(allowed.contains);

          final String title = (t['title'] ?? 'Untitled').toString();
          final String desc = (t['description'] ?? '').toString();
          final String city = (t['city'] ?? '').toString();
          final String address = (t['addressShort'] ?? '').toString();
          final dynamic priceRaw = t['price'] ?? t['amount'] ?? t['budget'];
          final String priceText = priceRaw == null ? '' : priceRaw.toString();
          final Timestamp? createdTs = t['createdAt'] is Timestamp ? t['createdAt'] as Timestamp : null;
          final catId = (t['categoryId'] ?? '').toString();

          return Card(
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: d.id))),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                        if (isVerified) const Chip(label: Text('Verified'), visualDensity: VisualDensity.compact),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: -6,
                      children: [
                        if (catId.isNotEmpty) Chip(label: Text(catLabelMap[catId] ?? catId.replaceAll('_', ' ')), visualDensity: VisualDensity.compact),
                        if (city.isNotEmpty) Chip(label: Text(city), visualDensity: VisualDensity.compact),
                        if (address.isNotEmpty) Chip(label: Text(address), visualDensity: VisualDensity.compact),
                        if (priceText.isNotEmpty) Chip(label: Text(priceText), visualDensity: VisualDensity.compact),
                        if (createdTs != null) Chip(label: Text(_timeAgo(createdTs.toDate())), visualDensity: VisualDensity.compact),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Map view shows only physical tasks (with location)
class _TasksMapView extends StatelessWidget {
  const _TasksMapView({required this.docs, required this.userLatLng, required this.onOpen});
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final LatLng? userLatLng;
  final void Function(String taskId) onOpen;

  @override
  Widget build(BuildContext context) {
    final physical = docs.where((d) =>
      (d.data()['type'] ?? '').toString().toLowerCase() == 'physical' &&
      d.data()['location'] is GeoPoint
    ).toList();

    final markers = <Marker>{};
    for (final d in physical) {
      final m = d.data();
      final gp = m['location'] as GeoPoint;
      markers.add(Marker(
        markerId: MarkerId(d.id),
        position: LatLng(gp.latitude, gp.longitude),
        infoWindow: InfoWindow(title: (m['title'] ?? 'Task').toString(), onTap: () => onOpen(d.id)),
      ));
    }

    LatLng initial = const LatLng(6.9271, 79.8612); // Colombo default
    if (physical.isNotEmpty) {
      final gp = physical.first.data()['location'] as GeoPoint;
      initial = LatLng(gp.latitude, gp.longitude);
    } else if (userLatLng != null) {
      initial = userLatLng!;
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: initial, zoom: 12),
      markers: markers,
      myLocationEnabled: userLatLng != null,
      myLocationButtonEnabled: true,
    );
  }
}
