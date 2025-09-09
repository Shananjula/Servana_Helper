
// lib/widgets/offer_message_card.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class OfferMessageCard extends StatelessWidget {
  const OfferMessageCard({
    super.key,
    required this.taskId,
    required this.posterId,
    required this.helperId,
    required this.price,
    this.note,
  });

  final String taskId;
  final String posterId;
  final String helperId;
  final double price;
  final String? note;

  bool get _amPoster => FirebaseAuth.instance.currentUser?.uid == posterId;
  bool get _amHelper => FirebaseAuth.instance.currentUser?.uid == helperId;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.local_offer_outlined, size: 18),
              const SizedBox(width: 6),
              Text('Offer', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
            ]),
            const SizedBox(height: 6),
            Text('Price: LKR ${price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if ((note ?? '').isNotEmpty) ...[const SizedBox(height: 6), Text(note!)],
            const SizedBox(height: 8),
            Row(children: [
              if (_amPoster) ...[
                FilledButton.icon(
                  onPressed: () async {
                    final q = await FirebaseFirestore.instance
                      .collection('tasks').doc(taskId).collection('offers')
                      .where('helperId', isEqualTo: helperId)
                      .where('status', whereIn: ['pending','counter'])
                      .limit(1).get();
                    if (q.docs.isNotEmpty) {
                      await q.docs.first.reference.update({'status': 'accepted', 'updatedAt': FieldValue.serverTimestamp()});
                    }
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Accept'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Counter flow placeholder'),
                    ));
                  },
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Counter'),
                ),
              ],
              if (_amHelper) ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    final q = await FirebaseFirestore.instance
                      .collection('tasks').doc(taskId).collection('offers')
                      .where('helperId', isEqualTo: helperId)
                      .where('status', isEqualTo: 'pending')
                      .limit(1).get();
                    if (q.docs.isNotEmpty) {
                      await q.docs.first.reference.update({'status': 'withdrawn', 'updatedAt': FieldValue.serverTimestamp()});
                    }
                  },
                  icon: const Icon(Icons.undo_outlined),
                  label: const Text('Withdraw'),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }
}
