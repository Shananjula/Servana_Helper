// lib/services/user_gate_service.dart (v3)
//
// Fixes:
// 1) Listens to ALL docs under users/{uid}/categoryEligibility (no query filter),
//    then matches status case-insensitively ('approved', 'Approved', 'APPROVED', etc.).
// 2) If any approved category is missing from users/{uid}.allowedCategoryIds,
//    calls the callable to recompute (one-time backfill for legacy users).
// 3) Keeps the same Offer gating API.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart'; // FlutterFire

class UserGateService extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _funcs = FirebaseFunctions.instance;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _eligSub;
  StreamSubscription<User?>? _authSub;

  String? _uid;
  bool _loaded = false;
  Set<String> _allowed = <String>{};
  final Map<String, String> _elig = <String, String>{}; // catId -> status

  UserGateService() {
    _authSub = _auth.userChanges().listen((u) {
      _uid = u?.uid;
      _teardownStreams();
      if (_uid == null) {
        _allowed = <String>{};
        _loaded = true;
        notifyListeners();
        return;
      }
      _userSub = _db.doc('users/${_uid!}').snapshots().listen(_onUserDoc, onError: (e, st) {
        debugPrint('[UserGate] user doc stream error: $e');
      });
      // ⚠️ Listen to the whole subcollection to avoid case issues
      _eligSub = _db.collection('users/${_uid!}/categoryEligibility')
          .snapshots()
          .listen(_onEligSnapshot, onError: (e, st) {
        debugPrint('[UserGate] elig stream error: $e');
      });
    });
  }

  void _onUserDoc(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? const <String, dynamic>{};
    final raw = data['allowedCategoryIds'];
    final next = <String>{};
    if (raw is List) {
      for (final v in raw) {
        if (v == null) continue;
        next.add(_canon(v.toString()));
      }
    }
    _allowed = next;
    _loaded = true;
    notifyListeners();
  }

  Future<void> _onEligSnapshot(QuerySnapshot<Map<String, dynamic>> q) async {
    bool needRecompute = false;
    for (final doc in q.docs) {
      final catId = _canon(doc.id);
      final status = ((doc.data()['status'] ?? '') as String).toLowerCase().trim();
      _elig[catId] = status;
      if (status == 'approved' && !_allowed.contains(catId)) {
        needRecompute = true;
      }
    }
    if (needRecompute) {
      await _requestRecomputeAllowed();
    }
    notifyListeners();
  }

  Future<void> _requestRecomputeAllowed() async {
    try {
      final call = _funcs.httpsCallable('recomputeAllowedForUser');
      await call.call(<String, dynamic>{ 'uid': _uid });
      debugPrint('[UserGate] recomputeAllowedForUser requested');
    } catch (e) {
      debugPrint('[UserGate] recomputeAllowedForUser failed: $e');
    }
  }

  bool get ready => _loaded;
  Set<String> get allowedCategoryIds => _allowed;

  bool canOfferForTask(Map<String, dynamic> task) {
    if (!_loaded) return false;
    final status = (task['status'] ?? 'open').toString().toLowerCase();
    const offerable = {'open', 'listed', 'negotiating', 'negotiation'};
    if (!offerable.contains(status)) return false;

    final ids = _extractTaskCategoryIds(task);
    if (ids.isEmpty) return false;

    for (final id in ids) {
      if (_allowed.contains(id)) return true;
    }
    return false;
  }

  Set<String> _extractTaskCategoryIds(Map<String, dynamic> t) {
    final out = <String>{};

    String? _pickId(List<String> keys) {
      for (final k in keys) {
        final v = t[k];
        if (v == null) continue;
        if (v is String && v.trim().isNotEmpty) return v;
        if (v is Map && v['id'] is String && (v['id'] as String).trim().isNotEmpty) {
          return v['id'] as String;
        }
        if (v is Map && v['slug'] is String && (v['slug'] as String).trim().isNotEmpty) {
          return v['slug'] as String;
        }
      }
      return null;
    }

    const primaryKeys = [
      'categoryId', 'mainCategoryId', 'primaryCategoryId',
      'category_id', 'main_category_id',
      'category', 'mainCategory', 'categorySlug',
    ];
    final p = _pickId(primaryKeys);
    if (p != null) out.add(_canon(p));

    // If your tasks only store labels, try to canonicalize the label field too.
    final labelKeys = ['mainCategoryLabel', 'categoryLabel', 'mainCategoryLabelOrId', 'category_name'];
    for (final k in labelKeys) {
      final v = t[k];
      if (v is String && v.trim().isNotEmpty) out.add(_canon(v));
      if (v is Map && v['label'] is String && (v['label'] as String).trim().isNotEmpty) out.add(_canon(v['label'] as String));
    }

    // Lists
    const listKeys = ['categoryIds', 'categories', 'tagIds', 'mainTagIds'];
    for (final k in listKeys) {
      final v = t[k];
      if (v is List) {
        for (final e in v) {
          if (e == null) continue;
          if (e is String) out.add(_canon(e));
          else if (e is Map) {
            if (e['id'] is String) out.add(_canon(e['id'] as String));
            if (e['slug'] is String) out.add(_canon(e['slug'] as String));
            if (e['label'] is String) out.add(_canon(e['label'] as String));
          }
        }
      }
    }
    return out;
  }

  String _canon(String s) {
    final x = s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return x.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  @override
  void dispose() {
    _teardownStreams();
    super.dispose();
  }

  void _teardownStreams() {
    _userSub?.cancel();
    _eligSub?.cancel();
    _authSub?.cancel();
    _userSub = null;
    _eligSub = null;
    _authSub = null;
  }
}