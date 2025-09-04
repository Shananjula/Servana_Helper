// lib/widgets/live_location_map_widget.dart
//
// Shared Google Map widget for HELPERS and TASKS.
// - Modes: MapMode.helpers (presence docs) | MapMode.tasks (task docs)
// - Accepts a Firestore stream and renders markers
// - Optional client-side distance filter from a given center (km)
// - Optional lightweight clustering (grid-based) for performance
// - Optional "Search this area" button + viewport callback
// - Category-colored pins for tasks; green pins for helpers
//
// Usage examples:
//
// Live helpers near me:
//   LiveLocationMapWidget(
//     stream: FirebaseFirestore.instance
//       .collection('presence')
//       .where('isLive', isEqualTo: true)
//       .snapshots(),
//     mode: MapMode.helpers,
//     showMyLocation: true,
//     enableClustering: true,
//   )
//
// Tasks in my categories within 4km of my location:
//   LiveLocationMapWidget(
//     stream: FirebaseFirestore.instance
//       .collection('tasks')
//       .where('status', isEqualTo: 'listed')
//       .limit(250)
//       .snapshots(),
//     mode: MapMode.tasks,
//     centerLat: userProv.lat,
//     centerLng: userProv.lng,
//     clientDistanceFilterKm: 4,
//     onMarkerTap: (taskId, data) {
//       Navigator.push(context, MaterialPageRoute(
//         builder: (_) => TaskDetailsScreen(taskId: taskId)));
//     },
//   )

import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'package:servana/providers/user_provider.dart';

enum MapMode { helpers, tasks }

class LiveLocationMapWidget extends StatefulWidget {
  const LiveLocationMapWidget({
    super.key,
    required this.stream,
    required this.mode,
    this.centerLat,
    this.centerLng,
    this.clientDistanceFilterKm,
    this.enableClustering = true,
    this.maxMarkers = 300,
    this.showMyLocation = true,
    this.showSearchThisArea = false,
    this.onViewportChanged,
    this.onSearchThisArea,
    this.onMarkerTap,
  });

  /// Firestore stream: each document should have `lat` & `lng` as numbers.
  final Stream<QuerySnapshot> stream;

  /// Rendering mode: helpers (presence) or tasks (task docs)
  final MapMode mode;

  /// Optional center for client-side distance filtering.
  final double? centerLat;
  final double? centerLng;

  /// If provided, items farther than this distance (km) are filtered out.
  final double? clientDistanceFilterKm;

  /// Lightweight grid clustering at lower zooms.
  final bool enableClustering;

  /// Hard cap on marker count after clustering.
  final int maxMarkers;

  /// Show my location dot & button.
  final bool showMyLocation;

  /// Show a floating “Search this area” chip (only if [onSearchThisArea] set).
  final bool showSearchThisArea;

  /// Called when the camera goes idle after move/zoom.
  final ValueChanged<LatLngBounds>? onViewportChanged;

  /// Called when user taps the “Search this area” chip.
  final ValueChanged<LatLngBounds>? onSearchThisArea;

  /// Called when a marker is tapped: (document id, raw data).
  final void Function(String id, Map<String, dynamic> data)? onMarkerTap;

  @override
  State<LiveLocationMapWidget> createState() => _LiveLocationMapWidgetState();
}

class _LiveLocationMapWidgetState extends State<LiveLocationMapWidget> {
  GoogleMapController? _controller;
  StreamSubscription<QuerySnapshot>? _sub;

  // Render state
  final Set<Marker> _markers = <Marker>{};
  final Set<Circle> _circles = <Circle>{};

  // Camera state
  LatLng _initial = const LatLng(6.9271, 79.8612); // Colombo fallback
  double _zoom = 12;
  LatLngBounds? _lastBounds;

