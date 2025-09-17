// lib/services/offer_actions.dart
// Thin client wrapper around Cloud Functions used for offer negotiation.
// Safe to share across Poster and Helper apps.

import 'package:cloud_functions/cloud_functions.dart';

class OfferActions {
  OfferActions._();
  static final OfferActions instance = OfferActions._();

  HttpsCallable _fn(String name) => FirebaseFunctions.instance.httpsCallable(name);

  /// Poster proposes a counter price (and optional note).
  Future<void> proposeCounter({
    required String offerId,
    required num price,
    String? note,
  }) async {
    final payload = <String, dynamic>{
      'offerId': offerId,
      'price': price,
      if (note != null && note.isNotEmpty) 'note': note,
    };
    await _fn('proposeCounter').call(payload);
  }

  /// Poster rejects an offer (optional reason).
  Future<void> rejectOffer({
    required String offerId,
    String? reason,
  }) async {
    final payload = <String, dynamic>{
      'offerId': offerId,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    };
    await _fn('rejectOffer').call(payload);
  }

  /// Helper withdraws their offer.
  Future<void> withdrawOffer({
    required String offerId,
  }) async {
    await _fn('withdrawOffer').call({'offerId': offerId});
  }

  /// Helper agrees to the poster's counter.
  Future<void> agreeToCounter({
    required String offerId,
  }) async {
    await _fn('agreeToCounter').call({'offerId': offerId});
  }

  /// Helper counters back with a new price.
  Future<void> helperCounter({
    required String offerId,
    required num price,
  }) async {
    await _fn('helperCounter').call({
      'offerId': offerId,
      'price': price,
    });
  }

  /// Poster accepts an offer (server applies origin-aware fee & assignment).
  Future<void> acceptOffer({
    required String offerId,
  }) async {
    await _fn('acceptOffer').call({'offerId': offerId});
  }
}
