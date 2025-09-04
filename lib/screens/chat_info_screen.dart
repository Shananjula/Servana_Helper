// lib/screens/chat_info_screen.dart
//
// Chat Info (Helper app)
// ----------------------
// • Header: other participant, channel id snippet, task link (if any)
// • Quick toggles: Mute / Archive / Clear chat (for me)
// • Media gallery: all photos shared in this chat (tap to view fullscreen)
// • Starred: quick link to StarredMessagesScreen
// • Search in chat: lightweight text search over recent messages; tap → open chat
//
// Firestore usage (tolerant):
//   chats/{channelId} {
//     participants: [uidA, uidB],
//     taskId?: string,
//     muted?:    { <uid>: true },
//     archived?: { <uid>: true },
//     updatedAt?: Timestamp
//   }
//   chats/{channelId}/messages/{id} (type: 'text'|'image', ...)

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:servana/screens/helper_public_profile_screen.dart';

import 'package:servana/screens/conversation_screen.dart';
import 'package:servana/screens/starred_messages_screen.dart';
import 'package:servana/screens/task_details_screen.dart';

class ChatInfoScreen extends StatefulWidget {
  const ChatInfoScreen({super.key, required this.channelId});
  final String channelId;

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  final _searchCtrl = TextEditingController();
  String _q = '';
  bool _busyClear = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _q = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.channelId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat info'),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: chatRef.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final m = snap.data!.data() ?? {};
          final parts = ((m['participants'] as List?)?.cast<String>() ?? const <String>[]);
          final other = parts.isNotEmpty ? (parts.first == _uid ? (parts.length > 1 ? parts[1] : '') : parts.first) : '';
          final muted = (m['muted'] is Map) ? (m['muted'][_uid] == true) : false;
          final archived = (m['archived'] is Map) ? (m['archived'][_uid] == true) : false;
          final taskId = (m['taskId'] ?? '') as String;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // Header
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        child: Text(other.isNotEmpty ? other.substring(0, 2).toUpperCase() : '?'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Channel', style: Theme.of(context).textTheme.titleMedium),
                            Text(widget.channelId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall),
                            if (taskId.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: InkWell(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: taskId)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.assignment_outlined, size: 16),
                                      const SizedBox(width: 6),
                                      Text('Linked task • $taskId',
                                          style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Open chat',
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ConversationScreen(channelId: widget.channelId)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Other participant quick actions
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: other.isEmpty
                        ? null
                        : () {
                      Navigator.push(
                          context, MaterialPageRoute(builder: (_) => HelperPublicProfileScreen(helperId: other)));
                    },
                    icon: const Icon(Icons.person_rounded, size: 18),
                    label: const Text('View profile'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 'Verified for' chips for the other participant (if helper)
              FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: other.isEmpty ? null : FirebaseFirestore.instance.collection('users').doc(other).get(),
                builder: (context, usnap) {
                  if (other.isEmpty || !usnap.hasData) return const SizedBox.shrink();
                  final u = usnap.data!.data() ?? const <String, dynamic>{};
                  if (u['isHelper'] != true) return const SizedBox.shrink();
                  final allowed = (u['allowedCategoryIds'] is List)
                      ? List<String>.from(u['allowedCategoryIds']).map((e) => e.toString()).toList()
                      : const <String>[];
                  if (allowed.isEmpty) return const SizedBox.shrink();
                  return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    future: FirebaseFirestore.instance.collection('categories').get(),
                    builder: (context, csnap) {
                      final labelFor = (String id) {
                        if (!csnap.hasData) return id.replaceAll('_', ' ');
                        final m = {for (final d in csnap.data!.docs) d.id: (d.data()['label'] ?? d.id).toString()};
                        return (m[id] ?? id).toString();
                      };
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Verified for', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: -6,
                                children: allowed
                                    .take(10)
                                    .map((id) => Chip(
                                  label: Text(labelFor(id)),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: Colors.green.withOpacity(0.12),
                                  side: BorderSide(color: Colors.green.withOpacity(0.2)),
                                ))
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 12),

              // Toggles
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      value: muted,
                      onChanged: (v) async => _setFlag('muted', v),
                      title: const Text('Mute notifications'),
                      secondary: const Icon(Icons.notifications_off_outlined),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: archived,
                      onChanged: (v) async => _setFlag('archived', v),
                      title: const Text('Archive chat'),
                      secondary: const Icon(Icons.archive_outlined),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.star_outline),
                      title: const Text('Starred messages'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const StarredMessagesScreen()),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: _busyClear
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.delete_outline, color: Colors.red),
                      title: const Text('Clear chat'),
                      subtitle: const Text('Deletes all messages for you (keeps them for the other user)'),
                      onTap: _busyClear ? null : _clearChatForMe,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Media
              Text('Media, links & docs', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _MediaGrid(channelId: widget.channelId),

              const SizedBox(height: 16),

              // Search in chat
              Text('Search in chat', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'Type to search messages…',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 8),
              if (_q.isNotEmpty) _SearchResults(channelId: widget.channelId, q: _q),
            ],
          );
        },
      ),
    );
  }

  Future<void> _setFlag(String key, bool value) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(widget.channelId).set({
        key: {_uid: value},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not update: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _clearChatForMe() async {
    setState(() => _busyClear = true);
    try {
      final ref =
      FirebaseFirestore.instance.collection('chats').doc(widget.channelId).collection('messages');
      const pageSize = 400; // keep under 500 batch ops
      Query<Map<String, dynamic>> q = ref.orderBy('timestamp', descending: true).limit(pageSize);

      while (true) {
        final snap = await q.get();
        if (snap.docs.isEmpty) break;

        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap.docs) {
          batch.set(d.reference, {'deletedFor.$_uid': true}, SetOptions(merge: true));
        }
        await batch.commit();

        final last = snap.docs.last;
        q = ref.orderBy('timestamp', descending: true).startAfterDocument(last).limit(pageSize);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat cleared.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not clear chat: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _busyClear = false);
    }
  }
}

