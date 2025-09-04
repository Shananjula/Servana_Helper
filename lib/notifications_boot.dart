// lib/notifications_boot.dart
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No UI here; keep light.
}

final FlutterLocalNotificationsPlugin _flnp = FlutterLocalNotificationsPlugin();

Future<void> initNotificationsBoot() async {
  // Android channel for lock-screen + heads-up
  const channel = AndroidNotificationChannel(
    'servana_general',
    'General Notifications',
    description: 'Alerts for tasks, chat, verification.',
    importance: Importance.max,
  );
  await _flnp
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // Ensure background handler is registered
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
}