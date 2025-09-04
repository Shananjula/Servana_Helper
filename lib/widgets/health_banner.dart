import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HealthBanner extends StatelessWidget {
  const HealthBanner({super.key, required this.error, this.message});

  final Object error;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String title = 'Something went wrong';
    String body  = message ?? 'Please try again.';

    if (error is FirebaseException) {
      final fe = error as FirebaseException;
      if (fe.code == 'permission-denied') {
        title = 'Missing permissions';
        body  = 'This data is not available for your account. If this seems wrong, sign out and sign in again, or contact support.';
      } else if (fe.code == 'failed-precondition') {
        title = 'Index not ready';
        body  = 'We’re building a search index. It usually completes in a minute.';
      }
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(body, style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
