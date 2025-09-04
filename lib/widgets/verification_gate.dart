// lib/widgets/verification_gate.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class VerificationGate extends StatelessWidget {
  final String categoryId;
  final Widget child;
  final VoidCallback? onRequestVerification;

  const VerificationGate({
    super.key,
    required this.categoryId,
    required this.child,
    this.onRequestVerification,
  });

  // Legacy compat: some screens call this after login.
  static Future<void> ensurePostLogin(BuildContext context) async {
    // no-op by default; hook navigation here if you want.
    return;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('Please sign in'));
    }
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final allowed = (data?['allowedCategoryIds'] is List)
            ? List<String>.from(data!['allowedCategoryIds'])
            : <String>[];
        final isAllowed = allowed.contains(categoryId);
        if (isAllowed) return child;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_user_outlined, size: 48),
              const SizedBox(height: 8),
              const Text('Verification required for this category'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: onRequestVerification,
                child: const Text('Start verification'),
              ),
            ],
          ),
        );
      },
    );
  }
}
