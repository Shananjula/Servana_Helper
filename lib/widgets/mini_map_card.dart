// lib/widgets/mini_map_card.dart
//
// MiniMapCard — crash-proof map for Helpers
// ----------------------------------------
// • Shows a map only when the Helper has at least one PHYSICAL category verified.
// • If Helper is ONLINE-only, shows a friendly “no map needed” card.
// • If Helper has BOTH, shows a small toggle (Physical ↔ Online); map appears only on Physical.
// • Task pins are queried rule-friendly:
//      where('categoryId', whereIn: allowedPhysicalCats.take(10))
//      .where('status', whereIn: ['open','listed','negotiating','negotiation'])
//      .where('type', isEqualTo: 'physical')
// • Any task without a GeoPoint location is safely skipped (no null-deref).
//
// Deps: cloud_firestore, firebase_auth, google_maps_flutter, flutter/material

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum TaskMode { physical, online }

class MiniMapCard extends StatefulWidget {
  const MiniMapCard({
    super.key,
    this.initialMode,
    this.height = 220,
    // --- Back-compat: accept old params so callers compiling with `mode:` and
    //     `categoryId:` won’t error out. They’re ignored at runtime.
    @Deprecated('Use initialMode: TaskMode.physical/online') this.mode,
    @Deprecated('MiniMapCard determines categories automatically') this.categoryId,
  });

  final TaskMode? initialMode;
  final double height;

  // deprecated shim parameters (ignored; kept only to avoid caller compile errors)
  final String? mode;
  final String? categoryId;

  @override
  State<MiniMapCard> createState() => _MiniMapCardState();
}

