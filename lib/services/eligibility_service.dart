// lib/services/eligibility_service.dart
//
// Central place to determine if the current helper is eligible to
// SEE a task and/or MAKE AN OFFER for a given category.
//
// Data it reads from users/{uid}:
//   registeredCategories: [String]
//   allowedCategoryIds: [String]
//   verifiedCategories: { [categoryId]: { status, verifiedAt?, expiresAt? } }
//
// Optional per-category proof doc for richer status (not required here):
//   category_proofs/{uid}_{categoryId} { status, notes?, submittedAt?, verifiedAt? }

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Normalizes a human label like "Home Cleaning"
/// -> "home_cleaning" to match our IDs consistently.
@visibleForTesting
String normalizeCategoryId(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

/// High-level result you can use in UI and guards.
class CategoryEligibility {
  const CategoryEligibility({
    required this.categoryId,
    required this.isRegistered,
    required this.status, // not_started | pending | verified | rejected | needs_more_info
    required this.isAllowed, // true when category is fully unlocked for offers
    this.notes,
    this.verifiedAt,
    this.submittedAt,
  });

  final String categoryId;
  final bool isRegistered;
  final String status;
  final bool isAllowed;

  /// Optional, populated when a reviewer left feedback (from category_proofs).
  final String? notes;

  final DateTime? verifiedAt;
  final DateTime? submittedAt;

  bool get canSeeTasks => isRegistered;               // show in Discover feed
  bool get canMakeOffer => isAllowed && status == 'verified';

  CategoryEligibility copyWith({
    bool? isRegistered,
    String? status,
    bool? isAllowed,
    String? notes,
    DateTime? verifiedAt,
    DateTime? submittedAt,
  }) {
    return CategoryEligibility(
      categoryId: categoryId,
      isRegistered: isRegistered ?? this.isRegistered,
      status: status ?? this.status,
      isAllowed: isAllowed ?? this.isAllowed,
      notes: notes ?? this.notes,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      submittedAt: submittedAt ?? this.submittedAt,
    );
  }
}

class EligibilityService {
  EligibilityService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  String? get _uid => _auth.currentUser?.uid;

  /// One-shot check (good for guards, button enables, etc).
  Future<CategoryEligibility> checkHelperEligibility(String rawCategoryId) async {
    final uid = _uid;
    if (uid == null) {
      return CategoryEligibility(
        categoryId: normalizeCategoryId(rawCategoryId),
        isRegistered: false,
        status: 'not_started',
        isAllowed: false,
      );
    }

    final categoryId = normalizeCategoryId(rawCategoryId);

    final userSnap = await _db.collection('users').doc(uid).get();
    final user = userSnap.data() ?? <String, dynamic>{};

    final registered = _asStringList(user['registeredCategories']);
    final allowed = _asStringList(user['allowedCategoryIds']);
    final verifiedMap = (user['verifiedCategories'] is Map)
        ? Map<String, dynamic>.from(user['verifiedCategories'])
        : const <String, dynamic>{};

    final isReg = registered.contains(categoryId);
    final isAllow = allowed.contains(categoryId);
    final status = _readStatus(verifiedMap[categoryId]);

    // Optionally read proof doc for richer timestamps/notes (if exists).
    DateTime? submittedAt, verifiedAt;
    String? notes;

    final proofId = '${uid}_$categoryId';
    final proofSnap =
    await _db.collection('category_proofs').doc(proofId).get();
    if (proofSnap.exists) {
      final p = proofSnap.data() ?? const <String, dynamic>{};
      submittedAt = _toDate(p['submittedAt']);
      verifiedAt = _toDate(p['verifiedAt']);
      notes = (p['notes'] ?? '').toString().trim().isEmpty ? null : p['notes'].toString();
    }

    return CategoryEligibility(
      categoryId: categoryId,
      isRegistered: isReg,
      status: status,
      isAllowed: isAllow,
      notes: notes,
      submittedAt: submittedAt,
      verifiedAt: verifiedAt,
    );
  }

  /// Live stream that updates when the user doc changes (great for badges).
  Stream<CategoryEligibility> watchEligibility(String rawCategoryId) async* {
    final uid = _uid;
    final categoryId = normalizeCategoryId(rawCategoryId);
    if (uid == null) {
      yield CategoryEligibility(
        categoryId: categoryId,
        isRegistered: false,
        status: 'not_started',
        isAllowed: false,
      );
      return;
    }

    final userDocRef = _db.collection('users').doc(uid);
    final proofDocRef = _db.collection('category_proofs').doc('${uid}_$categoryId');

    // Combine latest from user + proof. If proof doc doesn’t exist, we still get user updates.
    await for (final userSnap in userDocRef.snapshots()) {
      final user = userSnap.data() ?? <String, dynamic>{};
      final registered = _asStringList(user['registeredCategories']);
      final allowed = _asStringList(user['allowedCategoryIds']);
      final verifiedMap = (user['verifiedCategories'] is Map)
          ? Map<String, dynamic>.from(user['verifiedCategories'])
          : const <String, dynamic>{};

      final isReg = registered.contains(categoryId);
      final isAllow = allowed.contains(categoryId);
      final status = _readStatus(verifiedMap[categoryId]);

      // Try to read proof doc once per user change; if you want full reactivity,
      // you can split this into a proper Rx combineLatest of two streams.
      DateTime? submittedAt, verifiedAt;
      String? notes;
      try {
        final proofSnap = await proofDocRef.get();
        if (proofSnap.exists) {
          final p = proofSnap.data() ?? const <String, dynamic>{};
          submittedAt = _toDate(p['submittedAt']);
          verifiedAt = _toDate(p['verifiedAt']);
          notes = (p['notes'] ?? '').toString().trim().isEmpty ? null : p['notes'].toString();
        }
      } catch (_) {}

      yield CategoryEligibility(
        categoryId: categoryId,
        isRegistered: isReg,
        status: status,
        isAllowed: isAllow,
        notes: notes,
        submittedAt: submittedAt,
        verifiedAt: verifiedAt,
      );
    }
  }

  // ------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------

  static List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => normalizeCategoryId(e.toString())).toSet().toList();
    }
    return const <String>[];
  }

  static String _readStatus(dynamic v) {
    if (v is Map) {
      final s = (v['status'] ?? 'not_started').toString();
      return _allowedStatuses.contains(s) ? s : 'not_started';
    }
    if (v is String && _allowedStatuses.contains(v)) return v;
    return 'not_started';
  }

  static final Set<String> _allowedStatuses = <String>{
    'not_started', 'pending', 'verified', 'rejected', 'needs_more_info',
  };

  static DateTime? _toDate(dynamic ts) {
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return null;
  }
}
