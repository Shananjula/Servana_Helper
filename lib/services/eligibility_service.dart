
// lib/services/eligibility_service.dart
//
// Eligibility gating (v2.1):
// - Canonicalize labels/ids aggressively (slug + common prefix stripping)
// - Allow if EITHER:
//      a) category tokens intersect user's allowedCategoryIds/tokens/labels
//      b) OR the user is VERIFIED for that category (verifiedCategories[cat].status == 'verified')
// - For PHYSICAL categories, require basic docs (flags.basicVerified) regardless.
// - Clear reason: 'basic_docs' | 'category_not_allowed' | 'not_signed_in'
//
// Backwards‑compatible API:
//
//   Future<CategoryEligibility> checkHelperEligibility(String rawCategoryId, {bool isPhysical = false})
//   Future<CategoryEligibility> checkHelperEligibilityForTask(Map<String, dynamic> task)
//
// ---------------------------------------------------------------------

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ---- Top-level helpers (accessible to normalizeCategoryId) ------------------

String _slug(dynamic v) {
  final s = (v ?? '').toString().trim().toLowerCase();
  if (s.isEmpty) return s;
  final sb = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch);
    final isAZ = (ch >= 97 && ch <= 122); // a-z
    final is09 = (ch >= 48 && ch <= 57);  // 0-9
    if (isAZ || is09) {
      sb.write(c);
    } else if (c == ' ' || c == '-' || c == '.' || c == '/' || c == ':' || c == '–' || c == '—' || c == '_') {
      sb.write('_');
    }
    // drop other punctuation
  }
  return sb.toString().replaceAll(RegExp(r'_+'), '_').trim().replaceAll(RegExp(r'^_+|_+$'), '');
}

String _deprefix(String s) {
  // Strip common prefixes that appear in doc IDs / labels
  // e.g., cat_home_tutoring, category_home_tutoring, phys_home_tutoring, physical_home_tutoring
  const prefixes = [
    'cat_', 'category_', 'phys_', 'physical_', 'online_', 'onsite_', 'on_site_', 'task_', 'svc_', 'service_'
  ];
  for (final p in prefixes) {
    if (s.startsWith(p)) return s.substring(p.length);
  }
  return s;
}

// Export normalizer so UI can share it
String normalizeCategoryId(String raw) => _deprefix(_slug(raw));

// --- Public DTO -------------------------------------------------------
class CategoryEligibility {
  final String categoryId;          // canonical id we evaluated
  final bool isRegistered;          // user registered for this category (coarse)
  final String status;              // 'not_started' | 'pending' | 'verified' | 'rejected' | 'needs_more_info'
  final bool isAllowed;             // can actually make offers NOW
  final String? reason;             // null if allowed; otherwise 'basic_docs' | 'category_not_allowed' | 'not_signed_in'
  final DateTime? submittedAt;
  final DateTime? verifiedAt;

  const CategoryEligibility({
    required this.categoryId,
    required this.isRegistered,
    required this.status,
    required this.isAllowed,
    this.reason,
    this.submittedAt,
    this.verifiedAt,
  });

  @override
  String toString() {
    return 'CategoryEligibility(categoryId: $categoryId, isRegistered: $isRegistered, '
           'status: $status, isAllowed: $isAllowed, reason: $reason, '
           'submittedAt: $submittedAt, verifiedAt: $verifiedAt)';
  }
}

// --- Service ----------------------------------------------------------
class EligibilityService {
  EligibilityService._();
  static final EligibilityService _instance = EligibilityService._();
  factory EligibilityService() => _instance;

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  Future<CategoryEligibility> checkHelperEligibility(
    String rawCategoryId, {
    bool isPhysical = false,
  }) async {
    return _check(
      categoryTokens: _tokensForCategory(rawCategoryId),
      categoryId: normalizeCategoryId(rawCategoryId),
      isPhysical: isPhysical,
    );
  }

  Future<CategoryEligibility> checkHelperEligibilityForTask(
    Map<String, dynamic> task,
  ) async {
    final tokens = _taskCandidates(task);
    final catId = tokens.isNotEmpty ? tokens.first : normalizeCategoryId(task['categoryId'] ?? task['category'] ?? '');
    final isPhysical = (task['type']?.toString().toLowerCase() == 'physical') || (task['isPhysical'] == true);
    return _check(categoryTokens: tokens, categoryId: catId, isPhysical: isPhysical);
  }

