// lib/screens/manage_offers_screen.dart — Helper app
// Streams offers from tasks/{taskId}/offers, accepts via CF,
// and reads phone with tolerance (phone ?? phoneNumber).
//
// Assumes you have:
// - FirestoreService (the unified one we added earlier)
// - A Task model or map with at least: id (taskId), posterId

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/chat_service.dart';
import 'package:servana/widgets/offer_counter_actions.dart';

class ManageOffersScreen extends StatefulWidget {
  final String taskId;
  final String posterId; // for chat/phone display

  const ManageOffersScreen({
    super.key,
    required this.taskId,
    required this.posterId,
  });

  @override
  State<ManageOffersScreen> createState() => _ManageOffersScreenState();
}

class _ManageOffersScreenState extends State<ManageOffersScreen> {
  final _fs = FirestoreService();
  final _chat = ChatService();

  Future<void> _acceptOffer(String offerId) async {
    await _fs.acceptOffer(taskId: widget.taskId, offerId: offerId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offer accepted')),
      );
    }
  }

  Future<void> _openTaskChat() async {
    final channelId =
    await _chat.createOrGetChannel(widget.posterId, taskId: widget.taskId);
    if (!mounted) return;
    // TODO: push your ChatScreen with channelId
    // Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(channelId: channelId)));
  }

  Future<void> _callPoster() async {
    final phone = await _fs.getUserPhone(widget.posterId);
    final number = phone; // tolerant already (phone ?? phoneNumber)
    if (number == null || number.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number found')),
      );
      return;
    }
    // TODO: launchUrl(Uri.parse('tel:$number'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offers')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _fs.streamOffersForTask(widget.taskId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return const Center(child: Text('No offers yet'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final offer = docs[i].data();
              final offerId = docs[i].id;
              final helperId = offer['createdBy'] as String?;
              final price = offer['price'];
              final note = offer['note'] ?? offer['message'] ?? '';
              final status = offer['status'] as String?;

              return ListTile(
                title: Text('Offer: ${price ?? '-'}'),
                subtitle: Text(note.toString()),
                trailing: (status == 'counter')
                  ? OfferCounterActions(offerDocRef: docs[i].reference, padding: EdgeInsets.zero)
                  : Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: () => _acceptOffer(offerId),
                      child: const Text('Accept'),
                    ),
                    OutlinedButton(
                      onPressed: _openTaskChat,
                      child: const Text('Chat'),
                    ),
                  ],
                ),
                onTap: _callPoster,
              );
            },
          );
        },
      ),
    );
  }
}