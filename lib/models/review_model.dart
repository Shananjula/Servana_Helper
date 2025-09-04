// lib/models/review_model.dart
//
// Review model (pairs with RatingScreen + helper/public profiles)
// --------------------------------------------------------------
// Firestore shape (superset; all keys optional except reviewerId/revieweeId/rating):
// reviews/{id} {
//   taskId?: string,
//   reviewerId: string,
//   revieweeId: string,
//   role: 'helper'|'poster',         // reviewee role (who is being reviewed)
//   rating: number,                  // 0.5 .. 5.0
//   comment?: string,
//   anonymous?: bool,
//   createdAt?: Timestamp,
//   updatedAt?: Timestamp
// }
//
// Notes:
// • We keep it tolerant to missing fields so UI won't crash.
// • Use with users/{uid} aggregates (averageRating, ratingCount) as a soft cache.

import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewModel {
  final String id;

  final String reviewerId;
  final String revieweeId;
  final String role;        // 'helper' | 'poster' (reviewee role)

  final double rating;      // 0.5 .. 5.0
  final String? comment;
  final bool anonymous;

  final String? taskId;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  ReviewModel({
    required this.id,
    required this.reviewerId,
    required this.revieweeId,
    required this.role,
    required this.rating,
    this.comment,
    this.anonymous = false,
    this.taskId,
    this.createdAt,
    this.updatedAt,
  });

  // ---------------- Safe parsers ----------------

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static DateTime? _ts(dynamic t) {
    if (t is Timestamp) return t.toDate();
    if (t is DateTime) return t;
    return null;
  }

  // ---------------- Factories ----------------

  factory ReviewModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    return ReviewModel(
      id: doc.id,
      reviewerId: (m['reviewerId'] ?? '').toString(),
      revieweeId: (m['revieweeId'] ?? '').toString(),
      role: (m['role'] ?? 'helper').toString(),
      rating: _asDouble(m['rating']),
      comment: (m['comment'] as String?)?.toString(),
      anonymous: m['anonymous'] == true,
      taskId: (m['taskId'] as String?)?.toString(),
      createdAt: _ts(m['createdAt']),
      updatedAt: _ts(m['updatedAt']),
    );
  }

  factory ReviewModel.fromMap(String id, Map<String, dynamic> m) {
    final fake = _FakeDoc(id, m);
    return ReviewModel.fromDoc(fake);
  }

  // ---------------- Serialization ----------------

  Map<String, dynamic> toMap({bool includeTimestamps = true}) {
    final out = <String, dynamic>{
      'reviewerId': reviewerId,
      'revieweeId': revieweeId,
      'role': role,
      'rating': rating,
      if (comment != null && comment!.isNotEmpty) 'comment': comment,
      'anonymous': anonymous,
      if (taskId != null && taskId!.isNotEmpty) 'taskId': taskId,
    };
    if (includeTimestamps) {
      out['updatedAt'] = FieldValue.serverTimestamp();
      if (createdAt == null) out['createdAt'] = FieldValue.serverTimestamp();
    }
    return out;
  }

  // ---------------- Helpers ----------------

  bool get isAnonymous => anonymous;
  String get displayComment => (comment ?? '').trim();

  ReviewModel copyWith({
    String? id,
    String? reviewerId,
    String? revieweeId,
    String? role,
    double? rating,
    String? comment,
    bool? anonymous,
    String? taskId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ReviewModel(
      id: id ?? this.id,
      reviewerId: reviewerId ?? this.reviewerId,
      revieweeId: revieweeId ?? this.revieweeId,
      role: role ?? this.role,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      anonymous: anonymous ?? this.anonymous,
      taskId: taskId ?? this.taskId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// Tiny adapter so we can reuse fromDoc for raw map inputs.
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

  // Unused members to satisfy the interface
  @override
  SnapshotMetadata get metadata => throw UnimplementedError();
  @override
  DocumentReference<Map<String, dynamic>> get reference => throw UnimplementedError();
  @override
  dynamic /* Map<String, dynamic> | T */ get(DataSource? source) => _data;
  @override
  dynamic operator [](Object field) => _data[field];
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
