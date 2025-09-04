// lib/screens/map_view_screen.dart
//
// Full-screen interactive map for discovering Helpers (Poster mode)
// or OPEN Tasks (Helper mode). Tapping markers opens the relevant
// profile/details. Filters include radius, type (for tasks), and category.
//
// Invariants:
// • Reads role from UserProvider; no role toggle here.
// • Poster -> query /users where isHelper==true
// • Helper -> query /tasks where status=='open'
// • No Firestore rules changes; schema-tolerant, null-safe.
// • Uses only existing deps: cloud_firestore, firebase_auth, google_maps_flutter, provider.

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:servana/utils/verification_nav.dart';

// Role source of truth
import 'package:servana/providers/user_provider.dart';

// Destinations
import 'package:servana/screens/task_details_screen.dart';
import 'package:servana/screens/helper_public_profile_screen.dart';

class MapViewScreen extends StatefulWidget {
  const MapViewScreen({super.key});

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> {
  static const LatLng _fallbackCenter = LatLng(6.9271, 79.8612); // Colombo

  // Filters (session-local for this screen)
  double _radiusKm = 5;
  bool _onlyVerified = true;
  Set<String> _allowedCats = <String>{};
  String _typeFilter = 'all'; // 'all' | 'online' | 'physical'  (tasks only)
  String? _category;
  static const List<String> _quickCategories = [
    'Cleaning', 'Delivery', 'Repairs', 'Tutoring', 'Design', 'Writing'
  ];

  // Map/position
  LatLng _center = _fallbackCenter;
  bool _centerLoaded = false;
  GoogleMapController? _ctrl;

  // Streams
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _helpers$;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _tasks$;

  @override
  void initState() {
    _loadAllowed();

    super.initState();
    _loadCenterFromUserDoc();
    _helpers$ = FirebaseFirestore.instance
        .collection('users')
        .where('isHelper', isEqualTo: true)
        .limit(300)
        .snapshots();

    final col = FirebaseFirestore.instance.collection('tasks');
    try {
      _tasks$ = col
          .where('status', isEqualTo: 'open')
          .orderBy('createdAt', descending: true)
          .limit(300)
          .snapshots();
    } catch (_) {
      _tasks$ = col.where('status', isEqualTo: 'open').limit(300).snapshots();
    }
  }

  Future<void> _loadCenterFromUserDoc() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() {
          _center = _fallbackCenter;
          _centerLoaded = true;
        });
        return;
      }
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data();
      GeoPoint? gp;
      final presence = (data?['presence'] is Map<String, dynamic>)
          ? data!['presence'] as Map<String, dynamic>
          : null;
      if (presence?['currentLocation'] is GeoPoint) {
        gp = presence!['currentLocation'] as GeoPoint;
      } else if (data?['workLocation'] is GeoPoint) {
        gp = data?['workLocation'] as GeoPoint;
      } else if (data?['homeLocation'] is GeoPoint) {
        gp = data?['homeLocation'] as GeoPoint;
      }
      setState(() {
        _center = gp != null ? LatLng(gp.latitude, gp.longitude) : _fallbackCenter;
        _centerLoaded = true;
      });
    } catch (_) {
      setState(() {
        _center = _fallbackCenter;
        _centerLoaded = true;
      });
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final true = context.watch<UserProvider>().true;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final title = true ? 'Map — Tasks' : 'Map — Helpers';

    final camera = CameraPosition(target: _center, zoom: _zoomForRadius(_radiusKm));

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Filters',
            onPressed: _openFilters,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Data-layer
          Positioned.fill(
            child: _centerLoaded
                ? (true
                ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _tasks$,
              builder: (context, snap) {
                final markers = _buildTaskMarkers(snap.data);
                return _buildMap(camera, markers, isAndroid);
              },
            )
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _helpers$,
              builder: (context, snap) {
                final markers = _buildHelperMarkers(snap.data);
                return _buildMap(camera, markers, isAndroid);
              },
            ))
                : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),

          // Recenter + Radius bubble
          Positioned(
            right: 12,
            bottom: 12 + MediaQuery.of(context).padding.bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                _BubbleButton(
                  tooltip: 'Recenter',
                  icon: Icons.my_location_rounded,
                ),
                SizedBox(height: 8),
                _Bubble(
                  child: _RadiusText(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(CameraPosition camera, Set<Marker> markers, bool isAndroid) {
    return GoogleMap(
      initialCameraPosition: camera,
      mapType: MapType.normal,
      compassEnabled: false,
      zoomControlsEnabled: false,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      liteModeEnabled: false, // full interactivity in full-screen view
      markers: markers,
      circles: {
        Circle(
          circleId: const CircleId('radius'),
          center: _center,
          radius: _radiusKm * 1000,
          strokeWidth: 2,
          strokeColor: Theme.of(context).colorScheme.primary.withOpacity(0.35),
          fillColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        ),
      },
      onMapCreated: (c) => _ctrl = c,
      onCameraMove: (pos) => _center = pos.target,
      onCameraIdle: () => setState(() {}),
      onTap: (_) => _ctrl?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _center, zoom: _zoomForRadius(_radiusKm)),
        ),
      ),
    );
  }

  // ---------- Marker builders ----------
  Set<Marker> _buildHelperMarkers(QuerySnapshot<Map<String, dynamic>>? snap) {
    final markers = <Marker>{};
    if (snap == null) return markers;

    for (final doc in snap.docs) {
      final u = doc.data();
      if (u['isHelper'] != true) continue;

      GeoPoint? gp;
      final presence = (u['presence'] is Map<String, dynamic>) ? u['presence'] as Map<String, dynamic> : null;
      if (presence?['currentLocation'] is GeoPoint) {
        gp = presence!['currentLocation'] as GeoPoint;
      } else if (u['workLocation'] is GeoPoint) {
        gp = u['workLocation'] as GeoPoint;
      } else if (u['homeLocation'] is GeoPoint) {
        gp = u['homeLocation'] as GeoPoint;
      }
      if (gp == null) continue;

      // Category filter (best-effort)
      if (_category != null && _category!.trim().isNotEmpty) {
        final lc = _category!.trim().toLowerCase();
        final lists = [u['serviceCategories'], u['categories'], u['skills'], u['services']];
        final has = lists.any((v) => v is List && v.whereType<String>().any((e) => e.toLowerCase() == lc));
        if (!has) continue;
      }

      final pos = LatLng(gp.latitude, gp.longitude);
      final dist = _distanceKm(_center, pos);
      if (dist > _radiusKm + 0.01) continue;

      final name = (u['displayName'] as String?)?.trim().isNotEmpty == true ? (u['displayName'] as String).trim() : 'Helper';
      // poster verified-only
      if (!_isHelperMode && _onlyVerified) {
        if (_category != null && _category!.trim().isNotEmpty) {
          final lc = _category!.trim().toLowerCase();
          final allowed = (u['allowedCategoryIds'] is List) ? List<String>.from(u['allowedCategoryIds']).map((e)=>e.toLowerCase()).toSet() : const <String>{};
          if (!allowed.contains(lc)) continue;
        } else {
          // no category selected: just require the user to be generally verified
          final verifiedStatus = ((u['verificationStatus'] ?? '') as String).toLowerCase();
          if (!verifiedStatus.contains('verified')) continue;
        }
      }
      final live = presence?['isLive'] == true;

      markers.add(
        Marker(
          markerId: MarkerId('h_${doc.id}'),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(live ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: name,
            snippet: live ? 'Live · ${dist.toStringAsFixed(1)} km' : '${dist.toStringAsFixed(1)} km',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => HelperPublicProfileScreen(helperId: doc.id)),
              );
            },
          ),
        ),
      );
    }

    return markers;
  }

  Set<Marker> _buildTaskMarkers(QuerySnapshot<Map<String, dynamic>>? snap) {
    final markers = <Marker>{};
    if (snap == null) return markers;

    for (final doc in snap.docs) {
      final t = doc.data();
      if ((t['status'] as String?)?.toLowerCase() != 'open') continue;

      final GeoPoint? gp = t['location'] is GeoPoint ? t['location'] as GeoPoint : null;
      if (gp == null) continue;

      // Category filter
      if (_category != null && _category!.trim().isNotEmpty) {
        final lc = _category!.trim().toLowerCase();
        final tc = (t['category'] as String?)?.toLowerCase();
        if (tc != lc) continue;
      }

      // Type filter
      // Only-verified categories (helper mode)
      if (_onlyVerified) {
        final cat = (t['category'] as String?)?.toLowerCase() ?? '';
        if (cat.isNotEmpty && !_allowedCats.contains(cat)) continue;
      }
      // Type filter
      if (_typeFilter != 'all') {
        final type = (t['type'] as String?)?.toLowerCase();
        if (type != null && type != _typeFilter) continue;
      }

      final pos = LatLng(gp.latitude, gp.longitude);
      final dist = _distanceKm(_center, pos);
      if (dist > _radiusKm + 0.01) continue;

      final title = (t['title'] as String?)?.trim().isNotEmpty == true ? (t['title'] as String).trim() : 'Task';
      final num? amount = (t['finalAmount'] as num?) ?? (t['budget'] as num?);
      final snippet = [
        if (amount != null) _fmtLkr(amount),
        '${dist.toStringAsFixed(1)} km',
      ].join(' · ');

      markers.add(
        Marker(
          markerId: MarkerId('t_${doc.id}'),
            onTap: () async {
              final isHelperMode = context.read<UserProvider>().isHelperMode;
              if (isHelperMode) {
                final cat = (t['category'] ?? '').toString();
                if (cat.isNotEmpty) {
                  final ok = await VerificationNav.ensureEligibleOrRedirect(context, cat);
                  if (!ok) return;
                }
              }

          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: InfoWindow(
            title: title,
            snippet: snippet,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: doc.id))),
          ),
        ),
      );
    }

    return markers;
  }

  // ---------- Filters ----------
  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final true = context.read<UserProvider>().true;
        double tempRadius = _radiusKm;
        String tempType = _typeFilter;
        bool tempOnlyVerified = _onlyVerified;

        String? tempCategory = _category;

        return StatefulBuilder(
          builder: (context, setSheet) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                SwitchListTile(
                  title: const Text('Only verified categories'),
                  value: tempOnlyVerified,
                  onChanged: (v) => setSheet(() => tempOnlyVerified = v),
                ),
                Text('Filters', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),

                // Radius slider
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Distance', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: tempRadius,
                        min: 2,
                        max: 20,
                        divisions: 9,
                        label: '${tempRadius.toStringAsFixed(0)} km',
                        onChanged: (v) => setSheet(() => tempRadius = v),
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text('${tempRadius.toStringAsFixed(0)} km', textAlign: TextAlign.right),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Type (tasks only)
                if (true) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Type', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: tempType == 'all',
                        onSelected: (_) => setSheet(() => tempType = 'all'),
                      ),
                      ChoiceChip(
                        label: const Text('Online'),
                        selected: tempType == 'online',
                        onSelected: (_) => setSheet(() => tempType = 'online'),
                      ),
                      ChoiceChip(
                        label: const Text('Physical'),
                        selected: tempType == 'physical',
                        onSelected: (_) => setSheet(() => tempType = 'physical'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Category
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Category', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: tempCategory == null || tempCategory!.isEmpty,
                      onSelected: (_) => setSheet(() => tempCategory = null),
                    ),
                    for (final c in _quickCategories)
                      ChoiceChip(
                        label: Text(c),
                        selected: tempCategory == c,
                        onSelected: (_) => setSheet(() => tempCategory = c),
                      ),
                  ],
                ),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () { setState(() { _onlyVerified = tempOnlyVerified; });
                      setState(() {
                        _radiusKm = tempRadius;
                        _typeFilter = tempType;
                        _category = tempCategory;
                      });
                      Navigator.pop(context);
                      _ctrl?.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(target: _center, zoom: _zoomForRadius(_radiusKm)),
                        ),
                      );
                    },
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- Utils ----------
  double _zoomForRadius(double km) {
    if (km <= 2) return 14;
    if (km <= 5) return 13;
    if (km <= 10) return 12;
    if (km <= 15) return 11.5;
    return 11;
  }

  double _distanceKm(LatLng a, LatLng b) {
    const R = 6371.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return R * c;
  }

  double _deg2rad(double d) => d * (math.pi / 180.0);

  String _fmtLkr(num n) {
    final negative = n < 0;
    final abs = n.abs();
    final isWhole = abs % 1 == 0;
    final raw = isWhole ? abs.toStringAsFixed(0) : abs.toStringAsFixed(2);
    final parts = raw.split('.');
    String whole = parts[0];
    final reg = RegExp(r'\B(?=(\d{3})+(?!\d))');
    whole = whole.replaceAllMapped(reg, (m) => ',');
    final prefix = negative ? '−' : '';
    return parts.length == 1 ? 'LKR $prefix$whole' : 'LKR $prefix$whole.${parts[1]}';
  }
}

// ---------- Small UI Bubbles ----------
class _BubbleButton extends StatelessWidget {
  const _BubbleButton({required this.icon, this.tooltip});
  final IconData icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = _Bubble(child: Icon(icon, size: 18));
    return tooltip == null
        ? InkWell(onTap: () {}, borderRadius: BorderRadius.circular(12), child: child)
        : Tooltip(message: tooltip!, child: InkWell(onTap: () {}, borderRadius: BorderRadius.circular(12), child: child));
  }
}

class _RadiusText extends StatelessWidget {
  const _RadiusText();

  @override
  Widget build(BuildContext context) {
    // Just a caption; value is shown in filter sheet & circle radius
    return Text(
      'Radius',
      style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Future<void> _loadAllowed() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final m = snap.data() ?? const <String, dynamic>{};
      final list = (m['allowedCategoryIds'] is List) ? List<String>.from(m['allowedCategoryIds']) : const <String>[];
      setState(() => _allowedCats = list.map((e) => e.toLowerCase()).toSet());
    } catch (_) {}
  }
}
