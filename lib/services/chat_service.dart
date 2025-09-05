// lib/services/chat_service.dart — Helper app
// Canonicalizes chat IDs and preserves existing behavior.
// - Direct chats: "<minUid>_<maxUid>"
// - Task chats  : "<minUid>_<maxUid>_<taskId>"

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/chat_id.dart';

class ChatService {
  ChatService._();
  static final ChatService _instance = ChatService._();
  factory ChatService() => _instance;

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _chats =>
      _db.collection('chats');

  CollectionReference<Map<String, dynamic>> _messages(String channelId) =>
      _chats.doc(channelId).collection('messages');

  String _me() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not signed in');
    }
    return uid;
  }

  /// Back-compat helper kept for old callers.
  String channelIdFor(String a, String b) =>
      (a.compareTo(b) <= 0) ? '${a}_$b' : '${b}_$a';

  /// New task chat helper (canonical).
  String taskChannelIdFor(String a, String b, String taskId) =>
      '${channelIdFor(a, b)}_$taskId';

  Future<String> createOrGetChannel(String otherUid, {String? taskId}) async {
    final me = _me();
    final channelId = (taskId == null)
        ? ChatId.forDirect(uidA: me, uidB: otherUid)
        : ChatId.forTask(uidA: me, uidB: otherUid, taskId: taskId);

    final now = FieldValue.serverTimestamp();
    await _chats.doc(channelId).set({
      'id': channelId,
      'members': [me, otherUid],
      if (taskId != null) 'taskId': taskId,
      'type': taskId == null ? 'direct' : 'task',
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    return channelId;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamMessages(String channelId) {
    return _messages(channelId).orderBy('createdAt', descending: true).snapshots();
  }

  Future<void> sendMessage({
    required String channelId,
    required String text,
    Map<String, dynamic>? extra,
  }) async {
    final me = _me();
    final now = FieldValue.serverTimestamp();

    await _messages(channelId).add({
      'text': text,
      'senderId': me,
      'createdAt': now,
      'type': 'text',
      if (extra != null) ...extra,
    });

    await _chats.doc(channelId).set({
      'lastMessage': text,
      'lastMessageTimestamp': now,
      'updatedAt': now,
    }, SetOptions(merge: true));
  }
}