  // Snapshot cache
  List<_MapItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _primeInitialCenter();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant LiveLocationMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream ||
        oldWidget.mode != widget.mode ||
        oldWidget.clientDistanceFilterKm != widget.clientDistanceFilterKm ||
        oldWidget.centerLat != widget.centerLat ||
        oldWidget.centerLng != widget.centerLng ||
        oldWidget.enableClustering != widget.enableClustering) {
      _subscribe();
    } else {
      _render();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _primeInitialCenter() {
    // Prefer explicit center
    if (widget.centerLat != null && widget.centerLng != null) {
      _initial = LatLng(widget.centerLat!, widget.centerLng!);
      return;
    }
    // Fallback to UserProvider location
    try {
      final user = context.read<UserProvider>();
      if (user.lat != null && user.lng != null) {
        _initial = LatLng(user.lat!, user.lng!);
      }
    } catch (_) {}
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = widget.stream.listen((snapshot) {
      final centerLat = widget.centerLat ?? context.read<UserProvider>().lat;
      final centerLng = widget.centerLng ?? context.read<UserProvider>().lng;
      final filterKm = widget.clientDistanceFilterKm;

      final next = <_MapItem>[];
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        final double? lat = (data['lat'] as num?)?.toDouble();
        final double? lng = (data['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        // Optional distance filter
        if (centerLat != null && centerLng != null && filterKm != null) {
          final dist = _haversineKm(centerLat, centerLng, lat, lng);
          if (dist > filterKm) continue;
        }

        next.add(_MapItem(
          id: doc.id,
          data: data,
          position: LatLng(lat, lng),
          mode: widget.mode,
        ));
      }

      _items = next;
      _render();
    });
  }

  void _render() {
    if (!mounted) return;
    final items = _items;

    if (items.isEmpty) {
      setState(() {
        _markers.clear();
        _circles.clear();
      });
      return;
    }

    final doCluster = widget.enableClustering && _zoom <= 13;

    final clustersOrItems = doCluster
        ? _cluster(items, _zoom)
        : items.map((e) => _ClusterOrItem.item(e)).toList();

    final newMarkers = <Marker>{};
    final newCircles = <Circle>{};

    for (final c in clustersOrItems) {
      if (newMarkers.length >= widget.maxMarkers) break;

      if (c.isCluster) {
        final pos = c.clusterCenter!;
        final count = c.count;
        newMarkers.add(
          Marker(
            markerId: MarkerId('cluster_${pos.latitude}_${pos.longitude}_$count'),
            position: pos,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            infoWindow: InfoWindow(title: '$count nearby'),
          ),
        );
        continue;
      }

      final item = c.item!;
      final hue = _markerHueFor(item);
      final title = _markerTitleFor(item);
      final snippet = _markerSnippetFor(item);

      newMarkers.add(
        Marker(
          markerId: MarkerId(item.id),
          position: item.position,
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title: title,
            snippet: snippet,
            onTap: () {
              if (widget.onMarkerTap != null) {
                widget.onMarkerTap!(item.id, item.data);
              }
            },
          ),
          onTap: () {
            // Helpers: add a subtle live ring on tap for flair.
            if (item.mode == MapMode.helpers) {
              newCircles.add(
                Circle(
                  circleId: CircleId('ring_${item.id}'),
                  center: item.position,
                  radius: 40, // meters
                  strokeWidth: 1,
                  strokeColor: Colors.green.withOpacity(0.6),
                  fillColor: Colors.green.withOpacity(0.12),
                ),
              );
              setState(() {
                _circles
                  ..clear()
                  ..addAll(newCircles);
              });
            }
          },
        ),
      );
    }

    setState(() {
      _markers
        ..clear()
        ..addAll(newMarkers);
      _circles
        ..clear()
        ..addAll(newCircles);
    });
  }

  @override
  Widget build(BuildContext context) {
    final camera = CameraPosition(target: _initial, zoom: _zoom);

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: camera,
          myLocationEnabled: widget.showMyLocation,
          myLocationButtonEnabled: widget.showMyLocation,
          markers: _markers,
          circles: _circles,
          onMapCreated: (c) => _controller = c,
          onCameraMove: (pos) => _zoom = pos.zoom,
          onCameraIdle: () async {
            if (_controller != null) {
              final bounds = await _controller!.getVisibleRegion();
              _lastBounds = bounds;
              widget.onViewportChanged?.call(bounds);
              _render(); // re-evaluate clustering after zoom idle
            }
          },
        ),

        // Optional “Search this area” chip
        if (widget.showSearchThisArea && widget.onSearchThisArea != null)
          Positioned(
            top: 12,
            right: 12,
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  if (_lastBounds != null) widget.onSearchThisArea!.call(_lastBounds!);
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search),
                      SizedBox(width: 8),
                      Text('Search this area'),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---------------- Marker helpers ----------------

  double _markerHueFor(_MapItem item) {
    if (item.mode == MapMode.helpers) {
      // Helpers: green
      return BitmapDescriptor.hueGreen;
    }
    // Tasks: color by category
    final cat = (item.data['category'] ?? '') as String;
    switch (cat) {
      case 'cleaning':
        return BitmapDescriptor.hueBlue;
      case 'delivery':
        return BitmapDescriptor.hueGreen;
      case 'repairs':
        return BitmapDescriptor.hueOrange;
      case 'tutoring':
        return BitmapDescriptor.hueViolet;
      case 'design':
        return BitmapDescriptor.hueMagenta;
      case 'writing':
        return BitmapDescriptor.hueCyan;
      default:
        return BitmapDescriptor.hueRose;
    }
  }

  String _markerTitleFor(_MapItem item) {
    if (item.mode == MapMode.helpers) return 'Helper';
    final title = item.data['title'];
    if (title is String && title.isNotEmpty) return title;
    final cat = (item.data['category'] ?? 'Task') as String;
    return cat.isNotEmpty ? '${cat[0].toUpperCase()}${cat.substring(1)}' : 'Task';
  }

  String? _markerSnippetFor(_MapItem item) {
    if (item.mode == MapMode.helpers) return null;
    final price = item.data['price'];
    final cat = item.data['category'];
    if (price != null) return 'LKR $price · $cat';
    if (cat != null) return '$cat';
    return null;
  }

  // ---------------- Clustering ----------------

  /// Lightweight grid clustering based on zoom level.
  List<_ClusterOrItem> _cluster(List<_MapItem> items, double zoom) {
    if (zoom >= 14) return items.map((e) => _ClusterOrItem.item(e)).toList();

    final grid = _gridSizeForZoom(zoom); // degrees
    final buckets = <String, List<_MapItem>>{};

    for (final it in items) {
      final keyLat = (it.position.latitude / grid).floor();
      final keyLng = (it.position.longitude / grid).floor();
      final key = '$keyLat:$keyLng';
      (buckets[key] ??= []).add(it);
    }

    final out = <_ClusterOrItem>[];
    buckets.forEach((_, list) {
      if (list.length == 1) {
        out.add(_ClusterOrItem.item(list.first));
      } else {
        double sLat = 0, sLng = 0;
        for (final it in list) {
          sLat += it.position.latitude;
          sLng += it.position.longitude;
        }
        final c = LatLng(sLat / list.length, sLng / list.length);
        out.add(_ClusterOrItem.cluster(c, list.length));
      }
    });

    if (out.length > widget.maxMarkers) {
      out.sort((a, b) => (b.countOrOne).compareTo(a.countOrOne));
      return out.take(widget.maxMarkers).toList();
    }
    return out;
  }

  double _gridSizeForZoom(double zoom) {
    // Rough heuristic
    if (zoom <= 10) return 0.05;
    if (zoom <= 11) return 0.03;
    if (zoom <= 12) return 0.02;
    return 0.012;
  }
}

// ---------------- Internal models ----------------

class _MapItem {
  final String id;
  final Map<String, dynamic> data;
  final LatLng position;
  final MapMode mode;

  _MapItem({
    required this.id,
    required this.data,
    required this.position,
    required this.mode,
  });
}

class _ClusterOrItem {
  final LatLng? clusterCenter;
  final int? count;
  final _MapItem? item;

  bool get isCluster => clusterCenter != null;
  int get countOrOne => count ?? 1;

  _ClusterOrItem.cluster(this.clusterCenter, this.count) : item = null;
  _ClusterOrItem.item(this.item)
      : clusterCenter = null,
        count = null;
}

// ---------------- Utils ----------------

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLon = _deg2rad(lon2 - lon1);
  final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
      math.cos(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) * (math.sin(dLon / 2) * math.sin(dLon / 2));
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return R * c;
}

double _deg2rad(double deg) => deg * (math.pi / 180.0);
