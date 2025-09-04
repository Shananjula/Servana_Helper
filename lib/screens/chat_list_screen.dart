// lib/screens/chat_list_screen.dart
//
// Chats (Helper app)
// ------------------
// • Lists conversations the helper is part of
// • Merges channels from tolerant sources:
//     /chats           (participants: [uidA, uidB])
//     /channels        (members: [uidA, uidB])         // optional legacy
//     /chatChannels    (members: [uidA, uidB])         // optional legacy
//     /pairs           (members: [uidA, uidB])         // optional lightweight
// • Shows last message preview, unread badge (if available), tap → Conversation
// • Opens ChatInfo via trailing chevron menu
//
// Firestore (tolerant):
//   chats/{id} {
//     participants: [uidA, uidB],
//     lastMessage, lastMessageAt/lastMessageTimestamp/updatedAt,
//     taskId?, muted?:{uid:true}, archived?:{uid:true}, unread?:{uid:number}
//   }
//
// Notes:
// • We keep the list fast and defensive. Missing fields won't crash UI.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:servana/screens/conversation_screen.dart';
import 'package:servana/screens/chat_info_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        centerTitle: false,
      ),
      body: const _ChannelList(),
    );
  }
}

class _ChannelList extends StatelessWidget {
  const _ChannelList();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('Sign in to view your chats.'));
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _channelItemsStream(uid),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const _SkeletonList();
        }

        var items = snap.data!;
        // Sort newest first using a few tolerant timestamp keys
        items.sort((a, b) {
          int aTs = _toMillis(a['lastMessageTimestamp'] ?? a['lastMessageAt'] ?? a['updatedAt'] ?? a['createdAt']);
          int bTs = _toMillis(b['lastMessageTimestamp'] ?? b['lastMessageAt'] ?? b['updatedAt'] ?? b['createdAt']);
          return bTs.compareTo(aTs);
        });

        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No chats yet. Start a conversation from a task or offer.'),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) {
            final ch = items[i];

            // Title: try otherName/helperName/displayName then fallback
            final title = (ch['otherName'] ?? ch['helperName'] ?? ch['displayName'] ?? 'Conversation').toString();

            // Preview: lastMessage/preview/snippet
            final preview = (ch['lastMessage'] ?? ch['preview'] ?? ch['snippet'] ?? '').toString();

            // Unread (if provided)
            int unread = 0;
            final rawUnread = ch['unread'] ?? ch['unreadCount'];
            if (rawUnread is int) unread = rawUnread;
            if (rawUnread is num) unread = rawUnread.toInt();
            if (rawUnread is Map) {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null && rawUnread[uid] is num) unread = (rawUnread[uid] as num).toInt();
            }

            // Compute "other user id" for fallback channel building
            String otherId = (ch['otherId'] ?? ch['helperId'] ?? '').toString();
            if (otherId.isEmpty) {
              final mem = ch['members'] ?? ch['participants'];
              if (mem is List && mem.isNotEmpty) {
                final u = FirebaseAuth.instance.currentUser?.uid;
                otherId = mem.firstWhere((m) => m != u, orElse: () => mem.first).toString();
              }
            }

            final channelId = (ch['id'] ?? '').toString();

            return ListTile(
              tileColor: Theme.of(ctx).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(ctx).colorScheme.outline.withOpacity(0.12)),
              ),
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (unread > 0)
                    CircleAvatar(
                      radius: 12,
                      child: Text('$unread'),
                    ),
                  FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: otherId.isEmpty
                        ? null
                        : FirebaseFirestore.instance.collection('users').doc(otherId).get(),
                    builder: (context, usnap) {
                      if (!usnap.hasData) return const SizedBox.shrink();
                      final m = usnap.data!.data() ?? const <String, dynamic>{};
                      final isVerified = ((m['verificationStatus'] ?? '') as String)
                          .toString()
                          .toLowerCase()
                          .contains('verified');
                      return isVerified
                          ? const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.verified_rounded, size: 16, color: Colors.green),
                      )
                          : const SizedBox.shrink();
                    },
                  ),
                  IconButton(
                    tooltip: 'Info',
                    icon: const Icon(Icons.info_outline),
                    onPressed: () {
                      if (channelId.isEmpty) return;
                      Navigator.push(ctx, MaterialPageRoute(builder: (_) => ChatInfoScreen(channelId: channelId)));
                    },
                  )
                ],
              ),
              onTap: () {
                // Prefer channelId. If missing, fall back to otherId pairing.
                if (channelId.isNotEmpty) {
                  Navigator.of(ctx).push(MaterialPageRoute(
                    builder: (_) => ConversationScreen(channelId: channelId),
                  ));
                } else {
                  Navigator.of(ctx).push(MaterialPageRoute(
                    builder: (_) => ConversationScreen(otherUserId: otherId, otherUserName: title),
                  ));
                }
              },
            );
          },
        );
      },
    );
  }

  int _toMillis(dynamic ts) {
    if (ts == null) return 0;
    if (ts is int) return ts;
    if (ts is Timestamp) return ts.millisecondsSinceEpoch;
    if (ts is DateTime) return ts.millisecondsSinceEpoch;
    try { return int.parse(ts.toString()); } catch (_) { return 0; }
  }
}

/// Merge channels from multiple possible collections and emit on ANY update.
/// This avoids "empty screen until all sources are available".
Stream<List<Map<String, dynamic>>> _channelItemsStream(String uid) {
  final db = FirebaseFirestore.instance;
  final sources = <Stream<QuerySnapshot<Map<String, dynamic>>>>[
    // Modern
    db.collection('chats').where('participants', arrayContains: uid).snapshots(),
    // Legacy / optional
    db.collection('chatChannels').where('members', arrayContains: uid).snapshots(),
    db.collection('channels').where('members', arrayContains: uid).snapshots(),
    db.collection('pairs').where('members', arrayContains: uid).snapshots(),
  ];

  final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
  final latest = List<QuerySnapshot<Map<String, dynamic>>?>.filled(sources.length, null, growable: false);
  final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

  void emit() {
    final mergedDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final qs in latest) {
      if (qs == null) continue;
      mergedDocs.addAll(qs.docs);
    }
    // De-dupe by id; normalize to Map + attach id
    final byId = <String, Map<String, dynamic>>{};
    for (final d in mergedDocs) {
      final m = Map<String, dynamic>.from(d.data());
      m['id'] = d.id;
      byId[d.id] = m;
    }
    controller.add(byId.values.toList());
  }

  for (var i = 0; i < sources.length; i++) {
    final sub = sources[i].listen(
          (qs) {
        latest[i] = qs;
        emit();
      },
      onError: (_) {
        // Ignore this source if permission-denied/doesn't exist; still emit others
        latest[i] = null;
        emit();
      },
    );
    subs.add(sub);
  }

  controller.onCancel = () async {
    for (final s in subs) {
      await s.cancel();
    }
  };

  return controller.stream;
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(
        height: 72,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline.withOpacity(0.12)),
        ),
      ),
    );
  }
}
