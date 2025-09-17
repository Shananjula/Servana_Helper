
// lib/app_init.dart
//
// One-liner you can call from your main() to ensure:
// - Firebase is initialized for the right Android Google Services config
// - App Check is active (Play Integrity)
// - Project info is logged so you can confirm the app targets the right Firebase project
//
// Usage from your existing main.dart:
// -----------------------------------------------------
// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   await initFirebaseAndAppCheck();
//   runApp(const MyApp()); // your app root
// }
// -----------------------------------------------------

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

Future<void> initFirebaseAndAppCheck() async {
  // Initialize Firebase using platform-specific default options
  await Firebase.initializeApp();

  // Activate App Check (Play Integrity on Android)
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.playIntegrity,
    // If you also ship iOS/web, you can set appleProvider/webProvider too.
  );

  // Log basic project info to confirm we're on the expected Firebase project
  final o = Firebase.app().options;
  debugPrint('[FB] projectId=${o.projectId} appId=${o.appId} apiKey=${o.apiKey}');
}
