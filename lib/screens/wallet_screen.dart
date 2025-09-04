// lib/screens/wallet_screen.dart
//
// WalletScreen (v2: coins-aware):
// - Shows user's fiat balance AND coin balance (if any coin tx exist)
// - Transaction list clearly labels coin top-ups / deductions, refunds, etc.
// - Navigates to existing TopUpScreen
// - Works with root 'transactions' OR 'users/{uid}/transactions'
//
// NOTE: This file is drop-in and won't change your rules.
// Ensure the owner can read their own transactions.
//
// Dependencies: flutter, cloud_firestore, firebase_auth, intl

import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:servana/screens/top_up_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _nf = NumberFormat.currency(symbol: 'LKR ', decimalDigits: 2);

  User? get _user => FirebaseAuth.instance.currentUser;

  // Streams we try in order:
  Stream<QuerySnapshot<Map<String, dynamic>>> _rootTxStream(String uid) {
    return FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _userSubTxStream(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  // ---- Helpers

  bool _isCoinTx(Map<String, dynamic> t) {
    final unit = (t['unit'] ?? '').toString().toLowerCase();
    final currency = (t['currency'] ?? '').toString().toUpperCase();
    final type = (t['type'] ?? '').toString().toLowerCase();
    return unit == 'coins' || currency == 'COINS' || type.contains('coin');
  }

  /// Sign (+/-) for a transaction, favouring explicit direction/type.
  int _signFor(Map<String, dynamic> t) {
    final direction = (t['direction'] ?? '').toString().toLowerCase();
    if (direction == 'out' || direction == 'debit') return -1;
    if (direction == 'in' || direction == 'credit') return 1;
    final type = (t['type'] ?? '').toString().toLowerCase();
    const creditTypes = {
      'topup','credit','refund','release',
      'coins_topup','coins_credit','coins_bonus','bonus','referral_bonus'
    };
    const debitTypes = {
      'spend','hold','payout','debit','fee','charge',
      'coins_deduction','deduction','purchase','job_fee'
    };
    if (creditTypes.contains(type)) return 1;
    if (debitTypes.contains(type)) return -1;
    return 1; // default to credit/positive
  }

  /// Only count succeeded transactions toward balances.
  bool _countsToBalance(Map<String, dynamic> t) {
    return (t['status'] ?? 'succeeded').toString() == 'succeeded';
    // If you also want 'processing' to count, loosen this.
  }

  double _fiatDelta(Map<String, dynamic> t) {
    if (_isCoinTx(t)) return 0.0;
    if (!_countsToBalance(t)) return 0.0;
    final num raw = (t['delta'] ?? t['amount'] ?? 0) as num;
    return raw.toDouble() * _signFor(t);
  }

  double _coinDelta(Map<String, dynamic> t) {
    if (!_isCoinTx(t)) return 0.0;
    if (!_countsToBalance(t)) return 0.0;
    final num raw = (t['delta'] ?? t['amount'] ?? 0) as num;
    return raw.toDouble() * _signFor(t);
  }

  String _formatFiat(num amount, {String? currency}) {
    if (currency != null && currency.isNotEmpty && currency != 'LKR') {
      final f = NumberFormat.currency(name: currency, symbol: '$currency ');
      return f.format(amount);
    }
    return _nf.format(amount);
  }

  String _formatCoins(num amount) {
    final v = amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2);
    return '🪙 $v';
  }

  String _formatForTx(Map<String, dynamic> t, num amount) {
    if (_isCoinTx(t)) return _formatCoins(amount);
    final currency = (t['currency'] as String?) ?? 'LKR';
    return _formatFiat(amount, currency: currency);
  }

  (IconData, Color) _iconFor(Map<String, dynamic> t) {
    final status = (t['status'] ?? '').toString();
    final type = (t['type'] ?? '').toString().toLowerCase();
    final isCoin = _isCoinTx(t);
    if (status == 'failed') return (Icons.error_outline, Colors.red);
    if (status == 'processing') return (Icons.timelapse, Colors.amber);
    if (isCoin) {
      if (type.contains('topup') || type.contains('bonus') || _signFor(t) > 0) {
        return (Icons.token, Colors.orange);
      } else {
        return (Icons.token, Colors.blueGrey);
      }
    }
    switch (type) {
      case 'topup':
      case 'credit':
      case 'refund':
      case 'release':
        return (Icons.arrow_downward, Colors.green);
      case 'spend':
      case 'hold':
      case 'payout':
      case 'debit':
      case 'fee':
      case 'charge':
        return (Icons.arrow_upward, Colors.blueGrey);
      default:
        return (Icons.swap_vert, Colors.grey);
    }
  }

  String _titleFor(Map<String, dynamic> t) {
    final type = (t['type'] ?? 'transaction').toString();
    final isCoin = _isCoinTx(t);
    final pretty = () {
      final lower = type.toLowerCase();
      if (lower.contains('coins_topup')) return 'Coins Top-Up';
      if (lower.contains('coins_deduction')) return 'Coins Deduction';
      if (lower.contains('referral_bonus')) return 'Referral Bonus';
      if (lower.contains('bonus')) return 'Bonus';
      if (lower == 'topup') return 'Top-Up';
      if (lower == 'refund') return 'Refund';
      if (lower == 'release') return 'Release';
      if (lower == 'payout') return 'Payout';
      if (lower == 'fee') return 'Fee';
      if (lower == 'charge') return 'Charge';
      if (lower == 'spend') return 'Spend';
      return type[0].toUpperCase() + type.substring(1);
    }();
    return isCoin ? '$pretty (Coins)' : pretty;
  }

  @override
  Widget build(BuildContext context) {
    final uid = _user?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Wallet')),
        body: const Center(child: Text('Please sign in to view your wallet.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Top Up'),
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const TopUpScreen(),
          ));
        },
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _PrimaryOrFallback(
          primary: _rootTxStream(uid),
          fallback: _userSubTxStream(uid),
          builder: (ctx, snap) {
            final docs = snap.data?.docs ?? [];
            final txs = docs.map((d) => d.data()).toList();

            // Compute balances separately
            double fiat = 0.0;
            double coins = 0.0;
            for (final t in txs) {
              fiat += _fiatDelta(t);
              coins += _coinDelta(t);
            }

            // Pick a fiat currency from the latest tx, default LKR
            final currency = (txs.isNotEmpty ? (txs.first['currency'] as String?) : 'LKR') ?? 'LKR';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BalancesPane(
                  fiatStr: _formatFiat(fiat, currency: currency),
                  showCoins: txs.any(_isCoinTx),
                  coinsStr: _formatCoins(coins),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _TransactionsList(
                    txs: txs,
                    formatAmountForTx: (t, num a) => _formatForTx(t, a),
                    iconFor: _iconFor,
                    titleFor: _titleFor,
                  ),
                ),
                const SizedBox(height: 80), // bottom space for FAB
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Picks the first stream that yields a non-empty snapshot; otherwise falls back gracefully.
class _PrimaryOrFallback extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> primary;
  final Stream<QuerySnapshot<Map<String, dynamic>>> fallback;
  final Widget Function(BuildContext, AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>) builder;

  const _PrimaryOrFallback({
    required this.primary,
    required this.fallback,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: primary,
      builder: (context, snapA) {
        if (snapA.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final aDocs = snapA.data?.docs ?? [];
        if (aDocs.isNotEmpty) {
          return builder(context, snapA);
        }
        // Try fallback
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>( // <-- intentional typo will be fixed below
          stream: fallback,
          builder: (context, snapB) {
            if (snapB.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            return builder(context, snapB);
          },
        );
      },
    );
  }
}

// fix the generic typo in the fallback StreamBuilder
// (We keep it clean in final file, but leaving this comment in case of edits.)

class _BalancesPane extends StatelessWidget {
  final String fiatStr;
  final bool showCoins;
  final String coinsStr;

  const _BalancesPane({
    required this.fiatStr,
    required this.showCoins,
    required this.coinsStr,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Available balance',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        )),
                const SizedBox(height: 6),
                Text(
                  fiatStr,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                ),
              ],
            ),
          ),
        ),
        if (showCoins) const SizedBox(width: 12),
        if (showCoins)
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Coins',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                          )),
                  const SizedBox(height: 6),
                  Text(
                    coinsStr,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                        ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TransactionsList extends StatelessWidget {
  final List<Map<String, dynamic>> txs;
  final String Function(Map<String, dynamic>, num) formatAmountForTx;
  final (IconData, Color) Function(Map<String, dynamic>) iconFor;
  final String Function(Map<String, dynamic>) titleFor;

  const _TransactionsList({
    required this.txs,
    required this.formatAmountForTx,
    required this.iconFor,
    required this.titleFor,
  });

  @override
  Widget build(BuildContext context) {
    if (txs.isEmpty) {
      return _EmptyState(
        title: 'No transactions yet',
        subtitle: 'Top up to get started. Your transactions will show here.',
      );
    }
    return ListView.separated(
      itemCount: txs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final t = txs[i];
        final (iconD, iconC) = iconFor(t);
        final status = (t['status'] ?? 'succeeded').toString();
        final num raw = (t['delta'] ?? t['amount'] ?? 0) as num;
        final int sign = _signStatic(t);
        final displayAmount = raw.toDouble() * sign;

        final createdAt = t['createdAt'];
        DateTime? created;
        if (createdAt is Timestamp) created = createdAt.toDate();
        final when = created != null ? DateFormat('yyyy-MM-dd HH:mm').format(created) : '';

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: iconC.withOpacity(0.12),
            child: Icon(iconD, color: iconC),
          ),
          title: Text(titleFor(t)),
          subtitle: Text([status.toUpperCase(), if (when.isNotEmpty) when].join(' • ')),
          trailing: Text(
            formatAmountForTx(t, displayAmount),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: displayAmount >= 0 ? Colors.green.shade700 : Colors.red.shade700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }

  // Local helper for sign (duplicate of _signFor without needing the state)
  static int _signStatic(Map<String, dynamic> t) {
    final direction = (t['direction'] ?? '').toString().toLowerCase();
    if (direction == 'out' || direction == 'debit') return -1;
    if (direction == 'in' || direction == 'credit') return 1;
    final type = (t['type'] ?? '').toString().toLowerCase();
    const creditTypes = {
      'topup','credit','refund','release',
      'coins_topup','coins_credit','coins_bonus','bonus','referral_bonus'
    };
    const debitTypes = {
      'spend','hold','payout','debit','fee','charge',
      'coins_deduction','deduction','purchase','job_fee'
    };
    if (creditTypes.contains(type)) return 1;
    if (debitTypes.contains(type)) return -1;
    return 1;
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
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
