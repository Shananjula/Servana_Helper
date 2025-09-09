
// lib/services/chat_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/chat_id.dart';

class ChatService {
  ChatService({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get uid => _auth.currentUser!.uid;

  String resolveChatId({required String taskId, required String posterId, required String helperId}) {
    return chatIdForTaskPair(taskId: taskId, posterId: posterId, helperId: helperId);
  }

  Future<String> ensureChat({required String taskId, required String posterId, required String helperId, Map<String, dynamic>? taskPreview}) async {
    final chatId = resolveChatId(taskId: taskId, posterId: posterId, helperId: helperId);
    final ref = _db.collection('chats').doc(chatId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        tx.set(ref, {
          'taskId': taskId,
          'posterId': posterId,
          'helperId': helperId,
          'members': [posterId, helperId],
          'createdAt': FieldValue.serverTimestamp(),
          'lastMsgAt': FieldValue.serverTimestamp(),
          if (taskPreview != null) 'taskPreview': taskPreview,
        });
      }
    });
    return chatId;
  }

  Future<void> sendText(String chatId, String text) async {
    final msgRef = _db.collection('chats').doc(chatId).collection('messages').doc();
    await _db.runTransaction((tx) async {
      tx.set(msgRef, {
        'type': 'text',
        'text': text,
        'authorId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.update(_db.collection('chats').doc(chatId), {
        'lastMsg': text,
        'lastMsgAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
