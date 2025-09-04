import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class QuickRepliesService {
  static const defaultReplies = <String>[
    'On my way 🙂',
    'I’ve arrived at the location.',
    'Running 10–15 mins late, sorry.',
  ];

  static Stream<List<String>> streamReplies() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(defaultReplies);
    return FirebaseFirestore.instance
        .collection('users').doc(uid)
        .snapshots()
        .map((d) {
      final arr = (d.data()?['quickReplies'] as List?)?.cast<String>() ?? defaultReplies;
      return arr.take(6).toList(); // cap
    });
  }

  static Future<void> saveReplies(List<String> items) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final pruned = items.map((e) => e.trim()).where((e) => e.isNotEmpty).take(6).toList();
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'quickReplies': pruned,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
