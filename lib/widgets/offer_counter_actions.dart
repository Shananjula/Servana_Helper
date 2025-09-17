// lib/widgets/offer_counter_actions.dart (v2)
// Helper-side inline actions for an offer under tasks/{taskId}/offers/{offerId}.
// Usage options:
//   OfferCounterActions(offerRef: FirebaseFirestore.instance.doc('tasks/$taskId/offers/$offerId'))
//   OfferCounterActions(offerId: offerId, taskId: taskId)          // resolves subcollection ref
//   OfferCounterActions(offerId: offerId)                           // resolves taskId via top-level /offers/{offerId}
//
// Shows Agree / Withdraw / Counter back for the helper who owns the offer.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class OfferCounterActions extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>>? offerRef;
  final String? offerId;
  final String? taskId;

  const OfferCounterActions({
    super.key,
    this.offerRef,
    this.offerId,
    this.taskId,
  }) : assert(offerRef != null || offerId != null,
        'Provide either offerRef OR offerId (+ optional taskId).');

  @override
  State<OfferCounterActions> createState() => _OfferCounterActionsState();
}

class _OfferCounterActionsState extends State<OfferCounterActions> {
  bool _busy = false;
  final _priceCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  Future<DocumentReference<Map<String, dynamic>>>? _refFuture;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _refFuture = _resolveRef();
  }

  Future<DocumentReference<Map<String, dynamic>>> _resolveRef() async {
    if (widget.offerRef != null) return widget.offerRef!;
    final offerId = widget.offerId!;
    String? taskId = widget.taskId;
    if (taskId == null || taskId.isEmpty) {
      // Try top-level /offers mirror to discover taskId
      final top = await FirebaseFirestore.instance.doc('offers/$offerId').get();
      if (top.exists) {
        final t = (top.data() ?? const {})['taskId']?.toString();
        if (t != null && t.isNotEmpty) taskId = t;
      }
    }
    if (taskId == null || taskId.isEmpty) {
      throw StateError('Cannot resolve taskId for offer $offerId. Pass taskId or ensure /offers mirror exists.');
    }
    return FirebaseFirestore.instance.doc('tasks/$taskId/offers/$offerId');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentReference<Map<String, dynamic>>>(
      future: _refFuture,
      builder: (context, refSnap) {
        if (refSnap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 56,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (refSnap.hasError || refSnap.data == null) {
          return Text(
            'Offer actions unavailable: ${refSnap.error ?? 'no ref'}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          );
        }
        final ref = refSnap.data!;
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: ref.snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const SizedBox.shrink();
            final o = snap.data!.data() ?? const <String, dynamic>{};
            final helperId = (o['helperId'] ?? '').toString();
            if (helperId != _uid) return const SizedBox.shrink();

            final status = (o['status'] ?? '').toString();
            final canInteract = ['pending','negotiating','counter'].contains(status);
            if (!canInteract) return const SizedBox.shrink();

            final cp = o['counterPrice'] ?? o['price'] ?? o['amount'];
            if ((_priceCtrl.text.isEmpty) && cp != null) {
              _priceCtrl.text = cp.toString();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (status == 'counter')
                  Text('Poster countered to ${o['counterPrice']}', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : () => _agree(ref),
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Agree'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _withdraw(ref),
                        icon: const Icon(Icons.close),
                        label: const Text('Withdraw'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Your counter price',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _counterAgain(ref),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Counter back'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _agree(DocumentReference<Map<String, dynamic>> ref) async {
    setState(() => _busy = true);
    try {
      await ref.update({
        'helperAgreed': true,
        'agreedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agreed. Waiting for poster to accept.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw(DocumentReference<Map<String, dynamic>> ref) async {
    setState(() => _busy = true);
    try {
      await ref.update({
        'status': 'withdrawn',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _counterAgain(DocumentReference<Map<String, dynamic>> ref) async {
    final val = _priceCtrl.text.trim();
    final price = num.tryParse(val);
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid number.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.update({
        'status': 'negotiating',
        'helperCounterPrice': price,
        'helperCounterNote': _noteCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
