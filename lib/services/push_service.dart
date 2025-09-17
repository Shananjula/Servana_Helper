import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try { await Firebase.initializeApp(); } catch (_) {}
  if (kDebugMode) print('[FCM][BG] ${message.messageId} data=${message.data}');
}

class PushService {
  PushService._();
  static final instance = PushService._();

  final _msg = FirebaseMessaging.instance;
  final _auth = FirebaseAuth.instance;
  Stream<String>? _tokenStream;

  Future<void> initForCurrentUser({required String appRole}) async {
    // Ask permission (Android 13+/iOS)
    await _msg.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Save token now and on refresh
    await _register(appRole: appRole);
    _tokenStream ??= _msg.onTokenRefresh;
    _tokenStream!.listen((t) => _save(t, appRole: appRole));

    // Optional: log foreground messages
    FirebaseMessaging.onMessage.listen((m) {
      if (kDebugMode) {
        print('[FCM][FG] ${m.notification?.title} | ${m.notification?.body} | ${m.data}');
      }
    });
  }

  Future<void> _register({required String appRole}) async {
    final t = await _msg.getToken();
    if (t != null) await _save(t, appRole: appRole);
  }

  Future<void> _save(String token, {required String appRole}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance.doc('users/$uid');
    await ref.set({
      'fcmTokens': { token: true }, // map form makes server pruning easy
      'fcmMeta': {
        token: {
          'role': appRole,
          'platform': Platform.isAndroid ? 'android' : Platform.isIOS ? 'ios' : 'other',
          'updatedAt': FieldValue.serverTimestamp(),
        }
      },
      'lastTokenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> detach() async {
    final uid = _auth.currentUser?.uid;
    final t = await _msg.getToken();
    if (uid == null || t == null) return;
    await FirebaseFirestore.instance.doc('users/$uid').set({
      'fcmTokens': { t: FieldValue.delete() },
      'fcmMeta': { t: FieldValue.delete() },
    }, SetOptions(merge: true));
  }
}

