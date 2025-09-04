// lib/screens/helper_public_profile_screen.dart
//
// Public profile for a Helper (poster-facing)
// • Navigated with: HelperPublicProfileScreen(helperId: '...')
// • Reads user doc from Firestore and renders safely (schema-tolerant)
// • Shows: name, rating, live badge, city, bio, registered categories, services
// • Actions: “Hire this helper” → opens PostTaskScreen (no tight coupling)
// • No role switch UI here.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:servana/screens/post_task_screen.dart';

class HelperPublicProfileScreen extends StatelessWidget {
  const HelperPublicProfileScreen({super.key, required this.helperId});

  final String helperId;

  // Flip this to true if your services use `helperId` instead of `ownerId`
  static const bool useHelperIdFallback = true;

  @override
  Widget build(BuildContext context) {
    final userRef = FirebaseFirestore.instance.collection('users').doc(helperId);

    return Scaffold(
      appBar: AppBar(title: const Text('Helper profile')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const _EmptyState(
              icon: Icons.person_off_outlined,
              title: 'Helper not found',
              message: 'This profile may have been removed or is unavailable.',
            );
          }

          final m = snap.data!.data() ?? <String, dynamic>{};
          final name = (m['displayName'] ?? m['name'] ?? 'Helper').toString();
          final city = (m['city'] ?? m['workCity'] ?? '').toString();
          final bio = (m['bio'] ?? '').toString();
          final rating =
          (m['rating'] is num) ? (m['rating'] as num).toDouble() : null;
          final live = ((m['presence']?['isLive'] ?? m['isLive']) == true);
          final cats = ((m['registeredCategories'] as List?)?.cast<String>() ??
              const <String>[])
              .toList();
          final allowedIds = (m['allowedCategoryIds'] as List?)?.cast<String>() ??
              const <String>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _HeaderCard(
                name: name,
                city: city,
                rating: rating,
                live: live,
              ),

              if (bio.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Text(bio),
                  ),
                ),
              ],

              if (cats.isNotEmpty) ...[
                const SizedBox(height: 8),
                const _SectionHeader('Categories'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in cats)
                      Chip(
                        label: Text(c),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],

              if (allowedIds.isNotEmpty) ...[
                const SizedBox(height: 16),
                _VerifiedCategories(allowedIds: allowedIds),
              ],

              const SizedBox(height: 16),
              const _SectionHeader('Services'),
              _ServicesList(helperId: helperId),

              const SizedBox(height: 24),
              // Primary poster action
              FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PostTaskScreen()),
                  );
                },
                // FIX: use a valid Material icon
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Hire this helper (post a task)'),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Services list (schema tolerant; prefers ownerId but can fall back to helperId)
// ───────────────────────────────────────────────────────────────────────────────

class _ServicesList extends StatelessWidget {
  const _ServicesList({required this.helperId});
  final String helperId;

  @override
  Widget build(BuildContext context) {
    final base = FirebaseFirestore.instance.collection('services');
    // Prefer ownerId; optionally also show helperId matches if flag enabled.
    final qOwner = base.where('ownerId', isEqualTo: helperId).limit(50);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: qOwner.snapshots(),
      builder: (context, ownerSnap) {
        final ownerDocs = ownerSnap.data?.docs ?? const [];

        if (_hasDocs(ownerDocs)) {
          return _ServiceCards(docs: ownerDocs);
        }

        // Fallback to helperId if no ownerId matches and fallback allowed
        if (!HelperPublicProfileScreen.useHelperIdFallback) {
          return const _EmptyBox(
            icon: Icons.build_outlined,
            text: 'No services listed yet.',
          );
        }

        final qHelper = base.where('helperId', isEqualTo: helperId).limit(50);
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: qHelper.snapshots(),
          builder: (context, helperSnap) {
            final helperDocs = helperSnap.data?.docs ?? const [];
            if (_hasDocs(helperDocs)) {
              return _ServiceCards(docs: helperDocs);
            }
            if (ownerSnap.connectionState == ConnectionState.waiting ||
                helperSnap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            return const _EmptyBox(
              icon: Icons.build_outlined,
              text: 'No services listed yet.',
            );
          },
        );
      },
    );
  }

  bool _hasDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> d) =>
      d.isNotEmpty;
}

class _ServiceCards extends StatelessWidget {
  const _ServiceCards({required this.docs});
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final d in docs) _ServiceTile(service: d.data(), id: d.id),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service, required this.id});
  final Map<String, dynamic> service;
  final String id;

  @override
  Widget build(BuildContext context) {
    final s = service;
    final title = (s['title'] ?? s['name'] ?? 'Service').toString();
    final category = (s['categoryLabel'] ?? s['category'] ?? '').toString();
    final unit = (s['unit'] ?? '').toString();
    final price = s['price'];
    final active = (s['active'] == true);

    String trailing = active ? '' : 'Inactive';
    if (price is num) trailing = 'LKR ${price.toStringAsFixed(0)}${unit.isNotEmpty ? ' / $unit' : ''}';
    if (price is String && price.trim().isNotEmpty) trailing = price;

    return Card(
      child: ListTile(
        leading: const Icon(Icons.home_repair_service_outlined),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [category, unit].where((s) => s.isNotEmpty).join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          trailing.isEmpty ? '—' : trailing,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Header & small widgets
// ───────────────────────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.name,
    required this.city,
    required this.rating,
    required this.live,
  });

  final String name;
  final String city;
  final double? rating;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final badgeBg = live
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    city.isEmpty ? '—' : city,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              live ? Icons.radio_button_checked : Icons.radio_button_off,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(live ? 'Live' : 'Offline'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (rating != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rate_rounded, size: 18),
                            const SizedBox(width: 4),
                            Text(rating!.toStringAsFixed(1)),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _VerifiedCategories extends StatelessWidget {
  const _VerifiedCategories({required this.allowedIds});
  final List<String> allowedIds;

  @override
  Widget build(BuildContext context) {
    if (allowedIds.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('categories').get(),
      builder: (context, csnap) {
        // Helper to map category ID to its label. Falls back to a formatted ID.
        final labelFor = (String id) {
          if (!csnap.hasData || csnap.data!.docs.isEmpty) {
            return id.replaceAll('_', ' ');
          }
          final m = {
            for (final d in csnap.data!.docs)
              d.id: (d.data()['label'] ?? d.id).toString()
          };
          return m[id] ?? id.replaceAll('_', ' ');
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader('Verified For'),
            const SizedBox(height: 4), // Small gap between header and chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allowedIds
                  .take(8)
                  .map((id) => Chip(
                label: Text(labelFor(id)),
                visualDensity: VisualDensity.compact,
                backgroundColor: Colors.green.withOpacity(0.12),
                side: BorderSide(color: Colors.green.withOpacity(0.2)),
              ))
                  .toList(),
            ),
          ],
        );
      },
    );
  }
}
