// lib/services/chat_service.dart
//
// ChatService — WhatsApp-style chat helpers (no extra plugins)
// ------------------------------------------------------------
// What this adds on top of ConversationScreen logic:
// • setTyping(channelId, uid, on)
// • markAllRead(channelId, uid, {limit})
// • sendText(...) with reply/quote support
// • uploadChatImageAndSend(...)
// • toggleReaction / toggleStar
// • deleteForMe / deleteForEveryone
// • incrementUnread for the other participant (dot-path update)
// • createOrGetChannel / channelIdFor (convenience)
//
// Firestore shapes used here are the same as ConversationScreen:
//   chats/{channelId} {
//     participants: [uidA, uidB],
//     lastMessage, lastMessageSenderId, lastMessageTimestamp,
//     typing: { <uid>: true/false },
//     unread: { <uid>: number }   // optional map
//   }
//   chats/{channelId}/messages/{id} {
//     type: 'text'|'image'|'offer',
//     senderId, text?, imageUrl?,
//     timestamp, deliveredAt,
//     readBy: { <uid>: true },    // receipts
//     reactions: { <uid>: '👍' },
//     replyToId?, replyToText?, replyToSenderId?,
//     starredBy: { <uid>: true },
//     deletedFor: { <uid>: true },
//     isDeleted: true
//   }

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ChatService {
  ChatService._();
  static final ChatService _i = ChatService._();
  factory ChatService() => _i;

  final _db = FirebaseFirestore.instance;

  // ---------------- Channel helpers ----------------

  String channelIdFor(String a, String b) => (a.compareTo(b) < 0) ? '${a}_$b' : '${b}_$a';

  Future<String> createOrGetChannel(String a, String b, {String? taskId}) async {
    final id = channelIdFor(a, b);
    final ref = _db.collection('chats').doc(id);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'participants': [a, b],
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        if (taskId != null) 'taskId': taskId,
      }, SetOptions(merge: true));
    } else if (taskId != null && (snap.data()?['taskId'] is! String)) {
      await ref.set({'taskId': taskId}, SetOptions(merge: true));
    }
    return id;
  }

  // ---------------- Typing & Read ----------------

  Future<void> setTyping(String channelId, String uid, bool isTyping) async {
    await _db.collection('chats').doc(channelId).set({
      'typing': {uid: isTyping},
      'typingAt': {uid: FieldValue.serverTimestamp()},
    }, SetOptions(merge: true));
  }

  /// Resets unread counter for uid and marks the latest {limit} incoming
  /// messages as read for read receipts.
  Future<void> markAllRead(String channelId, String uid, {int limit = 80}) async {
    final ref = _db.collection('chats').doc(channelId);

    // Zero unread (map dot-path is safest)
    await ref.set({'unread.$uid': 0}, SetOptions(merge: true));

    final msgs = await ref.collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();

    final batch = _db.batch();
    for (final d in msgs.docs) {
      final m = d.data();
      final sender = (m['senderId'] ?? '').toString();
      if (sender == uid) continue;
      batch.set(d.reference, {'readBy.$uid': true}, SetOptions(merge: true));
    }
    await batch.commit();
  }

  // ---------------- Send text / image ----------------

  Future<String?> sendText({
    required String channelId,
    required String senderId,
    required String text,
    String? replyToId,
    String? replyToText,
    String? replyToSenderId,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return null;

    final ref = _db.collection('chats').doc(channelId);
    final msgRef = ref.collection('messages').doc();

    await msgRef.set({
      'type': 'text',
      'text': t,
      'senderId': senderId,
      'timestamp': FieldValue.serverTimestamp(),
      'deliveredAt': FieldValue.serverTimestamp(),
      if (replyToId != null && replyToId.isNotEmpty) 'replyToId': replyToId,
      if (replyToText != null && replyToText.isNotEmpty) 'replyToText': replyToText,
      if (replyToSenderId != null && replyToSenderId.isNotEmpty) 'replyToSenderId': replyToSenderId,
    });

    await _touchChannelAfterSend(ref, senderId, preview: t);
    return msgRef.id;
  }

  Future<String?> uploadChatImageAndSend({
    required String channelId,
    required String senderId,
    required File file,
    String? replyToId,
    String? replyToText,
    String? replyToSenderId,
  }) async {
    final path = 'chat_attachments/$channelId/${DateTime.now().millisecondsSinceEpoch}_$senderId.jpg';
    final storageRef = FirebaseStorage.instance.ref(path);
    await storageRef.putFile(file);
    final url = await storageRef.getDownloadURL();

    final ref = _db.collection('chats').doc(channelId);
    final msgRef = ref.collection('messages').doc();

    await msgRef.set({
      'type': 'image',
      'imageUrl': url,
      'senderId': senderId,
      'timestamp': FieldValue.serverTimestamp(),
      'deliveredAt': FieldValue.serverTimestamp(),
      if (replyToId != null && replyToId.isNotEmpty) 'replyToId': replyToId,
      if (replyToText != null && replyToText.isNotEmpty) 'replyToText': replyToText,
      if (replyToSenderId != null && replyToSenderId.isNotEmpty) 'replyToSenderId': replyToSenderId,
    });

    await _touchChannelAfterSend(ref, senderId, preview: 'Photo');
    return msgRef.id;
  }

  Future<void> _touchChannelAfterSend(DocumentReference<Map<String, dynamic>> chatRef, String senderId, {required String preview}) async {
    // Update last message fields
    await chatRef.set({
      'lastMessage': preview,
      'lastMessageSenderId': senderId,
      'lastMessageTimestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Increment unread for the other participant (if participants array is present)
    final snap = await chatRef.get();
    final parts = ((snap.data()?['participants'] as List?)?.cast<String>() ?? const <String>[]);
    if (parts.length == 2) {
      final other = parts.firstWhere((u) => u != senderId, orElse: () => '');
      if (other.isNotEmpty) {
        await chatRef.set({'unread.$other': FieldValue.increment(1)}, SetOptions(merge: true));
      }
    }
  }

  // ---------------- Reactions / Star / Delete ----------------

  Future<void> toggleReaction({
    required String channelId,
    required String messageId,
    required String uid,
    required String emoji,
  }) async {
    final msgRef = _db.collection('chats').doc(channelId).collection('messages').doc(messageId);
    final snap = await msgRef.get();
    final map = (snap.data()?['reactions'] as Map?) ?? {};
    final has = map[uid] == emoji;
    await msgRef.set({'reactions.$uid': has ? FieldValue.delete() : emoji}, SetOptions(merge: true));
  }

  Future<void> toggleStar({
    required String channelId,
    required String messageId,
    required String uid,
  }) async {
    final msgRef = _db.collection('chats').doc(channelId).collection('messages').doc(messageId);
    final snap = await msgRef.get();
    final map = (snap.data()?['starredBy'] as Map?) ?? {};
    final on = map[uid] == true;
    await msgRef.set({'starredBy.$uid': on ? FieldValue.delete() : true}, SetOptions(merge: true));
  }

  Future<void> deleteForMe({
    required String channelId,
    required String messageId,
    required String uid,
  }) async {
    final msgRef = _db.collection('chats').doc(channelId).collection('messages').doc(messageId);
    await msgRef.set({'deletedFor.$uid': true}, SetOptions(merge: true));
  }

  Future<void> deleteForEveryone({
    required String channelId,
    required String messageId,
    required String senderId,
  }) async {
    final msgRef = _db.collection('chats').doc(channelId).collection('messages').doc(messageId);
    final snap = await msgRef.get();
    final data = snap.data() ?? {};
    if ((data['senderId'] ?? '') != senderId) return; // only the sender may revoke
    await msgRef.set({
      'isDeleted': true,
      'text': null,
      'imageUrl': null,
      'offerNote': null,
    }, SetOptions(merge: true));
  }
}
