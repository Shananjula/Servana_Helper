// lib/widgets/payment_methods_row.dart
import 'package:flutter/material.dart';

class PaymentMethodsRow extends StatelessWidget {
  final List<String> methodIds;
  final String? otherNote;
  const PaymentMethodsRow({super.key, required this.methodIds, this.otherNote});

  @override
  Widget build(BuildContext context) {
    if (methodIds.isEmpty) return const SizedBox.shrink();
    final labels = {
      'bank_transfer': 'Bank transfer',
      'servcoins': 'ServCoins',
      'card': 'Card',
      'cash': 'Cash',
      'other': 'Other',
    };
    final icons = {
      'bank_transfer': Icons.account_balance,
      'servcoins': Icons.token,
      'card': Icons.credit_card,
      'cash': Icons.payments,
      'other': Icons.more_horiz,
    };

    final chips = methodIds.map((id) {
      final label = labels[id] ?? id;
      final icon = icons[id] ?? Icons.more_horiz;
      return Chip(avatar: Icon(icon, size: 16), label: Text(label));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Payment methods', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ...chips,
          if (methodIds.contains('other') && (otherNote ?? '').isNotEmpty)
            Chip(label: Text(otherNote!)),
        ]),
      ],
    );
  }
}
