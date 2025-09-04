
// lib/screens/verification_center_screen.dart
import 'package:flutter/material.dart';
import '../services/verification_service.dart';
import '../utils/verification_nav.dart';

class VerificationCenterScreen extends StatelessWidget {
  const VerificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verification Center')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Card(
              title: 'Online Verification',
              description: 'Select categories and upload skill proofs. No basic documents required.',
              onStart: () => VerificationNav.startOnline(context),
            ),
            const SizedBox(height: 16),
            _Card(
              title: 'Physical Verification',
              description: 'First time requires basic documents (NIC, selfie, police clearance), then category-specific proofs.',
              onStart: () => VerificationNav.startPhysical(context),
            ),
            const SizedBox(height: 24),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => VerificationNav.openStatus(context),
                icon: const Icon(Icons.history),
                label: const Text('View verification status'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String description;
  final VoidCallback onStart;
  const _Card({required this.title, required this.description, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: onStart,
                child: const Text('Start'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
