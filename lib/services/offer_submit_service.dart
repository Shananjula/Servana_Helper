// lib/services/offer_submit_service.dart
//
// Helper-side submit function that writes to the canonical path
//   tasks/{taskId}/offers/{autoId}
// and includes taskId + posterId so Poster queries (and Functions) can see it.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';


class OfferSubmitService {
  static Future<void> saveOffer({
    required String taskId,
    required Map<String, dynamic> task,
    required double amount,
    required String note,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw Exception('User not authenticated');
    }

    final posterIdFromTask = task['uid'] ?? task['posterId'];
    final now = FieldValue.serverTimestamp();

    final payload = <String, dynamic>{
      'taskId': taskId,
      'helperId': uid,
      'price': amount,
      'amount': amount,
      'message': note,
      'status': 'pending',
      'origin': 'public', // 👈 set origin to 'public'
      'createdAt': now,
      'updatedAt': now,
      if (posterIdFromTask != null && posterIdFromTask.isNotEmpty) 'posterId': posterIdFromTask,
    };

    final taskOffersRef = FirebaseFirestore.instance.collection('tasks').doc(taskId).collection('offers');

    final existingOffers = await taskOffersRef
        .where('helperId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existingOffers.docs.isNotEmpty) {
      await existingOffers.docs.first.reference.update(payload);
    } else {
      await taskOffersRef.add(payload);
    }
  }
}