// ---------------- Media grid ----------------

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.channelId});
  final String channelId;

  @override
  Widget build(BuildContext context) {
    final ref =
    FirebaseFirestore.instance.collection('chats').doc(channelId).collection('messages');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref.where('type', isEqualTo: 'image').orderBy('timestamp', descending: true).limit(120).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 110, child: Center(child: CircularProgressIndicator()));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('No media yet'),
              subtitle: const Text('Photos shared in this chat will appear here.'),
            ),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: 1,
          ),
          itemBuilder: (_, i) {
            final url = (docs[i].data()['imageUrl'] ?? '').toString();
            return GestureDetector(
              onTap: () => _openViewer(context, url),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(url, fit: BoxFit.cover),
              ),
            );
          },
        );
      },
    );
  }

  void _openViewer(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          child: Stack(
            children: [
              Positioned.fill(child: Image.network(url, fit: BoxFit.contain)),
              Positioned(
                right: 8, top: 8,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Search results ----------------

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.channelId, required this.q});
  final String channelId;
  final String q;

  @override
  Widget build(BuildContext context) {
    final ref =
    FirebaseFirestore.instance.collection('chats').doc(channelId).collection('messages');

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: ref.orderBy('timestamp', descending: true).limit(300).get(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
        }
        final docs = snap.data!.docs.where((d) {
          final m = d.data();
          final type = (m['type'] ?? 'text').toString();
          if (type != 'text') return false;
          final t = (m['text'] ?? '').toString().toLowerCase();
          return t.contains(q);
        }).toList();

        if (docs.isEmpty) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.search_off),
              title: const Text('No matches'),
              subtitle: Text('Try a different keyword.'),
            ),
          );
        }

        return Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length.clamp(0, 30),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final m = docs[i].data();
              final text = (m['text'] ?? '').toString();
              final ts = (m['timestamp'] is Timestamp) ? (m['timestamp'] as Timestamp).toDate() : null;
              return ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(ts != null ? _timeAgo(ts) : ''),
                onTap: () => Navigator.push(
                  _,
                  MaterialPageRoute(builder: (_) => ConversationScreen(channelId: channelId)),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
