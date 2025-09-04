// lib/screens/starred_messages_screen.dart
//
// Starred Messages (Helper app / role-agnostic)
// ---------------------------------------------
// • Shows all messages you starred across all chats (collectionGroup query)
// • Filters: All / Text / Images / Offers
// • Tap → opens the conversation (at channel level)
// • Long-press / overflow → Unstar, Copy text (if text), Open chat, Delete for me
//
// Firestore used (tolerant):
//   chats/{channelId}/messages/{messageId} {
//     type: 'text'|'image'|'offer',
//     text?, imageUrl?, offerAmount?, offerStatus?,
//     timestamp, senderId,
//     starredBy: { <uid>: true },
//     deletedFor?: { <uid>: true }
//   }
//   chats/{channelId} {
//     participants: [uidA, uidB]
//   }

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:servana/screens/conversation_screen.dart';

class StarredMessagesScreen extends StatefulWidget {
  const StarredMessagesScreen({super.key});

  @override
  State<StarredMessagesScreen> createState() => _StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends State<StarredMessagesScreen> {
  String _filter = 'all'; // all | text | image | offer

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Please sign in.')));
    }

    // collectionGroup query over all messages starred by me
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collectionGroup('messages')
        .where('starredBy.$uid', isEqualTo: true)
        .orderBy('timestamp', descending: true);

    if (_filter == 'text') {
      q = q.where('type', isEqualTo: 'text');
    } else if (_filter == 'image') {
      q = q.where('type', isEqualTo: 'image');
    } else if (_filter == 'offer') {
      q = q.where('type', isEqualTo: 'offer');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Starred messages'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 6),
          _FilterBar(
            value: _filter,
            onChanged: (v) => setState(() => _filter = v),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.limit(400).snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const _EmptyMessages();
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final m = d.data();

                    // Resolve channelId from collectionGroup doc: messages parent -> chats/{channelId}
                    final channelRef = d.reference.parent.parent; // chats/{channelId}
                    final channelId = channelRef?.id ?? '';

                    return _StarredTile(
                      messageDoc: d,
                      channelId: channelId,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'all', label: Text('All'), icon: Icon(Icons.star_outline)),
          ButtonSegment(value: 'text', label: Text('Text'), icon: Icon(Icons.chat_bubble_outline)),
          ButtonSegment(value: 'image', label: Text('Images'), icon: Icon(Icons.photo_outlined)),
          ButtonSegment(value: 'offer', label: Text('Offers'), icon: Icon(Icons.local_offer_outlined)),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _StarredTile extends StatelessWidget {
  const _StarredTile({required this.messageDoc, required this.channelId});

  final QueryDocumentSnapshot<Map<String, dynamic>> messageDoc;
  final String channelId;

  @override
  Widget build(BuildContext context) {
    final m = messageDoc.data();
    final type = (m['type'] ?? 'text').toString();
    final text = (m['text'] ?? '').toString();
    final imageUrl = (m['imageUrl'] ?? '').toString();
    final offerAmount = m['offerAmount'];
    final ts = (m['timestamp'] is Timestamp) ? (m['timestamp'] as Timestamp).toDate() : null;

    final (icon, title, subtitle) = switch (type) {
      'image' => (Icons.photo_outlined, 'Photo', ''),
      'offer' => (Icons.local_offer_outlined, 'Offer', offerAmount is num ? 'LKR ${offerAmount.toStringAsFixed(0)}' : ''),
      _ => (Icons.chat_bubble_outline, 'Message', text),
    };

    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ts != null)
              Text(
                _timeAgo(ts),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(width: 6),
            _MoreMenu(
              onUnstar: () => _unstar(messageDoc.reference),
              onOpenChat: () => _openChat(context, channelId),
              onCopy: (type == 'text' && text.isNotEmpty)
                  ? () => _copy(context, text)
                  : null,
              onDeleteForMe: () => _deleteForMe(messageDoc.reference),
            ),
          ],
        ),
        onTap: () => _openChat(context, channelId),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  Future<void> _unstar(DocumentReference ref) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await ref.set({'starredBy.$uid': FieldValue.delete()}, SetOptions(merge: true));
  }

  void _openChat(BuildContext context, String channelId) {
    if (channelId.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationScreen(channelId: channelId)));
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
    }
  }

  Future<void> _deleteForMe(DocumentReference ref) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await ref.set({'deletedFor.$uid': true}, SetOptions(merge: true));
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.onUnstar,
    required this.onOpenChat,
    required this.onDeleteForMe,
    this.onCopy,
  });

  final VoidCallback onUnstar;
  final VoidCallback onOpenChat;
  final VoidCallback onDeleteForMe;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (v) {
        switch (v) {
          case 'open':
            onOpenChat();
            break;
          case 'unstar':
            onUnstar();
            break;
          case 'copy':
            onCopy?.call();
            break;
          case 'delete_me':
            onDeleteForMe();
            break;
        }
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(value: 'open', child: Text('Open chat')),
        const PopupMenuItem(value: 'unstar', child: Text('Unstar')),
        if (onCopy != null) const PopupMenuItem(value: 'copy', child: Text('Copy text')),
        const PopupMenuItem(value: 'delete_me', child: Text('Delete for me')),
      ],
      icon: const Icon(Icons.more_vert),
    );
  }
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_border, size: 44, color: cs.outline),
            const SizedBox(height: 10),
            const Text('No starred messages'),
            const SizedBox(height: 4),
            const Text('Long-press any chat message to star it.'),
          ],
        ),
      ),
    );
  }
}
