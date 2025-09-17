// lib/screens/chat_thread_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:servana/widgets/chat/offer_message_card.dart';

class ChatThreadScreen extends StatefulWidget {
  final String chatId;
  const ChatThreadScreen({super.key, required this.chatId});

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _msgCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cid = widget.chatId;
    final stream = FirebaseFirestore.instance
        .collection('chats/$cid/messages')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('No messages yet.'));
                }
                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final m = docs[i].data();
                    final type = (m['type'] ?? '').toString();
                    if (type.startsWith('offer.')) {
                      return OfferMessageCard(message: m);
                    }
                    return ListTile(
                      title: Text((m['text'] ?? '').toString()),
                      subtitle: Text((m['actorId'] ?? '').toString()),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    child: _sending ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2),
                    ) : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      await FirebaseFirestore.instance.collection('chats/${widget.chatId}/messages').add({
        'type': 'text',
        'text': text,
        'actorId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _msgCtrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
