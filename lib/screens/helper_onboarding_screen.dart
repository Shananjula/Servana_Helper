// lib/screens/helper_onboarding_screen.dart
//
// Backward-compatible wrapper.
// Anywhere that previously navigated to HelperOnboardingScreen now lands on
// the consolidated VerificationCenterScreen (steps + status).

import 'package:flutter/material.dart';
import 'package:servana/screens/verification_center_screen.dart';

class HelperOnboardingScreen extends StatelessWidget {
  const HelperOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const VerificationCenterScreen();
  }
}
