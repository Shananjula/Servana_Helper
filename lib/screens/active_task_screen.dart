// lib/screens/active_task_screen.dart
//
// "My Posts" for POSTERS:
//  • Tabs: Open | In Progress | Completed
//  • Search bar to filter by title/category
//  • Each card shows title, category, price, status chip, created time
//  • Quick actions: View (TaskDetails) and Manage Offers
//  • Post Task FAB
//
// Firestore expectations (aligns with your models):
//  tasks/{taskId} fields (subset):
//    - posterId: string (current user uid)
//    - title: string
//    - category: string (normalized id)
//    - price: number
//    - status: 'listed' | 'negotiation' | 'assigned' | 'in_progress' | 'completed' | 'cancelled'
//    - createdAt: Timestamp
//    - lat,lng (optional)
//
// This screen reads directly from Firestore so it won’t fight your models/services.
// If you have a repository/service layer, you can swap the queries there later.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:servana/screens/task_details_screen.dart';
import 'package:servana/services/firestore_service.dart';
import 'package:servana/screens/manage_offers_screen.dart';
import 'package:servana/screens/post_task_screen.dart';

class ActiveTaskScreen extends StatefulWidget {
  const ActiveTaskScreen({super.key, this.taskId});
  final String? taskId;

  @override
  State<ActiveTaskScreen> createState() => _ActiveTaskScreenState();
}

class _ActiveTaskScreenState extends State<ActiveTaskScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));

    // You can now access the taskId via widget.taskId if needed, for example:
    // if (widget.taskId != null) {
    //   print('Launched with task ID: ${widget.taskId}');
    // }
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Posts'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Open'),
            Tab(text: 'In Progress'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by title or category…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                  tooltip: 'Clear',
                  onPressed: () => _searchCtrl.clear(),
                  icon: const Icon(Icons.close),
                ),
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _TaskList(statuses: const ['listed', 'negotiation'], query: _query),
                _TaskList(statuses: const ['assigned', 'in_progress'], query: _query),
                _TaskList(statuses: const ['completed'], query: _query),
              ],
            ),
          ),
        ],
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PostTaskScreen()));
        },
        icon: const Icon(Icons.add),
        label: const Text('Post a task'),
      ),
    );
  }
}

// ---------------- LIST WIDGET ----------------

class _TaskList extends StatelessWidget {
  const _TaskList({required this.statuses, required this.query});
  final List<String> statuses;
  final String query;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('Please sign in to view your posts.'));
    }

    // Firestore: poster’s tasks in selected statuses, newest first.
    // whereIn max 10 values — we use <= 2 per tab, so safe.
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('tasks')
        .where('posterId', isEqualTo: uid)
        .where('status', whereIn: statuses)
        .orderBy('createdAt', descending: true)
        .limit(100);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingList();
        }
        final docs = snap.data?.docs ?? [];

        // Client-side search over title/category
        final filtered = docs.where((d) {
          if (query.isEmpty) return true;
          final m = d.data();
          final t = (m['title'] ?? '').toString().toLowerCase();
          final c = (m['category'] ?? '').toString().toLowerCase();
          return t.contains(query) || c.contains(query);
        }).toList();

        if (filtered.isEmpty) {
          return const _EmptyState();
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final doc = filtered[i];
            final data = doc.data();

            return _TaskCard(
              taskId: doc.id,
              title: (data['title'] ?? 'Task') as String,
              category: (data['category'] ?? '-') as String,
              status: (data['status'] ?? '-') as String,
              price: data['price'],
              createdAt: data['createdAt'],
            );
          },
        );
      },
    );
  }
}

// ---------------- TASK CARD ----------------

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.taskId,
    required this.title,
    required this.category,
    required this.status,
    required this.price,
    required this.createdAt,
  });

  final String taskId;
  final String title;
  final String category;
  final String status;
  final dynamic price; // number or null
  final dynamic createdAt; // Timestamp or null

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: taskId)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(
            children: [
              // Leading icon by category (simple mapping)
              CircleAvatar(
                backgroundColor: _catColor(category, cs).withOpacity(0.15),
                foregroundColor: _catColor(category, cs),
                child: _catIcon(category),
              ),
              const SizedBox(width: 12),
              // Title + meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: -6,
                      children: [
                        _ChipText(category),
                        _StatusChip(status),
                        if (price != null) _ChipText('LKR $price'),
                        if (createdAt != null) _ChipText(_timeAgo(createdAt)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Actions column
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.local_offer_outlined, size: 18),
                    label: const Text('Offers'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ManageOffersScreen(taskId: taskId)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.remove_red_eye_outlined, size: 18),
                    label: const Text('View'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: taskId)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (status == 'listed' || status == 'open')
                    OutlinedButton.icon(
                      icon: const Icon(Icons.flash_on, size: 18),
                      label: const Text('Boost (24h)'),
                      onPressed: () async {
                        try {
                          await FirestoreService().boostTask(taskId, costCoins: 3, hours: 24);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Boosted for 24 hours.')));
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Boost failed: $e')));
                          }
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(dynamic timestamp) {
    if (timestamp is! Timestamp) return '-';
    final dt = timestamp.toDate();
    final diff = DateTime.now().difference(dt);

    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  Color _catColor(String cat, ColorScheme cs) {
    switch (cat) {
      case 'cleaning':
        return Colors.blue;
      case 'delivery':
        return Colors.green;
      case 'repairs':
        return Colors.orange;
      case 'tutoring':
        return Colors.purple;
      case 'design':
        return Colors.pink;
      case 'writing':
        return Colors.teal;
      default:
        return cs.primary;
    }
  }

  Icon _catIcon(String cat) {
    switch (cat) {
      case 'cleaning':
        return const Icon(Icons.cleaning_services);
      case 'delivery':
        return const Icon(Icons.delivery_dining);
      case 'repairs':
        return const Icon(Icons.build);
      case 'tutoring':
        return const Icon(Icons.menu_book);
      case 'design':
        return const Icon(Icons.brush);
      case 'writing':
        return const Icon(Icons.edit);
      default:
        return const Icon(Icons.work_outline);
    }
  }
}

// ---------------- SUBWIDGETS ----------------

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final tone = _tone(status);
    return Chip(
      label: Text(_label(status)),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: tone.withOpacity(0.25)),
      backgroundColor: tone.withOpacity(0.10),
    );
  }

  String _label(String s) {
    switch (s) {
      case 'listed':
        return 'Open';
      case 'negotiation':
        return 'Negotiation';
      case 'assigned':
        return 'Assigned';
      case 'in_progress':
        return 'In progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return s;
    }
  }

  Color _tone(String s) {
    switch (s) {
      case 'listed':
        return Colors.blue;
      case 'negotiation':
        return Colors.amber;
      case 'assigned':
        return Colors.indigo;
      case 'in_progress':
        return Colors.deepPurple;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
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
            const Text('No posts here yet.'),
            const SizedBox(height: 4),
            const Text('Try creating a new task or switching tabs.'),
          ],
        ),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: 6,
      itemBuilder: (_, i) {
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.work_outline)),
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
