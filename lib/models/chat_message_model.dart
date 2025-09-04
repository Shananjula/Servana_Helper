// lib/models/chat_message_model.dart
//
// WhatsApp-style chat message model (backward compatible)
//
// Supports:
//   - 'text'   : text
//   - 'image'  : imageUrl
//   - 'offer'  : offerAmount(+offerNote), offerStatus: 'pending'|'accepted'|'declined'|'counter'
//
// Extras we added (all optional, merge-safe):
//   deliveredAt: Timestamp                     // server-ack (delivery)
//   readBy:     { <uid>: true }                // read receipts
//   reactions:  { <uid>: '👍' }                 // emoji per user
//   replyToId: string                          // quoted message id
//   replyToText: string                        // snapshot of quoted text
//   replyToSenderId: string
//   starredBy:  { <uid>: true }                // per-user star/favorite
//   deletedFor: { <uid>: true }                // "delete for me"
//   isDeleted: true                            // "delete for everyone"
//
// Firestore shape (superset; all keys optional except senderId/type):
// chats/{channelId}/messages/{messageId} {
//   type: 'text'|'image'|'offer',
//   senderId: string,
//   text?: string,
//   imageUrl?: string,
//   offerAmount?: number,
//   offerNote?: string,
//   offerStatus?: 'pending'|'accepted'|'declined'|'counter',
//   timestamp: Timestamp,
//   deliveredAt?: Timestamp,
//   readBy?: { <uid>: true },
//   reactions?: { <uid>: string },
//   replyToId?: string,
//   replyToText?: string,
//   replyToSenderId?: string,
//   starredBy?: { <uid>: true },
//   deletedFor?: { <uid>: true },
//   isDeleted?: bool
// }

