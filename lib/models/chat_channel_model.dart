// lib/models/chat_channel_model.dart
//
// ChatChannel model (WhatsApp-style, backward compatible)
//
// Firestore shape (superset; all fields optional):
// chats/{channelId} {
//   participants: [uidA, uidB],
//   createdAt: Timestamp,
//   lastMessage: string,
//   lastMessageSenderId: string,
//   lastMessageTimestamp: Timestamp,
//   taskId?: string,                        // for task-linked threads
//   typing?: { <uid>: bool },               // per-user typing state
//   typingAt?: { <uid>: Timestamp },        // last typing ts per user
//   unread?: { <uid>: number },             // per-user unread counts
//   muted?: { <uid>: bool },                // per-user mute flag
//   archived?: { <uid>: bool }              // per-user archive flag
// }

import 'package:cloud_firestore/cloud_firestore.dart';

class ChatChannel {
  final String id;

  // Participants (2-user chats)
  final List<String> participants;

  // Last message meta (for list preview)
  final String? lastMessage;
  final String? lastMessageSenderId;
  final Timestamp? lastMessageTimestamp;

  // Link to a task (optional)
  final String? taskId;

  // Per-user state/maps
  final Map<String, bool> typing;     // uid -> true/false
  final Map<String, Timestamp> typingAt;
  final Map<String, int> unread;      // uid -> count
  final Map<String, bool> muted;      // uid -> true/false
  final Map<String, bool> archived;   // uid -> true/false

  // Timestamps
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  ChatChannel({
    required this.id,
    required this.participants,
    this.lastMessage,
    this.lastMessageSenderId,
    this.lastMessageTimestamp,
    this.taskId,
    Map<String, bool>? typing,
    Map<String, Timestamp>? typingAt,
    Map<String, int>? unread,
    Map<String, bool>? muted,
    Map<String, bool>? archived,
    this.createdAt,
    this.updatedAt,
  })  : typing = typing ?? const {},
        typingAt = typingAt ?? const {},
        unread = unread ?? const {},
        muted = muted ?? const {},
        archived = archived ?? const {};

  // ---------- Convenience ----------

  /// Return the other uid (assuming 2 participants); falls back to empty string.
  String otherOf(String myUid) {
    if (participants.isEmpty) return '';
    if (participants.length == 1) return participants.first;
    return participants.first == myUid ? participants[1] : participants.first;
  }

  int unreadFor(String uid) => unread[uid] ?? 0;
  bool isMutedFor(String uid) => muted[uid] == true;
  bool isArchivedFor(String uid) => archived[uid] == true;
  bool isTyping(String uid) => typing[uid] == true;

  DateTime? get lastAt => lastMessageTimestamp?.toDate();
  DateTime? get created => createdAt?.toDate();
  DateTime? get updated => updatedAt?.toDate();

  // ---------- Factories ----------

  static List<String> _listStr(dynamic v) {
    if (v is List) return v.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();
    return const <String>[];
  }

  static Map<String, bool> _mapBool(dynamic v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val == true));
    }
    return {};
  }

  static Map<String, int> _mapInt(dynamic v) {
    if (v is Map) {
      return v.map((k, val) {
        if (val is num) return MapEntry(k.toString(), val.toInt());
        if (val is String) return MapEntry(k.toString(), int.tryParse(val) ?? 0);
        return MapEntry(k.toString(), 0);
      });
    }
    return {};
  }

  static Map<String, Timestamp> _mapTs(dynamic v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val is Timestamp ? val : Timestamp.now()));
    }
    return {};
  }

  factory ChatChannel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    return ChatChannel(
      id: doc.id,
      participants: _listStr(m['participants']),
      lastMessage: (m['lastMessage'] as String?)?.toString(),
      lastMessageSenderId: (m['lastMessageSenderId'] as String?)?.toString(),
      lastMessageTimestamp: m['lastMessageTimestamp'] is Timestamp ? m['lastMessageTimestamp'] as Timestamp : null,
      taskId: (m['taskId'] as String?)?.toString(),
      typing: _mapBool(m['typing']),
      typingAt: _mapTs(m['typingAt']),
      unread: _mapInt(m['unread']),
      muted: _mapBool(m['muted']),
      archived: _mapBool(m['archived']),
      createdAt: m['createdAt'] is Timestamp ? m['createdAt'] as Timestamp : null,
      updatedAt: m['updatedAt'] is Timestamp ? m['updatedAt'] as Timestamp : null,
    );
  }

  // ---------- Serialization ----------

  Map<String, dynamic> toMap({bool includeTimestamps = true}) {
    final out = <String, dynamic>{
      'participants': participants,
      if (lastMessage != null) 'lastMessage': lastMessage,
      if (lastMessageSenderId != null) 'lastMessageSenderId': lastMessageSenderId,
      if (lastMessageTimestamp != null) 'lastMessageTimestamp': lastMessageTimestamp,
      if (taskId != null && taskId!.isNotEmpty) 'taskId': taskId,
      if (typing.isNotEmpty) 'typing': typing,
      if (typingAt.isNotEmpty) 'typingAt': typingAt,
      if (unread.isNotEmpty) 'unread': unread,
      if (muted.isNotEmpty) 'muted': muted,
      if (archived.isNotEmpty) 'archived': archived,
    };
    if (includeTimestamps) {
      out['updatedAt'] = FieldValue.serverTimestamp();
      if (createdAt == null) {
        out['createdAt'] = FieldValue.serverTimestamp();
      }
    }
    return out;
  }
}
