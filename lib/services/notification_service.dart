// lib/services/notification_service.dart
//
// FCM + deep-links for helper app. Exposes NotificationService.navigatorKey
// so your main.dart line `NotificationService.navigatorKey` works.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:servana/screens/helper_active_task_screen.dart';
import 'package:servana/screens/top_up_screen.dart';
import 'package:servana/screens/conversation_screen.dart';
import 'package:servana/screens/task_details_screen.dart';
import 'package:servana/screens/verification_center_screen.dart';
import 'package:servana/screens/step_2_documents.dart' as step2;

// Global navigator key (actual instance)
final GlobalKey<NavigatorState> _appNavigatorKey = GlobalKey<NavigatorState>();

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  // Static getter so main.dart can use NotificationService.navigatorKey
  static GlobalKey<NavigatorState> get navigatorKey => _appNavigatorKey;

  StreamSubscription<String?>? _tokenSub;

  Future<void> requestPermission() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true, badge: true, sound: true,
    );
  }

  Future<void> initNotifications() async {
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
    await requestPermission();

    FirebaseMessaging.onMessage.listen(_onMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handle(initial.data, opened: true);

    _tokenSub?.cancel();
    _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((_) => _syncToken());
    await _syncToken();
  }

  Future<void> _syncToken() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final t = await FirebaseMessaging.instance.getToken();
      if (t == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([t]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await FirebaseMessaging.instance.subscribeToTopic('user_$uid');
    } catch (_) {}
  }

  void _onMessage(RemoteMessage msg) {
    _handle(msg.data);
    final ctx = _appNavigatorKey.currentState?.context;
    if (ctx != null) {
      final title = msg.data['title'] ?? 'Notification';
      final body = msg.data['body'] ?? '';
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(body.isEmpty ? title : '$title — $body'),
          action: SnackBarAction(
            label: 'OPEN',
            onPressed: () => _handle(msg.data, opened: true),
          ),
        ),
      );
    }
  }

  void _onOpened(RemoteMessage msg) => _handle(msg.data, opened: true);

  void _handle(Map<String, dynamic> data, {bool opened = false}) {
    final type = data['type'] ?? '';
    final taskId = data['taskId'] as String?;
    final offerId = data['offerId'] as String?;
    final channelId = data['channelId'] as String?;
    final ctx = _appNavigatorKey.currentState?.context;
    if (ctx == null) return;

    switch (type) {
      case 'chat':
        if (channelId != null) {
          Navigator.push(ctx, MaterialPageRoute(builder: (_) => ConversationScreen(channelId: channelId)));
        }
        break;
      case 'offer':
        final body = (data['body'] ?? '').toString().toLowerCase();
        if ((body.contains('approved') || body.contains('assigned')) && taskId != null) {
          // old:
          // Navigator.push(ctx, MaterialPageRoute(builder: (_) => HelperActiveTaskScreen(taskId: taskId)));

          // new (constructor takes no args in your project):
          Navigator.push(ctx, MaterialPageRoute(builder: (_) => const HelperActiveTaskScreen()));
        } else if (body.contains('top up')) {
          Navigator.push(ctx, MaterialPageRoute(builder: (_) => const TopUpScreen()));
        } else if (taskId != null) {
          Navigator.push(ctx, MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: taskId)));
        }
        break;
      case 'task':
        if (taskId != null) {
          Navigator.push(ctx, MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: taskId)));
        }
        break;
      case 'verification_update':
      case 'verification_approved':
      case 'verification_rejected':
        {
          final relatedId = (data['relatedId'] ?? '').toString();
          if (relatedId.isNotEmpty) {
            Navigator.push(ctx, MaterialPageRoute(builder: (_) => step2.Step2Documents(initialCategoryId: relatedId)));
          } else {
            Navigator.push(ctx, MaterialPageRoute(builder: (_) => const VerificationCenterScreen()));
          }
        }
        break;
      default:
        break;
    }
  }

  Future<void> dispose() async {
    await _tokenSub?.cancel();
    _tokenSub = null;
  }
}
