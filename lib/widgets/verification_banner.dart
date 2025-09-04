// lib/widgets/verification_banner.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:servana/providers/user_provider.dart';
import '../screens/step_2_documents.dart';

/// A persistent, dismissible top banner prompting a new helper to finish verification.
/// Shows only when:
/// - app is in helper mode (if helperOnly=true)
/// - user is signed in
/// - allowedCategoryIds is empty or missing
class VerificationBanner extends StatefulWidget {
  const VerificationBanner({super.key, this.helperOnly = true});
  final bool helperOnly;

  @override
  State<VerificationBanner> createState() => _VerificationBannerState();
}

class _VerificationBannerState extends State<VerificationBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final isHelperMode = context.read<UserProvider>().isHelperMode;
    if (widget.helperOnly && !isHelperMode) return const SizedBox.shrink();
    if (_dismissed) return const SizedBox.shrink();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final data = snap.data!.data() ?? {};
        final list = data['allowedCategoryIds'];
        final allowed = (list is List) ? list.whereType<dynamic>().map((e) => e.toString()).toList() : const <String>[];

        if (allowed.isNotEmpty) return const SizedBox.shrink();

        // Render a top-of-screen banner
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 6))],
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_rounded, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Finish verification to unlock tasks', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        'Physical categories need basic documents + a category proof. '
                        'Online categories need only a skill proof.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Step2Documents()));
                  },
                  child: const Text('Verify now'),
                ),
                IconButton(
                  onPressed: () => setState(() => _dismissed = true),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Dismiss',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
