// lib/screens/referral_screen.dart
//
// Minimal referrals:
//  - Shows my referral code (auto-generates & stores mapping at first open)
//  - Lets me enter a friend's code once (stores referredBy uid)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});
  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  String? _myCode;
  bool _busy = false;
  final _friendCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ensureMyCode();
  }

  @override
  void dispose() {
    _friendCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureMyCode() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _busy = true);
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await userRef.get();
      final m = snap.data() ?? {};
      var code = (m['referralCode'] ?? '') as String;
      if (code.isEmpty) {
        // Generate 6-char code
        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        String gen() => List.generate(6, (i) => chars[(DateTime.now().millisecondsSinceEpoch + i + i*i) % chars.length]).join();
        // Try a few times to avoid collision
        for (int i = 0; i < 3; i++) {
          code = gen();
          final exists = await FirebaseFirestore.instance.collection('referral_codes').doc(code).get();
          if (!exists.exists) break;
          code = '';
        }
        if (code.isEmpty) {
          code = gen();
        }
        await FirebaseFirestore.instance.runTransaction((trx) async {
          trx.set(userRef, {'referralCode': code, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
          trx.set(FirebaseFirestore.instance.collection('referral_codes').doc(code), {'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
        });
      }
      if (mounted) setState(() => _myCode = code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyFriendCode() async {
    if (_busy) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final code = _friendCtrl.text.trim().toUpperCase();
    if (code.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid code.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final map = await FirebaseFirestore.instance.collection('referral_codes').doc(code).get();
      if (!map.exists) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code not found.')));
        return;
      }
      final referrerUid = (map.data() ?? {})['uid'] as String? ?? '';
      if (referrerUid.isEmpty || referrerUid == uid) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid code.')));
        return;
      }
      // Set referredBy only if not set
      final uref = FirebaseFirestore.instance.collection('users').doc(uid);
      await FirebaseFirestore.instance.runTransaction((trx) async {
        final snap = await trx.get(uref);
        final m = snap.data() ?? {};
        if ((m['referredBy'] ?? '').toString().isNotEmpty) return;
        trx.set(uref, {'referredBy': referrerUid, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Referral applied. Thanks!')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Referrals')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(backgroundColor: cs.primaryContainer, child: const Icon(Icons.card_giftcard_outlined)),
              title: const Text('Share your code'),
              subtitle: Text(_myCode ?? '…'),
              trailing: IconButton(
                icon: const Icon(Icons.copy_outlined),
                onPressed: _myCode == null ? null : () { Clipboard.setData(ClipboardData(text: _myCode)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied'))); },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Have a friend’s code?', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _friendCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Enter referral code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _applyFriendCode,
                    icon: _busy ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.check),
                    label: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
