
// lib/screens/chat_thread_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';

class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({super.key, required this.taskId, required this.posterId, required this.helperId});
  final String taskId;
  final String posterId;
  final String helperId;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _svc = ChatService();
  late final String _chatId;
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _chatId = _svc.resolveChatId(taskId: widget.taskId, posterId: widget.posterId, helperId: widget.helperId);
  }

  @override
  void dispose() { _input.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final msgQuery = FirebaseFirestore.instance.collection('chats').doc(_chatId).collection('messages').orderBy('createdAt');
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: msgQuery.snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final m = docs[i].data();
                  final mine = (m['authorId'] ?? '') == FirebaseAuth.instance.currentUser?.uid;
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: mine ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text((m['text'] ?? '') as String),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              Expanded(child: TextField(controller: _input, decoration: const InputDecoration(hintText: 'Message…'))),
              const SizedBox(width: 8),
              FilledButton(onPressed: () async { final t = _input.text.trim(); if (t.isEmpty) return; await _svc.sendText(_chatId, t); _input.clear(); }, child: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