import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String type; // 'text' | 'image' | 'offer'
  final String senderId;

  // Basic content
  final String? text;
  final String? imageUrl;

  // Offers
  final double? offerAmount;
  final String? offerNote;
  final String? offerStatus; // pending | accepted | declined | counter

  // Times
  final Timestamp? timestamp;   // sent
  final Timestamp? deliveredAt; // delivered (server ack)

  // Receipts / extras
  final Map<String, bool> readBy;     // uid -> true
  final Map<String, String> reactions; // uid -> emoji
  final String? replyToId;
  final String? replyToText;
  final String? replyToSenderId;
  final Map<String, bool> starredBy;  // uid -> true
  final Map<String, bool> deletedFor; // uid -> true
  final bool isDeleted;               // delete for everyone

  ChatMessage({
    required this.id,
    required this.type,
    required this.senderId,
    this.text,
    this.imageUrl,
    this.offerAmount,
    this.offerNote,
    this.offerStatus,
    this.timestamp,
    this.deliveredAt,
    Map<String, bool>? readBy,
    Map<String, String>? reactions,
    this.replyToId,
    this.replyToText,
    this.replyToSenderId,
    Map<String, bool>? starredBy,
    Map<String, bool>? deletedFor,
    this.isDeleted = false,
  })  : readBy = readBy ?? const {},
        reactions = reactions ?? const {},
        starredBy = starredBy ?? const {},
        deletedFor = deletedFor ?? const {};

  // ---------- Convenience ----------

  DateTime? get time => timestamp?.toDate();
  DateTime? get deliveredAtDate => deliveredAt?.toDate();

  bool get isText => type == 'text';
  bool get isImage => type == 'image';
  bool get isOffer => type == 'offer';

  double? get amount => offerAmount;

  bool isReadBy(String uid) => readBy[uid] == true;
  bool isStarredBy(String uid) => starredBy[uid] == true;
  bool isDeletedFor(String uid) => deletedFor[uid] == true;

  // ---------- Factories ----------

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static Map<String, bool> _mapBool(dynamic v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val == true));
    }
    return {};
  }

  static Map<String, String> _mapString(dynamic v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val?.toString() ?? ''));
    }
    return {};
  }

  factory ChatMessage.fromFirestore(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();
    return ChatMessage(
      id: doc.id,
      type: (m['type'] ?? 'text').toString(),
      senderId: (m['senderId'] ?? '').toString(),
      text: (m['text'] as String?)?.toString(),
      imageUrl: (m['imageUrl'] as String?)?.toString(),
      offerAmount: _asDouble(m['offerAmount']),
      offerNote: (m['offerNote'] as String?)?.toString(),
      offerStatus: (m['offerStatus'] as String?)?.toString(),
      timestamp: m['timestamp'] is Timestamp ? m['timestamp'] as Timestamp : null,
      deliveredAt: m['deliveredAt'] is Timestamp ? m['deliveredAt'] as Timestamp : null,
      readBy: _mapBool(m['readBy']),
      reactions: _mapString(m['reactions']),
      replyToId: (m['replyToId'] as String?)?.toString(),
      replyToText: (m['replyToText'] as String?)?.toString(),
      replyToSenderId: (m['replyToSenderId'] as String?)?.toString(),
      starredBy: _mapBool(m['starredBy']),
      deletedFor: _mapBool(m['deletedFor']),
      isDeleted: m['isDeleted'] == true,
    );
  }

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    return ChatMessage(
      id: doc.id,
      type: (m['type'] ?? 'text').toString(),
      senderId: (m['senderId'] ?? '').toString(),
      text: (m['text'] as String?)?.toString(),
      imageUrl: (m['imageUrl'] as String?)?.toString(),
      offerAmount: _asDouble(m['offerAmount']),
      offerNote: (m['offerNote'] as String?)?.toString(),
      offerStatus: (m['offerStatus'] as String?)?.toString(),
      timestamp: m['timestamp'] is Timestamp ? m['timestamp'] as Timestamp : null,
      deliveredAt: m['deliveredAt'] is Timestamp ? m['deliveredAt'] as Timestamp : null,
      readBy: _mapBool(m['readBy']),
      reactions: _mapString(m['reactions']),
      replyToId: (m['replyToId'] as String?)?.toString(),
      replyToText: (m['replyToText'] as String?)?.toString(),
      replyToSenderId: (m['replyToSenderId'] as String?)?.toString(),
      starredBy: _mapBool(m['starredBy']),
      deletedFor: _mapBool(m['deletedFor']),
      isDeleted: m['isDeleted'] == true,
    );
  }

  factory ChatMessage.fromMap(String id, Map<String, dynamic> m) {
    final fake = _FakeDoc(id, m);
    return ChatMessage.fromDoc(fake);
  }

  // ---------- Serialization ----------

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'senderId': senderId,
      if (text != null && text!.isNotEmpty) 'text': text,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      if (offerAmount != null) 'offerAmount': offerAmount,
      if (offerNote != null && offerNote!.isNotEmpty) 'offerNote': offerNote,
      if (offerStatus != null && offerStatus!.isNotEmpty) 'offerStatus': offerStatus,
      if (timestamp != null) 'timestamp': timestamp else 'timestamp': FieldValue.serverTimestamp(),
      if (deliveredAt != null) 'deliveredAt': deliveredAt,
      if (readBy.isNotEmpty) 'readBy': readBy,
      if (reactions.isNotEmpty) 'reactions': reactions,
      if (replyToId != null && replyToId!.isNotEmpty) 'replyToId': replyToId,
      if (replyToText != null && replyToText!.isNotEmpty) 'replyToText': replyToText,
      if (replyToSenderId != null && replyToSenderId!.isNotEmpty) 'replyToSenderId': replyToSenderId,
      if (starredBy.isNotEmpty) 'starredBy': starredBy,
      if (deletedFor.isNotEmpty) 'deletedFor': deletedFor,
      if (isDeleted) 'isDeleted': true,
    };
  }
}

// Adapter to reuse fromDoc for raw maps.
class _FakeDoc implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDoc(this._id, this._data);
  final String _id;
  final Map<String, dynamic> _data;

  @override
  String get id => _id;
  @override
  Map<String, dynamic>? data() => _data;
  @override
  bool get exists => true;

  // Unused members to satisfy interface
  @override
  SnapshotMetadata get metadata => throw UnimplementedError();
  @override
  DocumentReference<Map<String, dynamic>> get reference => throw UnimplementedError();
  @override
  dynamic operator [](Object field) => _data[field];
  @override
  dynamic get(Object field) => _data[field];
}
