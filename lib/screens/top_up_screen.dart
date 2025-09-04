// lib/screens/top_up_screen.dart
//
// Wallet Top Up (Helper app, Phase 0)
// -----------------------------------
// • Presets (500 / 1000 / 2000 / 5000) + custom amount
// • Payment method selector (Card / Bank / Other)
// • Primary flow order of preference:
//    1) Navigate to your existing PaymentScreen(amount: …)
//    2) Call Cloud Function 'createTopUpCheckout' to get a hosted payment URL (opens browser)
//    3) DEV fallback: write a completed top-up transaction and increment wallet (local testing ONLY)
//
// Firestore writes (guarded):
//   transactions/{txId} {
//     userId, type:'topup', amount, status:'pending'|'ok'|'failed', createdAt, updatedAt, note
//   }
//   users/{uid}.walletBalance += amount  (on success only)

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class TopUpScreen extends StatefulWidget {
  const TopUpScreen({super.key});

  @override
  State<TopUpScreen> createState() => _TopUpScreenState();
}

class _TopUpScreenState extends State<TopUpScreen> {
  final _amountCtrl = TextEditingController();
  int _selectedPreset = 1000;
  String _method = 'card'; // card | bank | other
  bool _busy = false;
  int _balance = 0;

  @override
  void initState() {
    super.initState();
    _primeBalance();
    _amountCtrl.text = _selectedPreset.toString();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _primeBalance() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final m = snap.data() ?? {};
      final b = m['walletBalance'];
      setState(() {
        _balance = b is int ? b : b is num ? b.toInt() : 0;
      });
    } catch (_) {}
  }

  void _pickPreset(int v) {
    setState(() {
      _selectedPreset = v;
      _amountCtrl.text = v.toString();
    });
  }

  int _readAmount() {
    final raw = _amountCtrl.text.trim().replaceAll(',', '');
    final n = int.tryParse(raw);
    return (n == null || n <= 0) ? 0 : n;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    const presets = [500, 1000, 2000, 5000];

    return Scaffold(
      appBar: AppBar(title: const Text('Top up'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          // Balance card
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: cs.primary.withOpacity(0.12),
                    foregroundColor: cs.primary,
                    child: const Icon(Icons.account_balance_wallet_outlined),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Current balance', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text('LKR $_balance', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Amount presets
          Text('Amount', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in presets)
                ChoiceChip(
                  label: Text('LKR $p'),
                  selected: _selectedPreset == p,
                  onSelected: (_) => _pickPreset(p),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Custom amount (LKR)',
              hintText: 'e.g., 1500',
            ),
            onChanged: (_) => setState(() {
              final n = _readAmount();
              if (n > 0) _selectedPreset = n;
            }),
          ),

          const SizedBox(height: 16),

          // Method
          Text('Payment method', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                RadioListTile<String>(
                  value: 'card',
                  groupValue: _method,
                  onChanged: (v) => setState(() => _method = v!),
                  title: const Text('Card (Visa/Master)'),
                  secondary: const Icon(Icons.credit_card),
                ),
                const Divider(height: 1),
                RadioListTile<String>(
                  value: 'bank',
                  groupValue: _method,
                  onChanged: (v) => setState(() => _method = v!),
                  title: const Text('Bank transfer'),
                  secondary: const Icon(Icons.account_balance_outlined),
                ),
                const Divider(height: 1),
                RadioListTile<String>(
                  value: 'other',
                  groupValue: _method,
                  onChanged: (v) => setState(() => _method = v!),
                  title: const Text('Other'),
                  secondary: const Icon(Icons.payments_outlined),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Info
          Card(
            color: cs.surfaceContainerHigh,
            child: const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Top-ups are instant after payment completes.'),
              subtitle: Text('For test mode, use the DEV fallback button below.'),
            ),
          ),
        ],
      ),

      // Action bar
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _startPayment,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.lock_open),
                label: const Text('Top up now'),
              ),
              const SizedBox(height: 10),
              // DEV fallback – only for local/testing environments
              TextButton(
                onPressed: _busy ? null : _devInstantCredit,
                child: const Text('DEV: credit instantly (no payment)'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startPayment() async {
    final amount = _readAmount();
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in first.')));
      return;
    }

    setState(() => _busy = true);
    try {
      // 1) If you have a PaymentScreen in your project, try to route there.
      final pushed = await _tryOpenPaymentScreen(amount);
      if (pushed == true) return;

      // 2) Otherwise, try a Cloud Function that returns a hosted checkout URL.
      final url = await _tryCreateHostedCheckout(uid, amount, _method);
      if (url != null) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opening payment…')));
          }
          return;
        }
      }

      // If neither path worked, inform the user.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment flow not configured yet. Use DEV credit for testing.'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start payment: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _tryOpenPaymentScreen(int amount) async {
    try {
      // If you already have a PaymentScreen elsewhere in your app, navigate to it.
      final route = MaterialPageRoute(
        builder: (_) {
          try {
            // Common constructor signatures
            return PaymentScreen(amount: amount);
          } catch (_) {
            try {
              return PaymentScreen(lkrAmount: amount);
            } catch (_) {
              return const PaymentScreen();
            }
          }
        },
      );
      await Navigator.push(context, route);
      // Assume PaymentScreen handles wallet credit on success.
      await _primeBalance();
      return true;
    } catch (_) {
      // No PaymentScreen or wrong signature – fall back
      return false;
    }
  }

  Future<String?> _tryCreateHostedCheckout(String uid, int amount, String method) async {
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('createTopUpCheckout');
      final res = await fn.call(<String, dynamic>{
        'userId': uid,
        'amount': amount,
        'currency': 'LKR',
        'method': method, // card/bank/other – for your backend’s logic
        'idempotencyKey': 'topup_${uid}_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1 << 32)}',
      });
      final data = res.data as Map;
      if (data['ok'] == true && data['url'] is String) {
        return data['url'] as String;
      }
    } catch (_) {}
    return null;
  }

  /// DEV ONLY: directly credits wallet and writes a completed transaction.
  Future<void> _devInstantCredit() async {
    final amount = _readAmount();
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final txRef = FirebaseFirestore.instance.collection('transactions').doc();

      await FirebaseFirestore.instance.runTransaction((trx) async {
        final userSnap = await trx.get(userRef);
        final m = userSnap.data() as Map<String, dynamic>? ?? {};
        final current = (m['walletBalance'] is num) ? (m['walletBalance'] as num).toInt() : 0;
        final next = current + amount;

        trx.set(txRef, {
          'userId': uid,
          'type': 'topup',
          'amount': amount,
          'status': 'ok',
          'note': 'DEV instant credit',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        trx.update(userRef, {
          'walletBalance': next,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      await _primeBalance();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wallet credited.')));
        // Return to wallet
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not credit: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// Dummy PaymentScreen symbol for IDE hints if the file is missing.
// Remove if you already have a real payment screen in your project.
class PaymentScreen extends StatelessWidget {
  const PaymentScreen({super.key, this.amount, this.lkrAmount});
  final int? amount;
  final int? lkrAmount;

  @override
  Widget build(BuildContext context) {
    final shown = amount ?? lkrAmount ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: Center(
        child: Text(
          'Integrate your gateway here.\nAmount: LKR $shown',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
