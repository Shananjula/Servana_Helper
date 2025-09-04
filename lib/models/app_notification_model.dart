// lib/models/app_notification_model.dart
//
// AppNotification model (matches NotificationsScreen + FCM deep-links)
//
// Firestore shape (superset; all keys optional except userId/type):
// notifications/{id} {
//   userId: string,
//   type: 'chat'|'task'|'offer'|'system',
//   title?: string,
//   body?: string,
//   channelId?: string,   // for chat
//   taskId?: string,      // for task/offer
//   offerId?: string,     // if you use top-level offers
//   read: bool,
//   archived: bool,
//   createdAt: Timestamp,
//   readAt?: Timestamp,
//   updatedAt?: Timestamp,
// }
//
// This model includes helpers and safe parsers so UI stays resilient.

import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  final String id;
  final String userId;

  final String type; // 'chat'|'task'|'offer'|'system'
  final String? title;
  final String? body;

  final String? channelId; // chat deeplink
  final String? taskId;    // task/offer deeplink
  final String? offerId;   // optional

  final bool read;
  final bool archived;

  final DateTime? createdAt;
  final DateTime? readAt;
  final DateTime? updatedAt;

  AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    this.title,
    this.body,
    this.channelId,
    this.taskId,
    this.offerId,
    this.read = false,
    this.archived = false,
    this.createdAt,
    this.readAt,
    this.updatedAt,
  });

  // ---------- Factories ----------

  static DateTime? _ts(dynamic t) {
    if (t is Timestamp) return t.toDate();
    if (t is DateTime) return t;
    return null;
  }

  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    return AppNotification(
      id: doc.id,
      userId: (m['userId'] ?? '').toString(),
      type: (m['type'] ?? 'system').toString(),
      title: (m['title'] as String?)?.toString(),
      body: (m['body'] as String?)?.toString(),
      channelId: (m['channelId'] as String?)?.toString(),
      taskId: (m['taskId'] as String?)?.toString(),
      offerId: (m['offerId'] as String?)?.toString(),
      read: m['read'] == true,
      archived: m['archived'] == true,
      createdAt: _ts(m['createdAt']),
      readAt: _ts(m['readAt']),
      updatedAt: _ts(m['updatedAt']),
    );
  }

  // ---------- Serialization ----------

  Map<String, dynamic> toMap({bool includeTimestamps = true}) {
    final out = <String, dynamic>{
      'userId': userId,
      'type': type,
      if (title != null && title!.isNotEmpty) 'title': title,
      if (body != null && body!.isNotEmpty) 'body': body,
      if (channelId != null && channelId!.isNotEmpty) 'channelId': channelId,
      if (taskId != null && taskId!.isNotEmpty) 'taskId': taskId,
      if (offerId != null && offerId!.isNotEmpty) 'offerId': offerId,
      'read': read,
      'archived': archived,
    };
    if (includeTimestamps) {
      out['updatedAt'] = FieldValue.serverTimestamp();
      if (createdAt == null) {
        out['createdAt'] = FieldValue.serverTimestamp();
      }
    }
    return out;
  }

  // ---------- Helpers ----------

  bool get isChat => type == 'chat';
  bool get isTask => type == 'task';
  bool get isOffer => type == 'offer';
  bool get isSystem => type == 'system';

  AppNotification copyWith({
    String? id,
    String? userId,
    String? type,
    String? title,
    String? body,
    String? channelId,
    String? taskId,
    String? offerId,
    bool? read,
    bool? archived,
    DateTime? createdAt,
    DateTime? readAt,
    DateTime? updatedAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      channelId: channelId ?? this.channelId,
      taskId: taskId ?? this.taskId,
      offerId: offerId ?? this.offerId,
      read: read ?? this.read,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
