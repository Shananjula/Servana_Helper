import 'package:flutter/material.dart';
import '../services/verification_service.dart';
import '../screens/step_1_services.dart';
import '../screens/verification_progress_screen.dart'; // <— add
// import '../screens/verification_status_screen.dart'; // old

class VerificationNav {
  static Future<void> startOnline(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const Step1Services(mode: VerificationMode.online)),
    );
  }

  static Future<void> startPhysical(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const Step1Services(mode: VerificationMode.physical)),
    );
  }

  // New progress screen (replaces the old status screen)
  static Future<void> openProgress(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VerificationProgressScreen()),
    );
  }

  // Back-compat alias
  static Future<void> openStatus(BuildContext context) => openProgress(context);
}
