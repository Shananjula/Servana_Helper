
// lib/screens/wallet_screen.dart
//
// Helper Wallet (Map v2.2, self-contained)
// - Reads coins from users/{uid}.servCoinBalance
// - Streams users/{uid}/transactions (created by CFs: topUpCoins, acceptOffer, etc.)
// - Clear labels for accept_fee/topup/refund/...
// - Includes an internal `_EmptyState` widget so `const _EmptyState(...)` compiles

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    final uid = _user?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Wallet')),
        body: const Center(child: Text('Please sign in to view your wallet.')),
      );
    }

    final userDoc = FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    final txns = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userDoc,
        builder: (context, userSnap) {
          final u = userSnap.data?.data() ?? const {};
          final coins = (u['servCoinBalance'] is num) ? (u['servCoinBalance'] as num).toDouble() : 0.0;
          final role = (u['role'] ?? '').toString();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(coins: coins, role: role),
              const Divider(height: 0),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: txns,
                  builder: (context, txSnap) {
                    if (txSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = txSnap.data?.docs ?? const [];
                    if (docs.isEmpty) {
                      return const _EmptyState(
                        title: 'No transactions yet',
                        subtitle: 'When a poster accepts your public offer, 25 coins may be charged.\n'
                                  'If it was a direct invite, you are not charged.',
                      );
                    }
                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (context, i) {
                        final t = docs[i].data();
                        return _TxnTile(t: t);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final double coins;
  final String role;
  const _Header({required this.coins, required this.role});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Coins balance', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('${coins.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              const Icon(Icons.monetization_on_outlined),
            ],
          ),
          const SizedBox(height: 8),
          const _Hint(),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Public offer acceptance can cost 25 coins. '
              'If a poster invited you directly, you are not charged.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  final Map<String, dynamic> t;
  const _TxnTile({required this.t});

  @override
  Widget build(BuildContext context) {
    final type = (t['type'] ?? '').toString();
    final amt = (t['amount'] is num) ? (t['amount'] as num).toDouble() : 0.0;
    final created = (t['createdAt'] as Timestamp?)?.toDate();
    final sign = _signFor(type);
    final title = _titleFor(type);
    final subtitle = _subtitleFor(t);
    final color = sign >= 0 ? Colors.green : Colors.red;
    final display = '${sign >= 0 ? '+' : '−'}${amt.abs().toStringAsFixed(0)} coins';

    return ListTile(
      leading: Icon(_iconFor(type), color: color),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(display, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }

  int _signFor(String type) {
    final s = type.toLowerCase();
    if (s == 'topup' || s == 'refund' || s.endsWith('_credit') || s.endsWith('_bonus') || s == 'release') return 1;
    return -1; // accept_fee, commission, payout, etc.
  }

  String _titleFor(String type) {
    switch (type.toLowerCase()) {
      case 'accept_fee': return 'Offer Acceptance Fee';
      case 'topup': return 'Top-Up';
      case 'refund': return 'Refund';
      case 'release': return 'Release';
      case 'commission': return 'Commission';
      default: return type.isEmpty ? 'Transaction' : '${type[0].toUpperCase()}${type.substring(1)}';
    }
  }

  String _subtitleFor(Map<String, dynamic> t) {
    final taskId = (t['taskId'] ?? '').toString();
    final offerId = (t['offerId'] ?? '').toString();
    final status = (t['status'] ?? '').toString();
    final created = (t['createdAt'] as Timestamp?)?.toDate();
    final dt = created != null ? DateFormat.yMMMd().add_jm().format(created) : '';
    final parts = <String>[];
    if (dt.isNotEmpty) parts.add(dt);
    if (status.isNotEmpty) parts.add(status);
    if (taskId.isNotEmpty) parts.add('task $taskId');
    if (offerId.isNotEmpty) parts.add('offer $offerId');
    return parts.join(' · ');
  }

  IconData _iconFor(String type) {
    switch (type.toLowerCase()) {
      case 'accept_fee': return Icons.how_to_reg_outlined;
      case 'topup': return Icons.add_card_outlined;
      case 'refund': return Icons.undo_outlined;
      case 'release': return Icons.outbond_outlined;
      case 'commission': return Icons.percent_outlined;
      default: return Icons.receipt_long_outlined;
    }
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  const _EmptyState({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700])),
          ],
        ),
      ),
    );
  }
}
