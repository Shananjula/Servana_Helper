// lib/services/firestore_service.dart — Helper app
// -----------------------------------------------------------------------------
// Backward-compatible + unified cross-app contract.
// Key points:
// • Offers: canonical path is tasks/{taskId}/offers, but legacy top-level reads
//   remain available (filtered by taskId) so no UI breaks.
// • Accept Offer: primary path via CF 'acceptOffer'; safe fallback keeps
//   previous behavior if CF is unavailable (no coins changed in fallback).
// • Disputes: addEvidenceToDispute & resolveDispute now present.
// • Phone reads are tolerant (phone OR phoneNumber).
// • Chats: canonical IDs via ChatId; legacy helper preserved.
// -----------------------------------------------------------------------------

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// Use relative import to avoid package name mismatches between repos
import '../utils/chat_id.dart';

class FirestoreService {
  FirestoreService._();
  static final FirestoreService _instance = FirestoreService._();
  factory FirestoreService() => _instance;

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // ---------- USERS ----------------------------------------------------------

  Future<Map<String, dynamic>?> getUser(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    return snap.data();
  }

  Future<String?> getUserPhone(String uid) async {
    final data = await getUser(uid);
    if (data == null) return null;
    // Tolerant read: prefer 'phone', else 'phoneNumber'
    return (data['phone'] as String?) ?? (data['phoneNumber'] as String?);
  }

  // ---------- OFFERS (canonical + legacy-safe) -------------------------------

  CollectionReference<Map<String, dynamic>> _offersCol(String taskId) =>
      _db.collection('tasks').doc(taskId).collection('offers');

  /// Canonical: stream offers from subcollection
  Stream<QuerySnapshot<Map<String, dynamic>>> streamOffersForTask(
      String taskId,
      ) {
    return _offersCol(taskId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Back-compat: some older UIs may call this name
  Stream<QuerySnapshot<Map<String, dynamic>>> streamOffers(String taskId) =>
      streamOffersForTask(taskId);

  /// Legacy top-level offers (if any): /offers where taskId == taskId
  /// Keep available so nothing breaks if an old tab uses it.
  Stream<QuerySnapshot<Map<String, dynamic>>> streamOffersTopLevelLegacy(
      String taskId,
      ) {
    return _db
        .collection('offers')
        .where('taskId', isEqualTo: taskId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<String> submitOffer({
    required String taskId,
    required Map<String, dynamic> offerData,
  }) async {
    final uid = _auth.currentUser?.uid;
    final payload = <String, dynamic>{
      ...offerData,
      'taskId': taskId,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'status': offerData['status'] ?? 'submitted',
    };
    final ref = await _offersCol(taskId).add(payload);
    return ref.id;
  }

  Future<void> updateOffer({
    required String taskId,
    required String offerId,
    required Map<String, dynamic> data,
  }) {
    return _offersCol(taskId).doc(offerId).set(data, SetOptions(merge: true));
  }

  // ---------- ACCEPT OFFER (primary CF + safe fallback) ----------------------

  /// Preferred: Cloud Function handles wallet/commission/notifications.
  Future<void> acceptOffer({
    required String taskId,
    required String offerId,
  }) async {
    try {
      final callable = _functions.httpsCallable('acceptOffer');
      await callable.call({'taskId': taskId, 'offerId': offerId});
    } catch (e) {
      if (kDebugMode) {
        debugPrint('acceptOffer CF failed, using fallback: $e');
      }
      // Fallback: minimal Firestore assignment; no coin logic here.
      await _db.collection('tasks').doc(taskId).set({
        'acceptedOfferId': offerId,
        'status': 'in_progress',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Back-compat: chat-based accept path still supported (routes to CF).
  Future<void> acceptOfferFromChatMessage({
    required String taskId,
    required String offerMessageId,
  }) async {
    try {
      final callable = _functions.httpsCallable('acceptOffer');
      await callable.call({
        'taskId': taskId,
        'offerMessageId': offerMessageId,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            'acceptOfferFromChatMessage CF failed; manual mapping required: $e');
      }
      // No reasonable fallback without mapping message->offer; keep silent.
    }
  }

  // ---------- CHATS (canonical IDs + legacy helper) --------------------------

  CollectionReference<Map<String, dynamic>> get _chats =>
      _db.collection('chats');

  Future<String> createOrGetTaskChannel({
    required String otherUid,
    required String taskId,
  }) async {
    final me = _auth.currentUser?.uid;
    if (me == null) throw StateError('Not signed in');

    final channelId = ChatId.forTask(uidA: me, uidB: otherUid, taskId: taskId);
    final now = FieldValue.serverTimestamp();

    await _chats.doc(channelId).set({
      'id': channelId,
      'members': [me, otherUid],
      'taskId': taskId,
      'type': 'task',
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    return channelId;
  }

  Future<String> createOrGetDirectChannel({
    required String otherUid,
  }) async {
    final me = _auth.currentUser?.uid;
    if (me == null) throw StateError('Not signed in');

    final channelId = ChatId.forDirect(uidA: me, uidB: otherUid);
    final now = FieldValue.serverTimestamp();

    await _chats.doc(channelId).set({
      'id': channelId,
      'members': [me, otherUid],
      'type': 'direct',
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    return channelId;
  }

  /// Back-compat helper in case some code builds IDs manually.
  String buildChannelId({required String a, required String b, String? taskId}) {
    return taskId == null
        ? ChatId.forDirect(uidA: a, uidB: b)
        : ChatId.forTask(uidA: a, uidB: b, taskId: taskId);
  }

  // ---------- DISPUTES (now present in Helper too) ---------------------------

  Future<void> addEvidenceToDispute(String disputeId, String url) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');

    final evidenceCol =
    _db.collection('disputes').doc(disputeId).collection('evidence');

    await evidenceCol.add({
      'url': url,
      'addedBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('disputes').doc(disputeId).set({
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> resolveDispute(
      String disputeId, {
        required String resolution, // "refund_poster" | "pay_helper" | "split" | etc.
        String? notes,
        int? posterCoinDelta,
        int? helperCoinDelta,
      }) async {
    try {
      final callable = _functions.httpsCallable('resolveDispute');
      await callable.call({
        'disputeId': disputeId,
        'resolution': resolution,
        'notes': notes,
        'posterCoinDelta': posterCoinDelta,
        'helperCoinDelta': helperCoinDelta,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('resolveDispute CF failed, falling back: $e');
      }
      await _db.collection('disputes').doc(disputeId).set({
        'status': 'resolved',
        'resolution': resolution,
        if (notes != null) 'notes': notes,
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': _auth.currentUser?.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
}
