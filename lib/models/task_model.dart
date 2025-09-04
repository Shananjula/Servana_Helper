// lib/models/task_model.dart
//
// Unified Task model used across the app.
// - Handles both public posts and direct bookings (booking.direct == true)
// - Works with either `price` or `budget` fields in Firestore (we read/write `price`)
// - Normalizes timestamps and optional fields safely
//
// Firestore shape (superset; all keys optional except posterId/title):
// tasks/{taskId} {
//   title: string,
//   description?: string,
//   category?: string,                     // normalized (e.g., 'cleaning')
//   type: 'online' | 'physical',
//   status: 'open'|'listed'|'negotiating'|'assigned'|'en_route'|'arrived'|
//           'in_progress'|'pending_completion'|'completed'|'closed'|'rated'|
//           'cancelled'|'in_dispute',
//   posterId: string,
//   helperId?: string,
//   price?: number,                        // LKR (preferred)
//   budget?: number,                       // legacy; we read this too
//   lat?: number, lng?: number,
//   address?: string,
//   schedule?: { date?: string, start?: string, end?: string },
//   targetHelperId?: string,               // for direct booking intent
//   booking?: { direct?: bool },
//   proofUrls?: [string],
//   createdAt?: Timestamp,
//   updatedAt?: Timestamp
// }

import 'package:cloud_firestore/cloud_firestore.dart';

class Task {
  final String id;

  final String title;
  final String? description;

  final String category; // default '-'
  final String type;     // 'online' | 'physical'
  final String status;

  final String posterId;
  final String? helperId;

  /// LKR amount. We read from `price` or `budget` and expose as double.
  final double budget;

  final double? lat;
  final double? lng;
  final String? address;

  final Map<String, dynamic>? schedule;
  final bool isDirectBooking;

  final List<String> proofUrls;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  Task({
    required this.id,
    required this.title,
    required this.category,
    required this.type,
    required this.status,
    required this.posterId,
    this.description,
    this.helperId,
    this.budget = 0.0,
    this.lat,
    this.lng,
    this.address,
    this.schedule,
    this.isDirectBooking = false,
    this.proofUrls = const [],
    this.createdAt,
    this.updatedAt,
  });

  /// Backwards-friendly getter (some screens referenced `price`)
  double get price => budget;

  /// Factory that accepts either DocumentSnapshot or QueryDocumentSnapshot.
  factory Task.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};

    // Money: prefer `price`, else `budget`
    final num? rawPrice = (m['price'] is num)
        ? m['price'] as num
        : (m['budget'] is num)
        ? m['budget'] as num
        : null;

    List<String> _stringList(dynamic v) {
      if (v is List) {
        return v.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();
      }
      return const <String>[];
    }

    DateTime? _ts(dynamic t) {
      if (t is Timestamp) return t.toDate();
      if (t is DateTime) return t;
      return null;
    }

    return Task(
      id: doc.id,
      title: (m['title'] ?? 'Task').toString(),
      description: (m['description'] ?? '')?.toString(),
      category: (m['category'] ?? '-')?.toString() ?? '-',
      type: (m['type'] ?? 'physical')?.toString() ?? 'physical',
      status: (m['status'] ?? 'open')?.toString() ?? 'open',
      posterId: (m['posterId'] ?? '')?.toString() ?? '',
      helperId: (m['helperId'] as String?)?.toString(),
      budget: rawPrice?.toDouble() ?? 0.0,
      lat: (m['lat'] is num) ? (m['lat'] as num).toDouble() : null,
      lng: (m['lng'] is num) ? (m['lng'] as num).toDouble() : null,
      address: (m['address'] as String?)?.toString(),
      schedule: (m['schedule'] is Map) ? Map<String, dynamic>.from(m['schedule'] as Map) : null,
      isDirectBooking: (m['booking'] is Map) ? ((m['booking'] as Map)['direct'] == true) : false,
      proofUrls: _stringList(m['proofUrls']),
      createdAt: _ts(m['createdAt']),
      updatedAt: _ts(m['updatedAt']),
    );
  }

  /// For ad-hoc maps (e.g., when reading from a nested chat payload)
  factory Task.fromMap(String id, Map<String, dynamic> m) {
    final doc = _FakeDoc(id, m);
    return Task.fromFirestore(doc);
  }

  Map<String, dynamic> toMap({bool includeTimestamps = true}) {
    final map = <String, dynamic>{
      'title': title,
      'description': description,
      'category': category,
      'type': type,
      'status': status,
      'posterId': posterId,
      if (helperId != null) 'helperId': helperId,
      'price': budget, // preferred write key
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (address != null && address!.isNotEmpty) 'address': address,
      if (schedule != null) 'schedule': schedule,
      if (isDirectBooking) 'booking': {'direct': true},
      if (proofUrls.isNotEmpty) 'proofUrls': proofUrls,
    };
    if (includeTimestamps) {
      map['updatedAt'] = FieldValue.serverTimestamp();
      if (createdAt == null) {
        map['createdAt'] = FieldValue.serverTimestamp();
      }
    }
    return map;
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

  // Unused members to satisfy the interface at compile time.
  @override
  SnapshotMetadata get metadata => throw UnimplementedError();

  @override
  DocumentReference<Map<String, dynamic>> get reference => throw UnimplementedError();

  @override
  dynamic operator [](Object field) => _data[field];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
