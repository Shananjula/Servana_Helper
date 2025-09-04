// lib/utils/safe_firestore.dart
//
// Minimal, dependency-free Firestore helper with retry/backoff.
// - SafeFirestore.setMerge('tasks', id, {...});
// - SafeFirestore.update('tasks', id, {...});
// - SafeFirestore.arrayUnion('tasks', id, 'proofUrls', [url]);
// - SafeFirestore.arrayRemove('tasks', id, 'proofUrls', [url]);
//
// On failure, logs to LogService (console + Firestore if enabled).

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:servana/utils/log_service.dart';

typedef _Op = Future<void> Function();

class SafeFirestore {
  static const int _maxRetries = 3;

  static Future<void> setMerge(String coll, String docId, Map<String, dynamic> data) {
    return _runWithRetry(() async {
      await FirebaseFirestore.instance.collection(coll).doc(docId).set(
        data,
        SetOptions(merge: true),
      );
    }, where: 'setMerge($coll/$docId)');
  }

  static Future<void> update(String coll, String docId, Map<String, dynamic> data) {
    return _runWithRetry(() async {
      await FirebaseFirestore.instance.collection(coll).doc(docId).update(data);
    }, where: 'update($coll/$docId)');
  }

  static Future<void> arrayUnion(String coll, String docId, String field, List<dynamic> values) {
    return setMerge(coll, docId, {field: FieldValue.arrayUnion(values), 'updatedAt': FieldValue.serverTimestamp()});
  }

  static Future<void> arrayRemove(String coll, String docId, String field, List<dynamic> values) {
    return setMerge(coll, docId, {field: FieldValue.arrayRemove(values), 'updatedAt': FieldValue.serverTimestamp()});
  }

  // ---------------- internal ----------------

  static Future<void> _runWithRetry(_Op op, {required String where}) async {
    int attempt = 0;
    while (true) {
      try {
        await op();
        return;
      } catch (e, st) {
        attempt++;
        // Log on every failure (with attempt)
        LogService.logError('firestore_op_failed', where: '$where (#$attempt)', error: e, stack: st);
        if (attempt >= _maxRetries) rethrow;
        // Exponential backoff with jitter
        final delayMs = (200 * attempt) + (kDebugMode ? 0 : 50 * attempt);
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
  }
}
