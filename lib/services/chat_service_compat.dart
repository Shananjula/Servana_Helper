// lib/services/chat_service_compat.dart
//
// Adds a compatibility method to ChatService so code that calls
//   _chat.createOrGetChannel(posterId, taskId: taskId)
// compiles and works. This uses a simple deterministic chat id based on the
// two member uids (and optional taskId) and ensures the chat doc exists.
//
// Usage: add this import in manage_offers_screen.dart:
//   import 'package:servana/services/chat_service_compat.dart';
//
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:servana/services/chat_service.dart';

String _sortedPairId(String a, String b) {
  return (a.compareTo(b) <= 0) ? '${a}_$b' : '${b}_$a';
}

extension ChatServiceCompat on ChatService {
  Future<DocumentReference<Map<String, dynamic>>> createOrGetChannel(
    String otherUserId, { String? taskId }
  ) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) {
      throw StateError('Not signed in');
    }

    // Use a deterministic channel id so we don't duplicate threads.
    final baseId = _sortedPairId(me, otherUserId);
    final chatId = (taskId == null || taskId.isEmpty) ? baseId : '${baseId}_$taskId';

    final ref = FirebaseFirestore.instance.collection('chats').doc(chatId);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'members': [me, otherUserId],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (taskId != null && taskId.isNotEmpty) 'taskId': taskId,
        'type': 'dm', // or 'task_dm' if you prefer
      }, SetOptions(merge: true));
    } else {
      await ref.set({
        'updatedAt': FieldValue.serverTimestamp(),
        if (taskId != null && taskId.isNotEmpty) 'taskId': taskId,
      }, SetOptions(merge: true));
    }

    return ref;
  }
}