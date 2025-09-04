// lib/models/leaderboard_model.dart
//
// LeaderboardEntry model (pairs with LeaderboardScreen)
// • Works with precomputed leaderboard docs (preferred)
// • Friendly fallbacks (safe parsers) if some fields are missing
//
// Firestore shape (superset; all keys optional except role/userId/period):
// leaderboard/{id} {
//   role: 'helper' | 'poster',
//   userId: string,
//   name?: string,
//   photoURL?: string,
//   category?: string,            // normalized (e.g., 'cleaning')
//   period: 'all_time'|'monthly',
//   score: number,                // higher = better (precomputed server-side)
//   jobs?: number,                // completions in period
//   rating?: number,              // average rating in period or overall
//   createdAt?: Timestamp,
//   updatedAt?: Timestamp
// }

import 'package:cloud_firestore/cloud_firestore.dart';

class LeaderboardEntry {
  final String id;

  final String role;        // 'helper' | 'poster'
  final String userId;
  final String period;      // 'all_time' | 'monthly'
  final String? category;   // normalized e.g. 'cleaning'

  // Display
  final String? name;
  final String? photoURL;

  // Metrics
  final double score;
  final int jobs;
  final double rating;

  // Meta
  final DateTime? createdAt;
  final DateTime? updatedAt;

  LeaderboardEntry({
    required this.id,
    required this.role,
    required this.userId,
    required this.period,
    this.category,
    this.name,
    this.photoURL,
    this.score = 0.0,
    this.jobs = 0,
    this.rating = 0.0,
    this.createdAt,
    this.updatedAt,
  });

  // ---------------- Helpers ----------------

  LeaderboardEntry copyWith({
    String? id,
    String? role,
    String? userId,
    String? period,
    String? category,
    String? name,
    String? photoURL,
    double? score,
    int? jobs,
    double? rating,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LeaderboardEntry(
      id: id ?? this.id,
      role: role ?? this.role,
      userId: userId ?? this.userId,
      period: period ?? this.period,
      category: category ?? this.category,
      name: name ?? this.name,
      photoURL: photoURL ?? this.photoURL,
      score: score ?? this.score,
      jobs: jobs ?? this.jobs,
      rating: rating ?? this.rating,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ---------------- Safe parsers ----------------

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static int _asInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static DateTime? _ts(dynamic t) {
    if (t is Timestamp) return t.toDate();
    if (t is DateTime) return t;
    return null;
  }

  // ---------------- Factories ----------------

  factory LeaderboardEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    return LeaderboardEntry(
      id: doc.id,
      role: (m['role'] ?? 'helper').toString(),
      userId: (m['userId'] ?? '').toString(),
      period: (m['period'] ?? 'all_time').toString(),
      category: (m['category'] as String?)?.toString(),
      name: (m['name'] as String?)?.toString(),
      photoURL: (m['photoURL'] as String?)?.toString(),
      score: _asDouble(m['score']),
      jobs: _asInt(m['jobs']),
      rating: _asDouble(m['rating']),
      createdAt: _ts(m['createdAt']),
      updatedAt: _ts(m['updatedAt']),
    );
  }

  // ---------------- Serialization ----------------

  Map<String, dynamic> toMap({bool includeTimestamps = true}) {
    final out = <String, dynamic>{
      'role': role,
      'userId': userId,
      'period': period,
      if (category != null && category!.isNotEmpty) 'category': category,
      if (name != null && name!.isNotEmpty) 'name': name,
      if (photoURL != null && photoURL!.isNotEmpty) 'photoURL': photoURL,
      'score': score,
      'jobs': jobs,
      'rating': rating,
    };
    if (includeTimestamps) {
      out['updatedAt'] = FieldValue.serverTimestamp();
      if (createdAt == null) out['createdAt'] = FieldValue.serverTimestamp();
    }
    return out;
  }
}
