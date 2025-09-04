// lib/screens/helper_profile_screen.dart
//
// Helper Profile (Phase 0)
// - Shows display name, phone, photo, verification status, rating stats
// - Quick actions: Edit Profile • Wallet • Verification Center • Settings
// - Links to Legal/About and Log out
// - Reads users/{uid} and wallets/{uid} (wallet is optional; WalletScreen shows history)
//
// Dependencies: cloud_firestore, firebase_auth, flutter/material.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:servana/screens/step_2_documents.dart' as step2;

// Destinations
import 'package:servana/screens/edit_profile_screen.dart';
import 'package:servana/screens/wallet_screen.dart';
import 'package:servana/screens/verification_center_screen.dart';
import 'package:servana/screens/settings_screen.dart';
import 'package:servana/screens/legal_screen.dart';
import 'package:servana/screens/top_up_screen.dart';
import 'package:servana/screens/notifications_screen.dart';

class HelperProfileScreen extends StatelessWidget {
  const HelperProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_rounded),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          ),
        ],
      ),
      body: uid == null
          ? const Center(child: Text('Please sign in to view your profile.'))
          : ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _HeaderCard(uid: uid),
          const SizedBox(height: 16),
          _QuickRow(
            onEditProfile: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
            ),
            onWallet: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WalletScreen()),
            ),
            onVerify: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VerificationCenterScreen()),
            ),
            onSettings: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(height: 20),
          Text('Account', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          _tile(
            context,
            icon: Icons.account_balance_wallet_rounded,
            title: 'Top up',
            subtitle: 'Add balance to your wallet',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TopUpScreen()),
            ),
          ),
          _tile(
            context,
            icon: Icons.verified_user_outlined,
            title: 'Verification Center',
            subtitle: 'ID & eligibility',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VerificationCenterScreen()),
            ),
          ),
          _tile(
            context,
            icon: Icons.settings_rounded,
            title: 'Settings',
            subtitle: 'Notifications, theme & language',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),

          const SizedBox(height: 16),
          Text('Help & legal', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          _tile(
            context,
            icon: Icons.gavel_outlined,
            title: 'Legal & terms',
            subtitle: 'Privacy policy and terms',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LegalScreen()),
            ),
          ),
          _tile(
            context,
            icon: Icons.info_outline,
            title: 'About Servana',
            subtitle: 'Version info',
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Servana',
              applicationVersion: '1.0.0',
              applicationLegalese: '© ${DateTime.now().year} Servana',
            ),
          ),

          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Log out'),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Signed out')),
                );
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context,
      {required IconData icon,
        required String title,
        String? subtitle,
        required VoidCallback onTap}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outline.withOpacity(0.12)),
        ),
        tileColor: cs.surface,
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subtitle == null ? null : Text(subtitle),
        onTap: onTap,
      ),
    );
  }
}

// ---------------- Header ----------------

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final userDoc = FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    final walletDoc = FirebaseFirestore.instance.collection('wallets').doc(uid).snapshots();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          const CircleAvatar(radius: 28, child: Icon(Icons.person)),
          const SizedBox(width: 12),
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: userDoc,
              builder: (context, snap) {
                final data = snap.data?.data() ?? const <String, dynamic>{};
                final name = (data['displayName'] ?? '').toString().trim();
                final phone = (data['phone'] ?? FirebaseAuth.instance.currentUser?.phoneNumber ?? '').toString();
                final status = (data['verificationStatus'] ?? 'not_started').toString();
                final rating = (data['averageRating'] is num)
                    ? (data['averageRating'] as num).toDouble()
                    : 0.0;
                final ratingsCount = (data['ratingCount'] is num)
                    ? (data['ratingCount'] as num).toInt()
                    : 0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Your account' : name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    if (phone.isNotEmpty)
                      Text(phone, style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _Chip(text: 'Status: ${status.toUpperCase()}'),
                        _Chip(text: 'Rating: ${rating.toStringAsFixed(1)} (${ratingsCount})'),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: walletDoc,
            builder: (context, snap) {
              // Wallet doc may not exist yet; WalletScreen reads /transactions as well
              final coins = (snap.data?.data()?['coins'] ?? 0).toString();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Coins', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(coins, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

// ---------------- Quick actions row ----------------

class _QuickRow extends StatelessWidget {
  const _QuickRow({
    required this.onEditProfile,
    required this.onWallet,
    required this.onVerify,
    required this.onSettings,
  });

  final VoidCallback onEditProfile;
  final VoidCallback onWallet;
  final VoidCallback onVerify;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        _Tile(icon: Icons.edit_rounded, label: 'Edit', onTap: onEditProfile, cs: cs),
        const SizedBox(width: 12),
        _Tile(icon: Icons.account_balance_wallet_rounded, label: 'Wallet', onTap: onWallet, cs: cs),
        const SizedBox(width: 12),
        _Tile(icon: Icons.verified_rounded, label: 'Verify', onTap: onVerify, cs: cs),
        const SizedBox(width: 12),
        _Tile(icon: Icons.settings_rounded, label: 'Settings', onTap: onSettings, cs: cs),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap, required this.cs});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          height: 92,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outline.withOpacity(0.12)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 26),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
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
        if (allowed.isNotEmpty) return const SizedBox.shrink();
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
