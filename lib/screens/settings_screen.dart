// lib/screens/settings_screen.dart
//
// Settings (Helper app, Phase 0/1) — UPDATED
// ------------------------------------------
// • Header: name, phone, wallet balance
// • Actions: Edit profile • Verification Center • Notifications • Legal • Logout
// • Money: Wallet (balance & transactions)
// • Preferences: Theme (System/Light/Dark), Language (System/EN/SI/TA)
// • Persists preferences to users/{uid}.settings.{theme, locale}
//
// Changes in this update:
// • Removed duplicate verification tiles:
//     - "Documents & Verification" (Step 2 Documents) tile removed
//     - Extra "Verification Center" tile that pointed to Step 2 removed
// • Kept a single, correct "Verification Center" tile (routes to VerificationCenterScreen)
// • Added a "Money" section with a "Wallet" tile
//
// Deps: cloud_firestore, firebase_auth, flutter/material
// Uses existing screens: EditProfileScreen, NotificationsScreen, VerificationCenterScreen, LegalScreen

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:servana/screens/verification_center_screen.dart';
import 'package:servana/screens/wallet_screen.dart';
import 'package:servana/screens/dispute_center_screen.dart'; // ← ADDED THIS LINE

// Destinations already in your project
import 'package:servana/screens/notifications_screen.dart';
import 'package:servana/screens/legal_screen.dart';
import 'package:servana/screens/edit_profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _themePref = 'system'; // 'system' | 'light' | 'dark'
  String _langPref = '';        // '' (system) | 'en' | 'si' | 'ta'
  bool _loadingPrefs = true;
  bool _savingPrefs = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _loadingPrefs = false);
        return;
      }
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final s = (snap.data()?['settings'] ?? {}) as Map<String, dynamic>;
      final theme = (s['theme'] ?? 'system').toString();
      final locale = (s['locale'] ?? '').toString();

      _themePref = (theme == 'light' || theme == 'dark' || theme == 'system') ? theme : 'system';
      _langPref = (['', 'en', 'si', 'ta'].contains(locale)) ? locale : '';
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingPrefs = false);
    }
  }

  Future<void> _savePrefs() async {
    setState(() => _savingPrefs = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'settings': {
          'theme': _themePref,
          'locale': _langPref,
        }
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preferences saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPrefs = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _HeaderCard(uid: uid),

          const SizedBox(height: 16),
          Text('Account', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),

          _tile(
            context,
            icon: Icons.person_rounded,
            title: 'Edit profile',
            subtitle: 'Name, photo, bio',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.rule_folder_rounded),
            title: const Text('Verification Center'),
            subtitle: const Text('Step 1 • Step 2 • Step 3'),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VerificationCenterScreen()));
            },
          ),

          const SizedBox(height: 16),
          Text('Money', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          _tile(
            context,
            icon: Icons.account_balance_wallet_outlined,
            title: 'Wallet',
            subtitle: 'Balance & transactions',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WalletScreen()),
            ),
          ),

          const SizedBox(height: 16),
          Text('Preferences', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          _PreferencesCard(
            loading: _loadingPrefs,
            themeValue: _themePref,
            langValue: _langPref,
            onThemeChanged: (v) => setState(() => _themePref = v),
            onLangChanged: (v) => setState(() => _langPref = v),
            onSave: _savingPrefs ? null : _savePrefs,
            saving: _savingPrefs,
          ),

          const SizedBox(height: 16),
          Text('Help & legal', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          // ADD — Dispute Center entry
          _tile(
            context,
            icon: Icons.balance_rounded,
            title: 'Dispute Center',
            subtitle: 'View & resolve disputes, add evidence',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DisputeCenterScreen()),
            ),
          ),
          _tile(
            context,
            icon: Icons.description_rounded,
            title: 'Legal & terms',
            subtitle: 'Privacy policy and terms',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LegalScreen()),
            ),
          ),
          _tile(
            context,
            icon: Icons.info_outline_rounded,
            title: 'About Servana',
            subtitle: 'Version info',
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Servana Helper',
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

  Widget _tile(
      BuildContext context, {
        required IconData icon,
        required String title,
        String? subtitle,
        required VoidCallback onTap,
      }) {
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

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.uid});
  final String? uid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (uid == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outline.withOpacity(0.12)),
        ),
        child: Row(
          children: const [
            CircleAvatar(radius: 26, child: Icon(Icons.person)),
            SizedBox(width: 12),
            Expanded(child: Text('Not signed in', style: TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
      );
    }

    final userDoc = FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          const CircleAvatar(radius: 26, child: Icon(Icons.person)),
          const SizedBox(width: 12),
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: userDoc,
              builder: (context, snap) {
                final data = snap.data?.data();
                final name = (data?['displayName'] ?? '').toString();
                final phone = (data?['phone'] ?? data?['phoneNumber'] ?? '').toString();
                final coins = (data?['walletBalance'] ?? 0).toString();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Your account' : name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      phone.isEmpty ? (FirebaseAuth.instance.currentUser?.phoneNumber ?? '') : phone,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: userDoc,
            builder: (context, snap) {
              final coins = (snap.data?.data()?['walletBalance'] ?? 0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Balance', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(coins.toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PreferencesCard extends StatelessWidget {
  const _PreferencesCard({
    required this.loading,
    required this.themeValue,
    required this.langValue,
    required this.onThemeChanged,
    required this.onLangChanged,
    required this.onSave,
    required this.saving,
  });

  final bool loading;
  final String themeValue;
  final String langValue;
  final ValueChanged<String> onThemeChanged;
  final ValueChanged<String> onLangChanged;
  final VoidCallback? onSave;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (loading) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline.withOpacity(0.12)),
        ),
        child: const LinearProgressIndicator(),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Theme', style: TextStyle(fontWeight: FontWeight.w800)),
          RadioListTile<String>(
            title: const Text('System default'),
            value: 'system',
            groupValue: themeValue,
            onChanged: (v) => onThemeChanged(v!),
          ),
          RadioListTile<String>(
            title: const Text('Light'),
            value: 'light',
            groupValue: themeValue,
            onChanged: (v) => onThemeChanged(v!),
          ),
          RadioListTile<String>(
            title: const Text('Dark'),
            value: 'dark',
            groupValue: themeValue,
            onChanged: (v) => onThemeChanged(v!),
          ),
          const SizedBox(height: 12),
          const Text('Language', style: TextStyle(fontWeight: FontWeight.w800)),
          RadioListTile<String>(
            title: const Text('System default'),
            value: '',
            groupValue: langValue,
            onChanged: (v) => onLangChanged(v!),
          ),
          RadioListTile<String>(
            title: const Text('English'),
            value: 'en',
            groupValue: langValue,
            onChanged: (v) => onLangChanged(v!),
          ),
          RadioListTile<String>(
            title: const Text('සිංහල (Sinhala)'),
            value: 'si',
            groupValue: langValue,
            onChanged: (v) => onLangChanged(v!),
          ),
          RadioListTile<String>(
            title: const Text('தமிழ் (Tamil)'),
            value: 'ta',
            groupValue: langValue,
            onChanged: (v) => onLangChanged(v!),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onSave,
              icon: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_rounded),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
