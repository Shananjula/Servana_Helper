// lib/screens/leaderboard_screen.dart
//
// Leaderboard (Helpers-first; Posters optional)
// • Tabs: Helpers | Posters (helpers tab is primary)
// • Filters: Category (optional), Period (All-time / This month)
// • Source of truth (in order):
//     1) leaderboard/{autoId} docs (role, userId, category, period, score, jobs, rating, name, photoURL)
//     2) Fallback to users/ collection (averageRating, ratingCount) when no leaderboard docs
// • Ranks top 100 by score (or ratingCount*avgRating in fallback)
// • Tapping an item:
//     - Helper → opens public profile
//     - Poster → (optional) opens poster profile if you have one; else disabled
//
// Firestore shapes (guarded):
//   leaderboard/{id} {
//     role: 'helper' | 'poster',
//     userId: string,
//     name?: string,
//     photoURL?: string,
//     category?: string,       // normalized, e.g. 'cleaning'
//     period: 'all_time'|'monthly',
//     score: number,           // precomputed, higher is better
//     jobs?: number,           // completions in period
//     rating?: number,         // average rating in period or overall
//     updatedAt: Timestamp
//   }
//
//   users/{uid} fallback (helpers):
//     displayName, photoURL, averageRating, ratingCount, registeredCategories[]
//
// Notes:
// • If you plan to compute leaderboards server-side, keep this UI as-is.
// • For fallback, we filter helpers verified (optional); here we just show everyone.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:servana/screens/helper_public_profile_screen.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  String _period = 'all_time'; // 'all_time' | 'monthly'
  String? _category;           // normalized id or null
  final List<(String, String)> _cats = const [
    ('All', ''),
    ('Cleaning', 'cleaning'),
    ('Delivery', 'delivery'),
    ('Repairs', 'repairs'),
    ('Tutoring', 'tutoring'),
    ('Design', 'design'),
    ('Writing', 'writing'),
  ];

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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.emoji_events_outlined), text: 'Helpers'),
            Tab(icon: Icon(Icons.groups_outlined), text: 'Posters'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Filters
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                // Category (helpers tab only; disabled for posters)
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: _cats
                        .map((c) => DropdownMenuItem<String>(
                      value: c.$2.isEmpty ? null : c.$2,
                      child: Text(c.$1),
                    ))
                        .toList(),
                    onChanged: (v) => setState(() => _category = v),
                  ),
                ),
                const SizedBox(width: 12),
                // Period
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _period,
                    decoration: const InputDecoration(labelText: 'Period'),
                    items: const [
                      DropdownMenuItem(value: 'all_time', child: Text('All-time')),
                      DropdownMenuItem(value: 'monthly', child: Text('This month')),
                    ],
                    onChanged: (v) => setState(() => _period = v ?? 'all_time'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _HelpersBoard(period: _period, category: _category),
                _PostersBoard(period: _period),
              ],
            ),
          ),
        ],
      ),

      // Tiny legend
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Text(
            'Scores are based on jobs completed, ratings, and recency.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// ==================== HELPERS BOARD ====================

class _HelpersBoard extends StatelessWidget {
  const _HelpersBoard({required this.period, required this.category});
  final String period;     // 'all_time' | 'monthly'
  final String? category;  // normalized or null

  @override
  Widget build(BuildContext context) {
    // Preferred: leaderboard collection
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('leaderboard')
        .where('role', isEqualTo: 'helper')
        .where('period', isEqualTo: period)
        .orderBy('score', descending: true)
        .limit(100);

    if (category != null && category!.isNotEmpty) {
      q = q.where('category', isEqualTo: category);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          // Fallback: compute from users collection (rough)
          return _HelpersUsersFallback(category: category);
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final m = docs[i].data();
            final uid = (m['userId'] ?? '') as String;
            return _RankTile(
              rank: i + 1,
              uid: uid,
              name: (m['name'] ?? 'Helper') as String,
              photoURL: (m['photoURL'] ?? '') as String,
              trailing: _TrailMetrics(
                rating: (m['rating'] is num) ? (m['rating'] as num).toDouble() : null,
                jobs: (m['jobs'] is num) ? (m['jobs'] as num).toInt() : null,
                score: (m['score'] is num) ? (m['score'] as num).toDouble() : null,
              ),
              onTap: () {
                if (uid.isNotEmpty) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => HelperPublicProfileScreen(helperId: uid)));
                }
              },
            );
          },
        );
      },
    );
  }
}

