// lib/utils/log_service.dart
//
// Console-first logging with optional Firestore sink.
// Usage:
//   LogService.enabledFirestore = true;   // e.g. in main() after Firebase init
//   LogService.logInfo('live_toggle', where: 'helper_dashboard');
//   LogService.logError('upload_failed', where: 'proofs_panel', error: e, stack: st);

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class LogService {
  static bool enabledFirestore = false;
  static String collectionPath = 'client_logs';

  static Future<void> logInfo(String name, {String? where, Map<String, dynamic>? extra}) async {
    _print('INFO', name, where, extra);
    if (!enabledFirestore) return;
    await _write('info', name, where, extra, null);
  }

  static Future<void> logWarn(String name, {String? where, Map<String, dynamic>? extra}) async {
    _print('WARN', name, where, extra);
    if (!enabledFirestore) return;
    await _write('warn', name, where, extra, null);
  }

  static Future<void> logError(String name, {String? where, Object? error, StackTrace? stack, Map<String, dynamic>? extra}) async {
    _print('ERROR', name, where, extra, error, stack);
    if (!enabledFirestore) return;
    await _write('error', name, where, {
      ...?extra,
      if (error != null) 'error': error.toString(),
      if (stack != null) 'stack': stack.toString(),
    }, error);
  }

  // --------------- internal ---------------

  static void _print(String level, String name, String? where, Map<String, dynamic>? extra, [Object? error, StackTrace? stack]) {
    if (!kReleaseMode) {
      // ignore: avoid_print
      print('[log][$level] $name'
          '${where != null ? ' @ $where' : ''}'
          '${extra != null ? ' ${extra.toString()}' : ''}'
          '${error != null ? ' err=$error' : ''}'
      );
      if (stack != null) {
        // ignore: avoid_print
        print(stack);
      }
    }
  }

  static Future<void> _write(String level, String name, String? where, Map<String, dynamic>? extra, Object? error) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance.collection(collectionPath).add({
        'level': level,
        'name': name,
        'where': where,
        'extra': extra,
        'uid': uid,
        'platform': defaultTargetPlatform.toString(),
        'release': kReleaseMode,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // never crash on logging
    }
  }
}
