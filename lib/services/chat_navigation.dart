// lib/services/chat_navigation.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'chat_id.dart';
import 'package:servana/screens/chat_thread_screen.dart';

Future<void> openChatWith({
  required BuildContext context,
  String? chatId,
  String? posterId,
  String? helperId,
  String? taskId,
}) async {
  String? cid = chatId;

  // Resolve missing pieces
  if (cid == null) {
    // Ensure we have all ids, fetch posterId from task if missing
    String? p = posterId;
    final h = helperId;
    final t = taskId;
    if (t == null || h == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing identifiers for chat')),
      );
      return;
    }
    if (p == null || p.isEmpty) {
      final tSnap = await FirebaseFirestore.instance.doc('tasks/$t').get();
      p = (tSnap.data() ?? const {})['posterId']?.toString();
    }
    if (p == null || p.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot resolve poster for this chat')),
      );
      return;
    }
    cid = chatIdFor(posterId: p, helperId: h, taskId: t);
    // Ensure chat doc exists (no-ops if already there)
    await FirebaseFirestore.instance.doc('chats/$cid').set({
      'chatId': cid, 'taskId': t, 'posterId': p, 'helperId': h,
      'members': [p, h],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  if (!context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ChatThreadScreen(chatId: cid!),
  ));
}