class _MiniMapCardState extends State<MiniMapCard> {
  TaskMode? _selected;
  GoogleMapController? _map;

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _InfoCard(
        icon: Icons.lock_outline,
        title: 'Sign in required',
        subtitle: 'Log in to see nearby tasks.',
        height: widget.height,
      );
    }

    final userStream =
    FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userStream,
      builder: (context, userSnap) {
        if (userSnap.connectionState == ConnectionState.waiting) {
          return _Skeleton(height: widget.height);
        }
        if (!userSnap.hasData || !userSnap.data!.exists) {
          return _InfoCard(
            icon: Icons.person_search_outlined,
            title: 'Complete your profile',
            subtitle: 'We’ll show tasks after you’re set up.',
            height: widget.height,
          );
        }

        final data = userSnap.data!.data() ?? {};
        final allowed = (data['allowedCategoryIds'] as List?)?.cast<String>() ?? const <String>[];

        if (allowed.isEmpty) {
          return _InfoCard(
            icon: Icons.verified_user_outlined,
            title: 'Get verified to view tasks',
            subtitle: 'Verify at least one category to unlock the map.',
            height: widget.height,
            cta: ElevatedButton(
              onPressed: () {
                // TODO: push Verification Center if available
              },
              child: const Text('Open Verification Center'),
            ),
          );
        }

        final catsRef = FirebaseFirestore.instance.collection('categories');
        final chunk = allowed.take(10).toList(); // whereIn <= 10
        final catsQuery = catsRef.where(FieldPath.documentId, whereIn: chunk);

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: catsQuery.snapshots(),
          builder: (context, catsSnap) {
            if (catsSnap.connectionState == ConnectionState.waiting) {
              return _Skeleton(height: widget.height);
            }
            if (!catsSnap.hasData) {
              return _InfoCard(
                icon: Icons.category_outlined,
                title: 'Loading categories…',
                subtitle: 'Fetching your access.',
                height: widget.height,
              );
            }

            final docs = catsSnap.data!.docs;
            final physicalCatIds = <String>[];
            final onlineCatIds = <String>[];
            for (final d in docs) {
              final m = (d.data()['mode'] ?? 'online').toString().toLowerCase();

              if (m == 'physical') {
                physicalCatIds.add(d.id);
              } else if (m == 'online') {
                onlineCatIds.add(d.id);
              }
            }

            final hasPhysical = physicalCatIds.isNotEmpty;
            final hasOnline = onlineCatIds.isNotEmpty;

            _selected ??= widget.initialMode ??
                (hasPhysical
                    ? TaskMode.physical
                    : hasOnline
                    ? TaskMode.online
                    : null);

            if (_selected == null) {
              return _InfoCard(
                icon: Icons.help_outline,
                title: 'No compatible categories',
                subtitle:
                'Your categories don’t specify online/physical yet. Ask an admin to set a mode.',
                height: widget.height,
              );
            }

            final header = (hasPhysical && hasOnline)
                ? Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: _ModeToggle(
                selected: _selected!,
                onChanged: (m) => setState(() => _selected = m),
              ),
            )
                : const SizedBox(height: 8);

            if (_selected == TaskMode.online) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  _InfoCard(
                    icon: Icons.wifi_tethering,
                    title: 'Online tasks don’t use a map',
                    subtitle:
                    'Switch to “Physical” to view a map of nearby tasks.',
                    height: widget.height - 8,
                  ),
                ],
              );
            }

            if (_selected == TaskMode.physical && !hasPhysical) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  _InfoCard(
                    icon: Icons.map_outlined,
                    title: 'No physical categories verified',
                    subtitle:
                    'Verify at least one physical category to unlock the map.',
                    height: widget.height - 8,
                  ),
                ],
              );
            }

            final q = FirebaseFirestore.instance
                .collection('tasks')
                .where('categoryId', whereIn: physicalCatIds.take(10).toList())
                .where('status',
                whereIn: const ['open', 'listed', 'negotiating', 'negotiation'])
                .where('type', isEqualTo: 'physical')
                .limit(120);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                SizedBox(
                  height: widget.height - 8,
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: q.snapshots(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return _Skeleton(height: widget.height - 8);
                      }
                      if (!snap.hasData || snap.data!.docs.isEmpty) {
                        return _InfoCard(
                          icon: Icons.place_outlined,
                          title: 'No nearby physical tasks (yet)',
                          subtitle: 'New tasks appear here in real-time.',
                          height: widget.height - 8,
                        );
                      }

                      final markers = <Marker>{};
                      for (final d in snap.data!.docs) {
                        final map = d.data();
                        final gp = map['location'];
                        if (gp is! GeoPoint) continue;
                        final latLng = LatLng(gp.latitude, gp.longitude);

                        markers.add(
                          Marker(
                            markerId: MarkerId(d.id),
                            position: latLng,
                            infoWindow: InfoWindow(
                              title: (map['title'] ?? 'Task').toString(),
                              snippet: (map['price'] != null)
                                  ? 'LKR ${(map['price']).toString()}'
                                  : null,
                            ),
                          ),
                        );
                      }

                      if (markers.isEmpty) {
                        return _InfoCard(
                          icon: Icons.my_location_outlined,
                          title: 'No mappable tasks',
                          subtitle:
                          'Tasks are physical but do not include a precise location yet.',
                          height: widget.height - 8,
                        );
                      }

                      final first = markers.first.position;

                      return ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: first,
                            zoom: 12,
                          ),
                          onMapCreated: (c) => _map = c,
                          markers: markers,
                          myLocationEnabled: false,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          compassEnabled: true,
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// --- UI helpers --------------------------------------------------------------

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.selected, required this.onChanged});
  final TaskMode selected;
  final ValueChanged<TaskMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TaskMode>(
      segments: const [
        ButtonSegment(value: TaskMode.physical, label: Text('Physical')),
        ButtonSegment(value: TaskMode.online, label: Text('Online')),
      ],
      selected: <TaskMode>{selected},
      onSelectionChanged: (s) {
        if (s.isNotEmpty) onChanged(s.first);
      },
      showSelectedIcon: false,
      multiSelectionEnabled: false,
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.cta,
    required this.height,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? cta;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (cta != null) ...[
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerLeft, child: cta!),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    // FIX: EdgeBoxConstraints → EdgeInsets
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      ),
    );
  }
}
