
// lib/services/eligibility_service.dart — v6 (token-bag matching)
// - No basic-docs gating.
// - Unlock if category is in allowedCategoryIds OR verifiedCategories.
// - Tolerant ID matching including order-insensitive "token bags" so
//   "physical_tutor_home" matches "home_tutoring_physical".

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

@visibleForTesting
String normalizeCategoryId(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');

final Set<String> _modeTokens = {'physical','online','on','site','on_site','onsite'};

List<String> _stemTokens(String s) {
  final base = normalizeCategoryId(s);
  final parts = base.split('_').where((t) => t.isNotEmpty).toList();
  return parts.map((t) {
    // merge on+site variants
    if (t == 'on' || t == 'site') return 'on_site';
    // cheap stemmer: drop common suffixes
    var w = t;
    if (w.endsWith('ing') && w.length > 5) w = w.substring(0, w.length - 3);
    else if (w.endsWith('ers') && w.length > 5) w = w.substring(0, w.length - 3);
    else if (w.endsWith('es') && w.length > 4) w = w.substring(0, w.length - 2);
    else if (w.endsWith('s') && w.length > 3) w = w.substring(0, w.length - 1);
    if (w == 'tuition') w = 'tutor'; // common synonym
    return w;
  }).toList();
}

Set<String> _tokenBag(String s, {bool dropMode = true}) {
  final toks = _stemTokens(s);
  final Set<String> bag = {};
  for (final t in toks) {
    if (dropMode && (_modeTokens.contains(t))) continue;
    bag.add(t);
  }
  return bag;
}

bool _bagSimilar(String a, String b) {
  final A = _tokenBag(a);
  final B = _tokenBag(b);
  if (A.isEmpty || B.isEmpty) return false;
  // Require that all non-mode tokens in A are in B (and vice versa) for strong match
  return A.containsAll(B) && B.containsAll(A);
}

Iterable<String> synonymsFor(String base, {bool? isPhysical}) sync* {
  final b = normalizeCategoryId(base);
  yield b;
  for (final s in ['${b}_physical','${b}_online','${b}_on_site','${b}_onsite',
                   'physical__$b','online__$b','on_site__$b','onsite__$b']) {
    yield s;
  }
  if (isPhysical == true) for (final s in ['${b}_physical','physical__$b','${b}_on_site','on_site__$b','${b}_onsite','onsite__$b']) yield s;
  if (isPhysical == false) for (final s in ['${b}_online','online__$b']) yield s;
}

bool _allowedContains(List<String> allowed, String categoryId, {bool? isPhysical}) {
  final canonAllowed = allowed.map(normalizeCategoryId).toList();
  for (final s in synonymsFor(categoryId, isPhysical: isPhysical)) {
    final cs = normalizeCategoryId(s);
    if (canonAllowed.contains(cs)) return true;
    // bag-of-words fallback
    for (final a in canonAllowed) {
      if (_bagSimilar(a, cs)) return true;
    }
  }
  // also try the direct bag match against original category id
  for (final a in canonAllowed) {
    if (_bagSimilar(a, categoryId)) return true;
  }
  return false;
}

bool _isVerifiedFor(Map<String, dynamic> verifiedMap, String categoryId, {bool? isPhysical}) {
  if (verifiedMap.isEmpty) return false;
  // normalize keys
  final Map<String, dynamic> canon = {
    for (final e in verifiedMap.entries) normalizeCategoryId(e.key): e.value
  };
  // try synonyms and bag matches
  bool _keyHit(String key) {
    final v = canon[key];
    final status = _readStatus(v);
    return status == 'verified';
  }
  for (final s in synonymsFor(categoryId, isPhysical: isPhysical)) {
    final key = normalizeCategoryId(s);
    if (canon.containsKey(key) && _keyHit(key)) return true;
  }
  for (final key in canon.keys) {
    if (_bagSimilar(key, categoryId) && _keyHit(key)) return true;
  }
  return false;
}

class CategoryEligibility {
  const CategoryEligibility({
    required this.categoryId,
    required this.isRegistered,
    required this.status,
    required this.isAllowed,
    this.reason,
    this.notes,
    this.verifiedAt,
    this.submittedAt,
  });

  final String categoryId;
  final bool isRegistered;
  final String status;
  final bool isAllowed;
  final String? reason;
  final String? notes;
  final DateTime? verifiedAt;
  final DateTime? submittedAt;

  bool get canSeeTasks => isRegistered;
  bool get canMakeOffer => isAllowed;
}

class EligibilityService {
  EligibilityService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  String? get _uid => _auth.currentUser?.uid;

  Future<CategoryEligibility> checkHelperEligibility(String rawCategoryIdOrLabel) async {
    final uid = _uid;
    final catId = normalizeCategoryId(rawCategoryIdOrLabel);
    if (uid == null) {
      return CategoryEligibility(categoryId: catId, isRegistered: false, status: 'not_started', isAllowed: false, reason: 'not_signed_in');
    }
    final user = await _readUser(uid);
    final registered = _asStringList(user['registeredCategories']);
    final allowed    = _asStringList(user['allowedCategoryIds']);
    final verifiedMap = _asMap(user['verifiedCategories']);
    final status = _readStatus(verifiedMap[catId]);
    final isReg = registered.contains(catId);
    final allowHit  = _allowedContains(allowed, catId);
    final verifyHit = _isVerifiedFor(verifiedMap, catId);
    if (kDebugMode) { print('[elig] cat=$catId reg=$isReg allowHit=$allowHit verifyHit=$verifyHit allowed=$allowed verifiedKeys=${verifiedMap.keys}'); }
    final meta = await _readProofMeta(uid, catId);
    return CategoryEligibility(categoryId: catId, isRegistered: isReg, status: status, isAllowed: allowHit || verifyHit, reason: (allowHit||verifyHit)?null:'not_allowed', notes: meta.notes, submittedAt: meta.submittedAt, verifiedAt: meta.verifiedAt);
  }

  Future<CategoryEligibility> checkHelperEligibilityForTask(dynamic taskLike) async {
    final uid = _uid;
    final t = _taskMap(taskLike);
    final catId = _taskCategoryId(t);
    final isPhysical = _taskIsPhysical(t);
    if (uid == null) {
      return CategoryEligibility(categoryId: catId, isRegistered: false, status: 'not_started', isAllowed: false, reason: 'not_signed_in');
    }
    final user = await _readUser(uid);
    final registered = _asStringList(user['registeredCategories']);
    final allowed    = _asStringList(user['allowedCategoryIds']);
    final verifiedMap = _asMap(user['verifiedCategories']);
    final status = _readStatus(verifiedMap[catId]);
    final isReg = registered.contains(catId);
    final allowHit  = _allowedContains(allowed, catId, isPhysical: isPhysical);
    final verifyHit = _isVerifiedFor(verifiedMap, catId, isPhysical: isPhysical);
    if (kDebugMode) { print('[eligForTask] cat=$catId physical=$isPhysical reg=$isReg allowHit=$allowHit verifyHit=$verifyHit allowed=$allowed verifiedKeys=${verifiedMap.keys}'); }
    final meta = await _readProofMeta(uid, catId);
    return CategoryEligibility(categoryId: catId, isRegistered: isReg, status: status, isAllowed: allowHit || verifyHit, reason: (allowHit||verifyHit)?null:'not_allowed', notes: meta.notes, submittedAt: meta.submittedAt, verifiedAt: meta.verifiedAt);
  }

  Stream<CategoryEligibility> watchEligibility(String rawCategoryIdOrLabel) async* {
    final uid = _uid;
    final categoryId = normalizeCategoryId(rawCategoryIdOrLabel);
    if (uid == null) {
      yield CategoryEligibility(categoryId: categoryId, isRegistered: false, status: 'not_started', isAllowed: false, reason: 'not_signed_in');
      return;
    }
    final userDocRef = _db.collection('users').doc(uid);
    final proofDocRef = _db.collection('category_proofs').doc('${uid}_$categoryId');
    Map<String, dynamic>? lastUser;
    Map<String, dynamic>? lastProof;
    CategoryEligibility _compute() {
      final user = lastUser ?? const <String, dynamic>{};
      final registered = _asStringList(user['registeredCategories']);
      final allowed    = _asStringList(user['allowedCategoryIds']);
      final verifiedMap = _asMap(user['verifiedCategories']);
      final isReg = registered.contains(categoryId);
      final status = _readStatus(verifiedMap[categoryId]);
      final allowHit  = _allowedContains(allowed, categoryId);
      final verifyHit = _isVerifiedFor(verifiedMap, categoryId);
      String? notes; DateTime? submittedAt, verifiedAt;
      if (lastProof != null) {
        submittedAt = _toDate(lastProof!['submittedAt']);
        verifiedAt  = _toDate(lastProof!['verifiedAt']);
        final rawNote = (lastProof!['notes'] ?? '').toString().trim();
        notes = rawNote.isEmpty ? null : rawNote;
      }
      if (kDebugMode) { print('[eligWatch] cat=$categoryId reg=$isReg allowHit=$allowHit verifyHit=$verifyHit allowed=$allowed verifiedKeys=${verifiedMap.keys}'); }
      return CategoryEligibility(categoryId: categoryId, isRegistered: isReg, status: status, isAllowed: allowHit || verifyHit, reason: (allowHit||verifyHit)?null:'not_allowed', notes: notes, submittedAt: submittedAt, verifiedAt: verifiedAt);
    }
    yield* Stream.multi((controller) {
      StreamSubscription? a; StreamSubscription? b;
      void emit() { try { controller.add(_compute()); } catch (e, st) { controller.addError(e, st); } }
      a = userDocRef.snapshots().listen((snap) { lastUser = snap.data() as Map<String, dynamic>?; emit(); }, onError: controller.addError);
      b = proofDocRef.snapshots().listen((snap) { lastProof = snap.data() as Map<String, dynamic>?; emit(); }, onError: (_) {});
      controller.onCancel = () async { await a?.cancel(); await b?.cancel(); };
    });
  }

  // helpers
  Future<Map<String, dynamic>> _readUser(String uid) async { final snap = await _db.collection('users').doc(uid).get(); return snap.data() ?? <String, dynamic>{}; }
  Map<String, dynamic> _asMap(dynamic v) { if (v is Map) return Map<String, dynamic>.from(v); return const <String, dynamic>{}; }
  Future<_ProofMeta> _readProofMeta(String uid, String categoryId) async {
    try { final s = await _db.collection('category_proofs').doc('${uid}_$categoryId').get(); if (s.exists) { final p = s.data() ?? <String, dynamic>{}; return _ProofMeta(submittedAt:_toDate(p['submittedAt']), verifiedAt:_toDate(p['verifiedAt']), notes:(p['notes']??'').toString().trim().isEmpty?null:(p['notes'] as String)); } }
    catch (_) {}
    return const _ProofMeta();
  }
  Map<String, dynamic> _taskMap(dynamic t) { if (t is DocumentSnapshot) { final d=t.data(); if (d is Map<String,dynamic>) return d; return <String,dynamic>{}; } if (t is Map<String,dynamic>) return t; return <String,dynamic>{}; }
  String _taskCategoryId(Map<String, dynamic> t) { final raw = t['mainCategoryId'] ?? t['categoryId'] ?? t['category_id'] ?? t['mainCategory'] ?? t['mainCategoryLabel'] ?? t['category']; if (raw==null) return ''; return normalizeCategoryId(raw.toString()); }
  bool _taskIsPhysical(Map<String, dynamic> t) { final v=t['isPhysical']??t['physical']??t['is_physical']; if (v is bool) return v; final mode=(t['mode']??t['taskMode']??t['categoryMode']??t['type']??'').toString().toLowerCase(); return mode=='physical' || mode=='onsite' || mode=='on_site'; }
  List<String> _asStringList(dynamic v) { if (v is Iterable) return v.map((e)=>normalizeCategoryId(e.toString())).toList(); return const <String>[]; }
  DateTime? _toDate(dynamic ts) { if (ts is Timestamp) return ts.toDate(); if (ts is DateTime) return ts; if (ts==null) return null; try { final i=int.parse(ts.toString()); return DateTime.fromMillisecondsSinceEpoch(i);} catch(_){ } return null; }
}

// normalize review statuses; "approved" ≡ "verified".
String _readStatus(dynamic v) {
  String s; if (v is Map) s=(v['status']??'not_started').toString(); else s=(v??'not_started').toString();
  s=s.trim().toLowerCase(); if (s=='approved') return 'verified';
  const allowed={'not_started','pending','processing','needs_more_info','verified','rejected','submitted'};
  return allowed.contains(s)?s:'not_started';
}

class _ProofMeta { const _ProofMeta({this.submittedAt,this.verifiedAt,this.notes}); final DateTime? submittedAt; final DateTime? verifiedAt; final String? notes; }
