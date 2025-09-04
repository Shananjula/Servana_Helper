// lib/utils/analytics.dart
//
// Minimal analytics helper.
// - Works out-of-the-box with no backend (logs to console in debug)
// - Optional Firestore logging when `enableFirestore = true`
// - Call Analytics.log('event_name', params: {...});
//
// Usage:
//   import 'package:servana/utils/analytics.dart';
//   Analytics.log('offer_sent', params: {'taskId': taskId, 'amount': price});
//
// Optional (after Firebase.initializeApp):
//   Analytics.enableFirestore = true; // to write events into Firestore

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Analytics {
  /// When true, events are also written to Firestore (see [collectionPath]).
  /// Default: false (console only in debug).
  static bool enableFirestore = false;

  /// Collection to write events into when [enableFirestore] is true.
  static String collectionPath = 'analytics_events';

  /// Max string length per param to avoid huge payloads.
  static const int _maxLen = 300;

  /// Log an analytics event.
  ///
  /// [name] should be snake_case, e.g. 'offer_sent'.
  /// [params] should be small, serializable values (num/bool/String).
  static Future<void> log(String name, {Map<String, dynamic>? params}) async {
    final now = DateTime.now();
    final event = <String, dynamic>{
      'name': _sanitizeKey(name),
      'params': _sanitizeParams(params),
      'ts': now.toIso8601String(),
      'release': kReleaseMode,
      'platform': defaultTargetPlatform.toString(), // e.g. TargetPlatform.android
    };

    // Always log to console in debug for quick visibility.
    if (!kReleaseMode) {
      // ignore: avoid_print
      print('[analytics] ${event['name']} ${event['params']}');
    }

    if (!enableFirestore) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance.collection(collectionPath).add({
        ...event,
        'uid': uid,
        'serverTs': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Swallow errors; analytics must never crash the app.
    }
  }

  /// Optionally set a user property (stored as a lightweight doc).
  /// Only used when [enableFirestore] is true.
  static Future<void> setUserProperty(String key, String value) async {
    if (!enableFirestore) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance
          .collection(collectionPath)
          .doc('_user_$uid')
          .set({
        'uid': uid,
        'userProps': {
          _sanitizeKey(key): _truncate(value),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {/* no-op */}
  }

  // ---------------- internal helpers ----------------

  static String _sanitizeKey(String key) {
    final k = key.trim().toLowerCase();
    // convert spaces to underscores, keep simple ascii keys.
    return k.replaceAll(RegExp(r'\s+'), '_').replaceAll(RegExp(r'[^a-z0-9_\.]'), '');
  }

  static Map<String, dynamic> _sanitizeParams(Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) return const {};
    final out = <String, dynamic>{};
    params.forEach((k, v) {
      out[_sanitizeKey(k)] = _toPrimitive(v);
    });
    return out;
  }

  static dynamic _toPrimitive(dynamic v) {
    if (v == null) return null;
    if (v is num || v is bool) return v;
    if (v is DateTime) return v.toIso8601String();
    if (v is Iterable) {
      // limit array size to 15 and map to primitives
      return v.take(15).map(_toPrimitive).toList();
    }
    if (v is Map) {
      // flatten one level and sanitize keys
      final m = <String, dynamic>{};
      v.entries.take(20).forEach((e) {
        m[_sanitizeKey(e.key.toString())] = _toPrimitive(e.value);
      });
      return m;
    }
    // Fallback to string with truncation
    return _truncate(v.toString());
  }

  static String _truncate(String s) {
    if (s.length <= _maxLen) return s;
    return s.substring(0, _maxLen);
  }
}