  // ---- Core ----------------------------------------------------------
  Future<CategoryEligibility> _check({
    required Set<String> categoryTokens,
    required String categoryId,
    required bool isPhysical,
  }) async {
    final uid = _uid;
    if (uid == null) {
      return CategoryEligibility(
        categoryId: categoryId,
        isRegistered: false,
        status: 'not_started',
        isAllowed: false,
        reason: 'not_signed_in',
      );
    }

    final userSnap = await _db.collection('users').doc(uid).get();
    final user = userSnap.data() ?? <String, dynamic>{};

    // Registration/verification
    final registered = _canonSet(user['registeredCategories']);
    final allowedIds = _canonSet(user['allowedCategoryIds']);
    final allowedTok = _canonSet(user['allowedCategoryTokens']);
    final allowedLbl = _canonSet(user['allowedCategoryLabels']); // just in case
    final allowedAll = {...allowedIds, ...allowedTok, ...allowedLbl};

    final verifiedMap = (user['verifiedCategories'] is Map)
        ? Map<String, dynamic>.from(user['verifiedCategories'])
        : const <String, dynamic>{};

    // --- token sets ---------------------------------------------------
    final taskTokens = categoryTokens.map(normalizeCategoryId).toSet();
    final allowTokens = allowedAll.map(normalizeCategoryId).toSet();

    // Also treat VERIFIED categories as allowed (client-side) — avoids UX deadlocks
    final verifiedAllowed = <String>{};
    verifiedMap.forEach((k, v) {
      final st = _readStatus(v);
      if (st == 'verified') {
        verifiedAllowed.add(normalizeCategoryId(k));
      }
    });

    // Basic docs gate for physical categories
    final flags = (user['flags'] is Map) ? Map<String, dynamic>.from(user['flags']) : const <String, dynamic>{};
    final basicOk = flags['basicVerified'] == true || user['basicVerified'] == true || user['verifiedBasicDocs'] == true;
    final needsBasicDocs = isPhysical && !basicOk;

    // Intersections with generous hierarchy match
    bool overlap = _anyOverlap(taskTokens, allowTokens);
    if (!overlap && verifiedAllowed.isNotEmpty) {
      overlap = _anyOverlap(taskTokens, verifiedAllowed);
    }

    final isAllow = !needsBasicDocs && overlap;

    final status = _readStatus(verifiedMap[categoryId]);
    return CategoryEligibility(
      categoryId: categoryId,
      isRegistered: registered.contains(categoryId) || _anyHierarchical(registered, categoryId),
      status: status,
      isAllowed: isAllow,
      reason: isAllow ? null : (needsBasicDocs ? 'basic_docs' : 'category_not_allowed'),
      submittedAt: _toDate(verifiedMap[categoryId]?['submittedAt']),
      verifiedAt: _toDate(verifiedMap[categoryId]?['verifiedAt']),
    );
  }

  // ---- Helpers -------------------------------------------------------

  Set<String> _taskCandidates(Map<String, dynamic> t) {
    final s = <String>{};
    s.addAll(_canonSet(t['categoryId']));
    s.addAll(_canonSet(t['category']));
    s.addAll(_canonSet(t['mainCategoryId']));
    s.addAll(_canonSet(t['mainCategory']));
    s.addAll(_canonSet(t['categoryTokens']));
    s.addAll(_canonSet(t['extraCategoryIds']));
    s.addAll(_canonSet(t['extraCategoryTokens']));
    if (s.isEmpty && t.containsKey('label')) s.add(normalizeCategoryId(t['label']));
    if (s.isEmpty && t.containsKey('title')) s.add(normalizeCategoryId(t['title']));
    final out = <String>{};
    for (final tok in s) {
      out.add(tok);
      out.add(tok.replaceAll('__', '_'));
      out.add(tok.replaceAll('-', '_'));
    }
    return out.where((e) => e.isNotEmpty).toSet();
  }

  Set<String> _tokensForCategory(dynamic any) {
    final s = _canonSet(any);
    if (s.isEmpty && any is String) return {normalizeCategoryId(any)};
    final out = <String>{};
    for (final x in s) {
      out.add(x);
      out.add(x.replaceAll('__', '_'));
      out.add(x.replaceAll('-', '_'));
    }
    return out.where((e) => e.isNotEmpty).toSet();
  }

  static Set<String> _canonSet(dynamic v) {
    final out = <String>{};
    if (v == null) return out;
    if (v is String && v.trim().isNotEmpty) out.add(normalizeCategoryId(v));
    else if (v is Iterable) {
      for (final x in v) {
        final s = x?.toString() ?? '';
        if (s.trim().isNotEmpty) out.add(normalizeCategoryId(s));
      }
    } else if (v is Map) {
      for (final k in v.keys) {
        final s = k?.toString() ?? '';
        if (s.trim().isNotEmpty) out.add(normalizeCategoryId(s));
      }
    }
    return out;
  }

  static bool _anyOverlap(Set<String> a, Set<String> b) {
    if (a.intersection(b).isNotEmpty) return true;
    // Try hierarchical match both ways
    for (final x in a) {
      for (final y in b) {
        if (_hierarchicalMatch(x, y)) return true;
      }
    }
    return false;
  }

  static bool _hierarchicalMatch(String a, String b) {
    if (a == b) return true;
    if (a.isEmpty || b.isEmpty) return false;
    if (a.length > b.length) {
      return a.startsWith(b + '_');
    } else if (b.length > a.length) {
      return b.startsWith(a + '_');
    }
    return false;
  }

  static bool _anyHierarchical(Set<String> set, String id) {
    for (final x in set) {
      if (_hierarchicalMatch(x, id)) return true;
    }
    return false;
  }

  static String _readStatus(dynamic st) {
    if (st == null) return 'not_started';
    if (st is Map) {
      final v = (st['status'] ?? st['state'] ?? '').toString();
      if (_allowedStatuses.contains(v)) return v;
      return v.isNotEmpty ? v : 'not_started';
    }
    if (st is String && _allowedStatuses.contains(st)) return st;
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
