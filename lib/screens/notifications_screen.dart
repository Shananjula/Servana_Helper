// lib/screens/notifications_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:servana/screens/task_details_screen.dart';
import 'package:servana/screens/conversation_screen.dart';
import 'package:servana/screens/verification_center_screen.dart';
import 'package:servana/screens/step_2_documents.dart' as step2;

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _markingAll = false;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Alerts')),
        body: const _Empty(message: 'Sign in to view alerts.'),
      );
    }

    final q = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          if (!_markingAll)
            IconButton(
              tooltip: 'Mark all read',
              icon: const Icon(Icons.done_all_rounded),
              onPressed: () async {
                setState(() => _markingAll = true);
                try {
                  final batch = FirebaseFirestore.instance.batch();
                  final qs = await q.limit(100).get();
                  for (final d in qs.docs) {
                    if ((d.data()['isRead'] ?? false) == false) {
                      batch.set(d.reference, {'isRead': true}, SetOptions(merge: true));
                    }
                  }
                  await batch.commit();
                } catch (_) {
                } finally {
                  if (mounted) setState(() => _markingAll = false);
                }
              },
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const _Empty(message: 'No alerts yet.');
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final id = docs[i].id;
              final isRead = (d['isRead'] ?? false) == true;
              final title = (d['title'] ?? 'Notification').toString();
              final body  = (d['body']  ?? '').toString();
              dynamic ts = d['timestamp'];
              String timeAgo = '';
              if (ts is Timestamp) timeAgo = _timeAgo(ts.toDate());

              return Dismissible(
                key: ValueKey(id),
                direction: DismissDirection.endToStart,
                background: _SwipeBg(
                  label: isRead ? 'Mark unread' : 'Mark read',
                  icon: isRead ? Icons.markunread_rounded : Icons.done_all_rounded,
                ),
                confirmDismiss: (_) async {
                  try {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('notifications')
                        .doc(id)
                        .set({'isRead': !isRead}, SetOptions(merge: true));
                  } catch (_) {}
                  return false;
                },
                child: ListTile(
                  tileColor: isRead
                      ? null
                      : Theme.of(context).colorScheme.primary.withOpacity(0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.12),
                    ),
                  ),
                  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Text(timeAgo, style: Theme.of(context).textTheme.labelSmall),
                  onTap: () => _openRelated(context, d),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openRelated(BuildContext context, Map<String, dynamic> d) {
    final type = (d['type'] as String?)?.toLowerCase() ?? '';
    final relatedId = (d['relatedId'] as String?) ?? '';

    switch (type) {
      case 'chat':
        if (relatedId.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => ConversationScreen(channelId: relatedId),
          ));
        }
        break;

      case 'task':
      case 'task_details':
      case 'task_offer':
        if (relatedId.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => TaskDetailsScreen(taskId: relatedId),
          ));
        }
        break;

      case 'verification_update':
      case 'verification_approved':
      case 'verification_rejected':
        if (relatedId.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => step2.Step2Documents(initialCategoryId: relatedId),
          ));
        } else {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => const VerificationCenterScreen(),
          ));
        }
        break;

      default:
        break;
    }
  }
}

class _SwipeBg extends StatelessWidget {
  const _SwipeBg({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: cs.primaryContainer,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.primary)),
          const SizedBox(width: 8),
          Icon(icon, color: cs.primary),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;

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
            Text(message),
          ],
        ),
      ),
    );
  }
}

String _timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}
