// lib/services/offer_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:servana/utils/category_utils.dart';

class OfferService {
  final _db = FirebaseFirestore.instance;

  Future<void> createOffer({
    required String taskId,
    required num price,
    String? message,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // Load task for tokens
    final tSnap = await _db.collection('tasks').doc(taskId).get();
    if (!tSnap.exists) {
      throw 'Task not found';
    }
    final t = tSnap.data()!;
    // Try to use server tokens; if missing, compute from categoryIds/legacy id
    final tokens = List<String>.from(t['categoryTokens'] ?? const []);
    List<String> taskTokens = tokens;
    if (taskTokens.isEmpty) {
      final meta = computeMetaForCategories(t['categoryIds'] ?? t['categoryId']);
      taskTokens = meta.categoryTokens;
    }

    // Load helper allowed categories
    final uSnap = await _db.collection('users').doc(uid).get();
    final allowed = List<String>.from(uSnap.data()?['allowedCategoryIds'] ?? const []);
    if (allowed.isEmpty) {
      throw 'Your profile is not verified for any categories';
    }

    final match = findMatchingToken(taskTokens: taskTokens, helperAllowedIds: allowed);
    if (match == null) {
      throw 'You are not eligible for any of this task’s categories';
    }

    await _db
        .collection('tasks')
        .doc(taskId)
        .collection('offers')
        .add({
      'createdBy': uid,
      'price': price,
      'message': (message ?? '').trim(),
      'status': 'pending',
      'matchCategoryId': match,               // <-- rules will validate this
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
