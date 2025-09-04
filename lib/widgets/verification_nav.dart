// lib/utils/verification_nav.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../screens/step_2_documents.dart';

/// Ensures the user is eligible for the given categoryId.
/// If not, navigates to Step2Documents(initialCategoryId: categoryId) and returns false.
/// If eligible, returns true.
class VerificationNav {
  static Future<bool> ensureEligibleOrRedirect(BuildContext context, String categoryId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = snap.data() ?? {};
      final list = data['allowedCategoryIds'];
      final allowed = (list is List) ? list.map((e) => e.toString()).toSet() : <String>{};
      if (allowed.contains(categoryId)) {
        return true;
      }
      // Not eligible yet — redirect to verification
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Step2Documents(initialCategoryId: categoryId),
      ));
      return false;
    } catch (_) {
      // On errors, redirect to verification to be safe
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Step2Documents(initialCategoryId: categoryId),
      ));
      return false;
    }
  }
}
