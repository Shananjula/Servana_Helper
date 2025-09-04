// lib/screens/profile_screen.dart
//
// Role switch lives HERE (and only here), gated by verification.
// - Reads current user from Firestore: /users/{uid}
// - Shows profile header, verification status, and mode switch
// - Mode switch enabled only if user is approved/verified as a helper
// - Writes UI mode via UserProvider.setUiMode('poster'|'helper')
// - Optional "Go Live" switch when in Helper mode (wired to UserProvider.setLive)
// - Button to open Verification Center if not verified
//
// Additive, schema-tolerant, null-safe. Does not rename public classes.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:servana/screens/step_2_documents.dart' as step2;
import 'package:servana/screens/verification_center_screen.dart';
import 'package:provider/provider.dart';

import 'package:servana/providers/user_provider.dart';
import 'package:servana/screens/verification_center_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: Text('Please sign in to view your profile.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          final data = snap.data?.data() ?? const <String, dynamic>{};

          final displayName = (data['displayName'] as String?)?.trim();
          final phone = (data['phoneNumber'] as String?) ?? (data['phone'] as String?);
          final photoURL = (data['photoURL'] as String?) ?? (data['avatarUrl'] as String?);
          final verificationStatus = (data['verificationStatus'] as String?)?.toLowerCase() ?? 'unverified';
          final isHelper = data['isHelper'] == true; // server-side helper flag
          final trustScore = (data['trustScore'] as num?)?.toInt();

          final isVerified = verificationStatus.contains('verified');
          final canToggleMode = isHelper && isVerified;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _HeaderCard(
                name: displayName ?? 'User',
                phone: phone,
                photoURL: photoURL,
                trustScore: trustScore,
                verificationStatus: verificationStatus,
              ),
              const SizedBox(height: 12),
              _VerifyBanner(),

              const SizedBox(height: 16),

              _ModeCard(
                canToggle: canToggleMode,
                verificationStatus: verificationStatus,
                isHelperServerFlag: isHelper,
              ),

              const SizedBox(height: 16),

              // Live toggle only when user has switched UI to helper mode
              const _LiveToggleCard(),

              // You can add more profile sections below (wallet summary, referrals, etc.)
            ],
          );
        },
      ),
    );
  }
}

// -----------------------------
// Header
// -----------------------------
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.name,
    required this.phone,
    required this.photoURL,
    required this.trustScore,
    required this.verificationStatus,
  });

  final String name;
  final String? phone;
  final String? photoURL;
  final int? trustScore;
  final String verificationStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    String prettyStatus(String s) {
      final t = s.toLowerCase();
      if (t.contains('verified')) return 'Verified';
      if (t.contains('pending')) return 'Pending';
      if (t.contains('rejected')) return 'Rejected';
      return 'Unverified';
    }

    Color statusBg(String s) {
      final t = s.toLowerCase();
      if (t.contains('verified')) return cs.primary;
      if (t.contains('pending')) return const Color(0xFFFFA000); // amber
      if (t.contains('rejected')) return cs.error;
      return cs.surfaceVariant;
    }

    Color statusFg(String s) {
      final t = s.toLowerCase();
      if (t.contains('verified')) return cs.onPrimary;
      if (t.contains('pending')) return Colors.black;
      if (t.contains('rejected')) return cs.onError;
      return cs.onSurfaceVariant;
    }

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline.withOpacity(0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: cs.primary.withOpacity(0.12),
              backgroundImage: (photoURL != null && photoURL!.isNotEmpty) ? NetworkImage(photoURL!) : null,
              child: (photoURL == null || photoURL!.isEmpty)
                  ? Icon(Icons.person_rounded, size: 28, color: cs.primary)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DefaultTextStyle(
                style: theme.textTheme.bodyMedium!,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
                    ),
                    const SizedBox(height: 4),
                    if (phone != null && phone!.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.phone_rounded, size: 16),
                          const SizedBox(width: 6),
                          Text(phone!, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Pill(
                          label: prettyStatus(verificationStatus),
                          bg: statusBg(verificationStatus),
                          fg: statusFg(verificationStatus),
                        ),
                        if (trustScore != null)
                          _Pill(
                            label: 'Trust $trustScore',
                            bg: cs.tertiaryContainer,
                            fg: cs.onTertiaryContainer,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------
// Mode switch (Poster / Helper)
// -----------------------------
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.canToggle,
    required this.verificationStatus,
    required this.isHelperServerFlag,
  });

  final bool canToggle;
  final String verificationStatus;
  final bool isHelperServerFlag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final userProv = context.watch<UserProvider>();
    final isHelperMode = userProv.isHelperMode;

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline.withOpacity(0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('App mode', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'poster', label: Text('Poster'), icon: Icon(Icons.person_pin_circle_rounded)),
                ButtonSegment(value: 'helper', label: Text('Helper'), icon: Icon(Icons.volunteer_activism_rounded)),
              ],
              selected: {isHelperMode ? 'helper' : 'poster'},
              onSelectionChanged: canToggle
                  ? (s) => context.read<UserProvider>().setUiMode(s.first)
                  : null,
            ),
            const SizedBox(height: 8),
            if (!canToggle) _ModeLockedBanner(verificationStatus: verificationStatus, isHelperServerFlag: isHelperServerFlag),
          ],
        ),
      ),
    );
  }
}

class _ModeLockedBanner extends StatelessWidget {
  const _ModeLockedBanner({required this.verificationStatus, required this.isHelperServerFlag});
  final String verificationStatus;
  final bool isHelperServerFlag;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String message() {
      final v = verificationStatus.toLowerCase();
      if (!isHelperServerFlag) {
        return 'Become a helper to unlock Helper mode.';
      }
      if (v.contains('pending')) {
        return 'Verification pending. You can switch modes after approval.';
      }
      if (v.contains('rejected')) {
        return 'Verification was rejected. Fix your documents and resubmit.';
      }
      return 'You must be verified to switch to Helper mode.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationCenterScreen()));
          },
          icon: const Icon(Icons.verified_user_rounded),
          label: const Text('Open Verification Center'),
        ),
      ],
    );
  }
}

// -----------------------------
// Live toggle (Helper mode)
// -----------------------------
class _LiveToggleCard extends StatelessWidget {
  const _LiveToggleCard();

  @override
  Widget build(BuildContext context) {
    final userProv = context.watch<UserProvider>();
    final isHelperMode = userProv.isHelperMode;

    if (!isHelperMode) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline.withOpacity(0.12)),
      ),
      child: SwitchListTile.adaptive(
        title: const Text('Go Live'),
        subtitle: Text(
          userProv.isLive
              ? 'You are visible to posters nearby.'
              : 'Go live to auto-surface on maps and Smart Leads.',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        value: userProv.isLive,
        onChanged: (v) => context.read<UserProvider>().setLive(v),
        secondary: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.podcasts_rounded),
        ),
      ),
    );
  }
}

// -----------------------------
// Small pill
// -----------------------------
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.bg, required this.fg});
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

class _VerifyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final allowed = (data['allowedCategoryIds'] is List) ? List<String>.from(data['allowedCategoryIds']) : const <String>[];
        if (allowed.isNotEmpty) return const SizedBox.shrink(); // already verified for something

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.verified_user_rounded, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Finish verification to unlock tasks', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      'Physical: basic docs + category proof • Online: category proof only',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationCenterScreen()));
                },
                child: const Text('Open center'),
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const step2.Step2Documents()));
                },
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('Upload docs'),
              ),
            ],
          ),
        );
      },
    );
  }
}
