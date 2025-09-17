
// lib/widgets/chat/offer_message_card.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:servana/services/offer_actions.dart';

class OfferMessageCard extends StatefulWidget {
  final Map<String, dynamic> message; // chats/{cid}/messages doc data
  const OfferMessageCard({super.key, required this.message});

  @override
  State<OfferMessageCard> createState() => _OfferMessageCardState();
}

class _OfferMessageCardState extends State<OfferMessageCard> {
  bool _busy = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final theme = Theme.of(context);
    final type = (m['type'] ?? '').toString();
    final offerId = (m['offerId'] ?? '').toString();
    final status = (m['status'] ?? '').toString();
    final amount = m['amount'];
    final counterPrice = m['counterPrice'];
    final helperCounterPrice = m['helperCounterPrice'];
    final origin = (m['origin'] ?? 'public').toString();
    final posterId = (m['posterId'] ?? '').toString();
    final helperId = (m['helperId'] ?? '').toString();
    final isPoster = _uid == posterId;
    final isHelper = _uid == helperId;

    final title = _titleFor(type, status);
    final rows = <Widget>[];

    rows.add(Text(title, style: theme.textTheme.titleMedium));
    rows.add(const SizedBox(height: 4));
    if (amount != null) rows.add(Text('Offer: $amount'));
    if (counterPrice != null) rows.add(Text('Counter: $counterPrice'));
    if (helperCounterPrice != null) rows.add(Text('Helper counter: $helperCounterPrice'));
    if (origin == 'public' && isPoster) {
      rows.add(Text('Helper pays acceptance fee on Accept', style: theme.textTheme.bodySmall));
    } else if (origin == 'direct' && isPoster) {
      rows.add(Text('No helper fee on Accept (direct invite path)', style: theme.textTheme.bodySmall));
    }

    final actions = _actions(type: type, status: status, isPoster: isPoster, isHelper: isHelper, offerId: offerId);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...rows,
            if (actions.isNotEmpty) const SizedBox(height: 8),
            if (actions.isNotEmpty)
              Wrap(
                spacing: 8, runSpacing: -6,
                children: actions.map((a) {
                  return a;
                }).toList(),
              ),
            if (_busy) const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            )
          ],
        ),
      ),
    );
  }

  String _titleFor(String type, String status) {
    switch (type) {
      case 'offer.created': return 'Offer submitted';
      case 'offer.counter.poster': return 'Poster countered';
      case 'offer.counter.helper': return 'Helper countered';
      case 'offer.agreed': return 'Helper agreed to counter';
      case 'offer.rejected': return 'Offer rejected';
      case 'offer.withdrawn': return 'Offer withdrawn';
      case 'offer.accepted': return 'Offer accepted';
      default:
        return status.isNotEmpty ? 'Offer $status' : 'Offer update';
    }
  }

  List<Widget> _actions({
    required String type,
    required String status,
    required bool isPoster,
    required bool isHelper,
    required String offerId,
  }) {
    final a = <Widget>[];

    // Poster actions
    if (isPoster) {
      if (status == 'pending' || status == 'negotiating' || status == 'counter') {
        a.add(OutlinedButton.icon(
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Counter'),
          onPressed: _busy ? null : () => _counterDialog(offerId),
        ));
        a.add(OutlinedButton.icon(
          icon: const Icon(Icons.close),
          label: const Text('Reject'),
          onPressed: _busy ? null : () => _reject(offerId),
        ));
        a.add(FilledButton.icon(
          icon: const Icon(Icons.check_circle),
          label: const Text('Accept'),
          onPressed: _busy ? null : () => _accept(offerId),
        ));
      }
    }

    // Helper actions
    if (isHelper) {
      if (status == 'pending' || status == 'negotiating' || status == 'counter') {
        if (status == 'counter') {
          a.add(FilledButton.icon(
            icon: const Icon(Icons.check_circle),
            label: const Text('Agree'),
            onPressed: _busy ? null : () => _agree(offerId),
          ));
        }
        a.add(OutlinedButton.icon(
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Counter back'),
          onPressed: _busy ? null : () => _helperCounterDialog(offerId),
        ));
        a.add(OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          label: const Text('Withdraw'),
          onPressed: _busy ? null : () => _withdraw(offerId),
        ));
      }
    }

    return a;
  }

  Future<void> _counterDialog(String offerId) async {
    final controller = TextEditingController();
    final noteCtrl = TextEditingController();
    final res = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Counter offer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: controller, decoration: const InputDecoration(labelText: 'Counter price'), keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Note (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, {'p': controller.text, 'n': noteCtrl.text}), child: const Text('Send'))
        ],
      ),
    );
    if (res != null && res['p'] != null && res['p']!.trim().isNotEmpty) {
      final price = num.tryParse(res['p']!.trim());
      final note  = res['n']!.trim();
      if (price != null && price > 0) {
        setState(() => _busy = true);
        try {
          await OfferActions.instance.proposeCounter(offerId: offerId, price: price, note: note.isEmpty ? null : note);
        } finally { if (mounted) setState(() => _busy = false); }
      }
    }
  }

  Future<void> _helperCounterDialog(String offerId) async {
    final controller = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Your counter price'),
        content: TextField(controller: controller, keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Send')),
        ],
      ),
    );
    if (res != null && res.trim().isNotEmpty) {
      final price = num.tryParse(res.trim());
      if (price != null && price > 0) {
        setState(() => _busy = true);
        try {
          // Use the same callable as poster? No — helper counter goes via direct field; we add a small callable, but for now reuse proposeCounter is wrong
          // We expose a helper-side counter by setting helperCounterPrice; add a dedicated callable if needed. Here we just reuse proposeCounter for simplicity.
          await OfferActions.instance.helperCounter(offerId: offerId, price: price);
        } finally { if (mounted) setState(() => _busy = false); }
      }
    }
  }

  Future<void> _reject(String offerId) async {
    setState(() => _busy = true);
    try {
      await OfferActions.instance.rejectOffer(offerId: offerId);
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _withdraw(String offerId) async {
    setState(() => _busy = true);
    try {
      await OfferActions.instance.withdrawOffer(offerId: offerId);
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _agree(String offerId) async {
    setState(() => _busy = true);
    try {
      await OfferActions.instance.agreeToCounter(offerId: offerId);
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _accept(String offerId) async {
    setState(() => _busy = true);
    try {
      await OfferActions.instance.acceptOffer(offerId: offerId);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Accept failed: $e')));
    } finally { if (mounted) setState(() => _busy = false); }
  }
}
