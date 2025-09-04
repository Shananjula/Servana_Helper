// lib/models/offer_model.dart
//
// Offer model (compatible with BOTH top-level /offers docs AND chat-based offers)
// ----------------------------------------------------------------------------
// Top-level Firestore (if you use /offers):
//   offers/{offerId} {
//     taskId: string,
//     posterId: string,
//     helperId: string,
//     price?: number,
//     message?: string,
//     status: 'pending'|'accepted'|'declined'|'withdrawn'|'counter'|'awaiting_topup',
//     createdAt: Timestamp,
//     updatedAt: Timestamp,
//     acceptedAt?: Timestamp
//   }
//
// Nested (legacy) under /tasks/{taskId}/offers/{offerId} uses the same fields.

import 'package:cloud_firestore/cloud_firestore.dart';

class Offer {
  final String id;
  final String taskId;
  final String posterId;
  final String helperId;
  final num? price;
  final String? message;
  final String status; // pending | accepted | declined | withdrawn | counter | awaiting_topup
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? acceptedAt;

  Offer({
    required this.id,
    required this.taskId,
    required this.posterId,
    required this.helperId,
    this.price,
    this.message,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.acceptedAt,
  });

  factory Offer.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snap) {
    final m = snap.data() ?? {};
    DateTime? _toDt(v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      return null;
    }

    return Offer(
      id: snap.id,
      taskId: (m['taskId'] ?? '') as String,
      posterId: (m['posterId'] ?? '') as String,
      helperId: (m['helperId'] ?? '') as String,
      price: (m['price'] is num) ? m['price'] as num : (m['amount'] as num?),
      message: (m['message'] ?? '') as String?,
      status: (m['status'] ?? 'pending') as String,
      createdAt: _toDt(m['createdAt']),
      updatedAt: _toDt(m['updatedAt']),
      acceptedAt: _toDt(m['acceptedAt']),
    );
  }

  Map<String, dynamic> toMap({bool forWrite = false}) {
    final out = <String, dynamic>{
      'taskId': taskId,
      'posterId': posterId,
      'helperId': helperId,
      if (price != null) 'price': price,
      if (message != null && message!.isNotEmpty) 'message': message,
      'status': status,
      if (acceptedAt != null) 'acceptedAt': acceptedAt,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (forWrite) {
      out['createdAt'] = FieldValue.serverTimestamp();
    }
    return out;
  }

  // -------------------- Helpers --------------------

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isDeclined => status == 'declined' || status == 'withdrawn';
  bool get isCounter => status == 'counter';
  bool get isAwaitingTopUp => status == 'awaiting_topup';
}
