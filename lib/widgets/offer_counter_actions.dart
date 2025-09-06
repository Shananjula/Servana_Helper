import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class OfferCounterActions extends StatefulWidget {
  final String offerId;    // top-level /offers document ID you show in Helper
  final EdgeInsets padding;
  const OfferCounterActions({super.key, required this.offerId, this.padding = const EdgeInsets.only(top: 8)});

  @override
  State<OfferCounterActions> createState() => _OfferCounterActionsState();
}

class _OfferCounterActionsState extends State<OfferCounterActions> {
  Future<void> _agree() async {
    final ref = FirebaseFirestore.instance.collection('offers').doc(widget.offerId);
    final snap = await ref.get();
    final data = snap.data() as Map<String, dynamic>? ?? {};
    final counterPrice = data['counterPrice'];
    if (counterPrice == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No counter amount found.')));
      return;
    }
    await ref.update({
      'price': counterPrice,
      'status': 'pending',
      'lastCounterBy': 'helper',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agreed. Waiting for poster to accept.')));
    }
  }

  Future<void> _counterBack() async {
    final c = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Counter offer'),
        content: TextField(
            controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'New price (LKR)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Send')),
        ],
      ),
    );
    if (res == null || res.isEmpty) return;
    final newPrice = num.tryParse(res);
    if (newPrice == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid number')));
      return;
    }
    await FirebaseFirestore.instance.collection('offers').doc(widget.offerId).update({
      'status': 'counter',
      'counterPrice': newPrice,
      'lastCounterBy': 'helper',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Counter sent.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: Row(children: [
        FilledButton.icon(onPressed: _agree, icon: const Icon(Icons.thumb_up_alt_outlined), label: const Text('Agree')),
        const SizedBox(width: 8),
        OutlinedButton.icon(onPressed: _counterBack, icon: const Icon(Icons.swap_vert), label: const Text('Counter back')),
      ]),
    );
  }
}