class _HelpersUsersFallback extends StatelessWidget {
  const _HelpersUsersFallback({required this.category});
  final String? category;

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'helper')
        .limit(300);

    // Filter by registeredCategories client-side later if needed

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        var docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        // Client-side filter for category
        if (category != null && category!.isNotEmpty) {
          docs = docs.where((d) {
            final arr = (d.data()['registeredCategories'] as List?)?.cast<String>() ?? const <String>[];
            return arr.contains(category);
          }).toList();
        }

        // Compute score: ratingCount * averageRating (simple)
        final items = docs.map((d) {
          final m = d.data();
          final uid = d.id;
          final name = (m['displayName'] ?? 'Helper') as String;
          final photo = (m['photoURL'] ?? '') as String;
          final rating = (m['averageRating'] is num) ? (m['averageRating'] as num).toDouble() : 0.0;
          final count = (m['ratingCount'] is num) ? (m['ratingCount'] as num).toInt() : 0;
          final score = rating * count;
          return (uid, name, photo, rating, count, score);
        }).toList();

        items.sort((a, b) => b.$6.compareTo(a.$6));
        final top = items.take(100).toList();

        if (top.isEmpty) {
          return const Center(child: Text('No helpers to show yet.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          itemCount: top.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final it = top[i];
            return _RankTile(
              rank: i + 1,
              uid: it.$1,
              name: it.$2,
              photoURL: it.$3,
              trailing: _TrailMetrics(rating: it.$4, jobs: it.$5, score: it.$6),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => HelperPublicProfileScreen(helperId: it.$1)));
              },
            );
          },
        );
      },
    );
  }
}

// ==================== POSTERS BOARD (optional) ====================

class _PostersBoard extends StatelessWidget {
  const _PostersBoard({required this.period});
  final String period;

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('leaderboard')
        .where('role', isEqualTo: 'poster')
        .where('period', isEqualTo: period)
        .orderBy('score', descending: true)
        .limit(100);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Center(child: Text('No poster leaderboard yet.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final m = docs[i].data();
            return _RankTile(
              rank: i + 1,
              uid: (m['userId'] ?? '') as String,
              name: (m['name'] ?? 'Poster') as String,
              photoURL: (m['photoURL'] ?? '') as String,
              trailing: _TrailMetrics(
                rating: (m['rating'] is num) ? (m['rating'] as num).toDouble() : null,
                jobs: (m['jobs'] is num) ? (m['jobs'] as num).toInt() : null,
                score: (m['score'] is num) ? (m['score'] as num).toDouble() : null,
              ),
              onTap: () {
                // If you have a poster public profile screen, route here.
              },
            );
          },
        );
      },
    );
  }
}

// ==================== Shared UI bits ====================

class _RankTile extends StatelessWidget {
  const _RankTile({
    required this.rank,
    required this.uid,
    required this.name,
    required this.photoURL,
    required this.trailing,
    required this.onTap,
  });

  final int rank;
  final String uid;
  final String name;
  final String photoURL;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final medal = switch (rank) {
      1 => (Icons.emoji_events, Colors.amber),
      2 => (Icons.emoji_events, Colors.grey),
      3 => (Icons.emoji_events, Colors.brown),
      _ => (Icons.circle_outlined, cs.onSurfaceVariant),
    };
    return Card(
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              backgroundImage: photoURL.isNotEmpty ? NetworkImage(photoURL) : null,
              child: photoURL.isEmpty ? const Icon(Icons.person) : null,
            ),
            Positioned(
              right: -6,
              bottom: -6,
              child: Icon(medal.$1, size: 18, color: medal.$2),
            ),
          ],
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(uid.isNotEmpty ? 'ID: ${uid.substring(0, 6)}…' : ''),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

class _TrailMetrics extends StatelessWidget {
  const _TrailMetrics({this.rating, this.jobs, this.score});
  final double? rating;
  final int? jobs;
  final double? score;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (rating != null) {
      rows.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 14, color: Colors.amber),
          const SizedBox(width: 4),
          Text(rating!.toStringAsFixed(1)),
        ],
      ));
    }
    if (jobs != null) {
      rows.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.task_alt_outlined, size: 14),
          const SizedBox(width: 4),
          Text('$jobs jobs'),
        ],
      ));
    }
    if (score != null) {
      rows.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.trending_up, size: 14),
          const SizedBox(width: 4),
          Text(score!.toStringAsFixed(0)),
        ],
      ));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: rows,
    );
  }
}
