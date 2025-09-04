// lib/models/service_model.dart
//
// Service model (matches ManageServicesScreen + AddEditServiceScreen)
// • Helper’s advertised service (title, category, price, description, active flag, image)
// • Safe parsers for all fields so UI doesn’t crash on missing data
//
// Firestore shape (superset; all keys optional except helperId/title):
// services/{serviceId} {
//   helperId: string,
//   title: string,
//   category?: string,            // e.g., 'Cleaning', 'Tutoring', …
//   price?: number,               // LKR
//   description?: string,
//   isActive?: bool,
//   imageUrl?: string,
//   createdAt?: Timestamp,
//   updatedAt?: Timestamp
// }

import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceModel {
  final String id;

  final String helperId;
  final String title;
  final String? category;

  final double price;          // LKR (0 if not set)
  final String? description;

  final bool isActive;
  final String? imageUrl;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  ServiceModel({
    required this.id,
    required this.helperId,
    required this.title,
    this.category,
    this.price = 0.0,
    this.description,
    this.isActive = true,
    this.imageUrl,
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

  factory ServiceModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};

    return ServiceModel(
      id: doc.id,
      helperId: (m['helperId'] ?? '').toString(),
      title: (m['title'] ?? 'Service').toString(),
      category: (m['category'] as String?)?.toString(),
      price: _asDouble(m['price']),
      description: (m['description'] as String?)?.toString(),
      isActive: m['isActive'] != false, // default true
      imageUrl: (m['imageUrl'] as String?)?.toString(),
      createdAt: _ts(m['createdAt']),
      updatedAt: _ts(m['updatedAt']),
    );
  }

  factory ServiceModel.fromMap(String id, Map<String, dynamic> m) {
    final fake = _FakeDoc(id, m);
    return ServiceModel.fromDoc(fake);
  }

  // ---------------- Serialization ----------------

  Map<String, dynamic> toMap({bool includeTimestamps = true}) {
    final out = <String, dynamic>{
      'helperId': helperId,
      'title': title,
      if (category != null && category!.isNotEmpty) 'category': category,
      'price': price,
      if (description != null && description!.isNotEmpty) 'description': description,
      'isActive': isActive,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
    };
    if (includeTimestamps) {
      out['updatedAt'] = FieldValue.serverTimestamp();
      if (createdAt == null) out['createdAt'] = FieldValue.serverTimestamp();
    }
    return out;
  }

  // ---------------- Helpers ----------------

  ServiceModel copyWith({
    String? id,
    String? helperId,
    String? title,
    String? category,
    double? price,
    String? description,
    bool? isActive,
    String? imageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ServiceModel(
      id: id ?? this.id,
      helperId: helperId ?? this.helperId,
      title: title ?? this.title,
      category: category ?? this.category,
      price: price ?? this.price,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// Tiny adapter to reuse fromDoc for raw maps.
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
