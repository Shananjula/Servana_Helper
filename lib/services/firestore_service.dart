// lib/services/firestore_service.dart
//
// Full Firestore service (app-wide helpers)
// -------------------------------------------------------------
// What this covers:
// • Users     : get/listen/update, presence (Go Live)
// • Tasks     : create/update/assign/cancel/proof, streams (poster/helper)
// • Offers    : top-level offers (optional) + chat-based offers (messages)
// • Chat      : deterministic channel, last-message updates
// • Services  : CRUD on helper services
// • SavedSearch: create saved filter alerts
// • Wallet/Tx : transactions + wallet increment/decrement
// • Contact ledger (first-time direct contact)
//
// Notes:
// • Security/fees should be enforced in Firestore rules + Cloud Functions.
// • All writes are merge-safe (SetOptions(merge: true)) unless a new doc.
// • Streams return QuerySnapshot/DocSnapshot so your UI can decide mapping.
// • If your old code used different names, see the shim area near the end.
//
// Dependencies: cloud_firestore

import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
static const List<String> kAllowedPublicStatuses = [
  'open', 'listed', 'negotiating', 'negotiation',
];

  FirestoreService._();
  static final FirestoreService instance = FirestoreService._();
  factory FirestoreService() => instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // -------------------------------
  // USERS
  // -------------------------------

  Future<DocumentSnapshot<Map<String, dynamic>>> getUserDoc(String uid) {
    return _db.collection('users').doc(uid).get();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> listenUserDoc(String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }

  Future<void> updateUserFields(String uid, Map<String, dynamic> patch) async {
    await _db.collection('users').doc(uid).set(
      {
        ...patch,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // Presence (Go Live)
  Future<void> setPresence({
    required String uid,
    required bool isLive,
    double? lat,
    double? lng,
    int ttlMinutes = 5,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final presence = <String, dynamic>{
      'uid': uid,
      'isLive': isLive,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      'lastSeen': FieldValue.serverTimestamp(),
      'ttl': now + 1000 * 60 * ttlMinutes,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Mirror under users/{uid}.presence (nice for profile reads)
    await _db.collection('users').doc(uid).set({'presence': presence}, SetOptions(merge: true));

    // Flat presence/{uid} for map fan-out queries
    await _db.collection('presence').doc(uid).set(presence, SetOptions(merge: true));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamLiveHelpers({int limit = 300}) {
    return _db
        .collection('presence')
        .where('isLive', isEqualTo: true)
        .limit(limit)
        .snapshots();
  }

  // -------------------------------
  // TASKS
  // -------------------------------

  Future<String> createTask(Map<String, dynamic> data) async {
    final ref = _db.collection('tasks').doc();
    await ref.set({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateTaskFields(String taskId, Map<String, dynamic> patch) async {
    await _db.collection('tasks').doc(taskId).set(
      {
        ...patch,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> assignTask(String taskId, String helperId) async {
    await _db.collection('tasks').doc(taskId).set(
      {
        'helperId': helperId,
        'status': 'assigned',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> cancelTask(
      String taskId, {
        required String by, // 'poster' | 'helper' | 'system'
        String? reason,
        num? feeEstimate,
      }) async {
    await _db.collection('tasks').doc(taskId).set(
      {
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
        'history': {'cancelAt': FieldValue.serverTimestamp()},
        'cancel': {
          'by': by,
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
          if (feeEstimate != null) 'feeEstimate': feeEstimate,
        }
      },
      SetOptions(merge: true),
    );
  }

  Future<void> addTaskProofUrl(String taskId, String url) async {
    await _db.collection('tasks').doc(taskId).set(
      {
        'proofUrls': FieldValue.arrayUnion([url]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // Streams by poster/helper + status groups
  Stream<QuerySnapshot<Map<String, dynamic>>> streamTasksForPoster(
      String posterId, {
        List<String>? statuses,
        int limit = 120,
      }) {
    Query<Map<String, dynamic>> q = _db
        .collection('tasks')
        .where('posterId', isEqualTo: posterId);

    if (statuses != null && statuses.isNotEmpty && statuses.length <= 10) {
      q = q.where('status', whereIn: statuses);
    }
    q = q.orderBy('createdAt', descending: true).limit(limit);
    return q.snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamTasksForHelper(
      String helperId, {
        List<String>? statuses,
        int limit = 120,
      }) {
    Query<Map<String, dynamic>> q = _db
        .collection('tasks')
        .where('helperId', isEqualTo: helperId);

    if (statuses != null && statuses.isNotEmpty && statuses.length <= 10) {
      q = q.where('status', whereIn: statuses);
    }
    q = q.orderBy('updatedAt', descending: true).limit(limit);
    return q.snapshots();
  }

  // Public “listed/open” tasks (filter by category/type client-side if needed)
  Stream<QuerySnapshot<Map<String, dynamic>>> streamListedTasks({
    List<String>? categories, // normalized ids, max 10 if used in whereIn
    String? type, // 'online' | 'physical'
    int limit = 250,
  }) {
    Query<Map<String, dynamic>> q =
    _db.collection('tasks').where('status', whereIn: ['open', 'listed']);
    if (type != null && type.isNotEmpty) {
      q = q.where('type', isEqualTo: type);
    }
    if (categories != null && categories.isNotEmpty) {
      q = q.where('category', whereIn: categories.take(10).toList());
    }
    return q.orderBy('createdAt', descending: true).limit(limit).snapshots();
  }

  // -------------------------------
  // OFFERS (Top-level optional API)
  // -------------------------------

  // If you have a top-level /offers collection in addition to chat-based offers, use these:
  Future<String> createOfferDoc({
    required String taskId,
    required String posterId,
    required String helperId,
    num? amount,
    String? message,
  }) async {
    // Coins gate: require minimum coins to even place an offer
    final uref = _db.collection('users').doc(helperId);
    final usnap = await uref.get();
    final um = usnap.data() ?? {};
    final bal = (um['walletBalance'] is num) ? (um['walletBalance'] as num).toInt() : 0;
    const minCoins = 400; // fallback; can be read from remote config
    if (bal < minCoins) {
      throw Exception('INSUFFICIENT_COINS');
    }

    final ref = _db.collection('offers').doc();
    await ref.set({
      'taskId': taskId,
      'posterId': posterId,
      'helperId': helperId,
      if (amount != null) 'price': amount,
      if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> setOfferStatus(String offerId, String status) async {
    await _db.collection('offers').doc(offerId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamOffersForTask(String taskId, {int limit = 200}) {
    return _db
        .collection('offers')
        .where('taskId', isEqualTo: taskId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  // -------------------------------
  // CHAT + CHAT-BASED OFFERS
  // -------------------------------

  String channelIdFor(String a, String b) => (a.compareTo(b) < 0) ? '${a}_$b' : '${b}_$a';

  Future<String> createOrGetChannel(String a, String b, {String? taskId}) async {
    final id = channelIdFor(a, b);
    final ref = _db.collection('chats').doc(id);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'participants': [a, b],
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        if (taskId != null) 'taskId': taskId,
      }, SetOptions(merge: true));
    } else if (taskId != null && (snap.data()?['taskId'] is! String)) {
      await ref.set({'taskId': taskId}, SetOptions(merge: true));
    }
    return id;
  }

  Future<void> sendOfferMessage({
    required String channelId,
    required String senderId,
    required double amount,
    String? note,
  }) async {
    final msgRef = _db.collection('chats').doc(channelId).collection('messages').doc();
    await msgRef.set({
      'type': 'offer',
      'senderId': senderId,
      'offerAmount': amount,
      if (note != null && note.trim().isNotEmpty) 'offerNote': note.trim(),
      'offerStatus': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
    await _db.collection('chats').doc(channelId).set({
      'lastMessage': 'Offer: LKR ${amount.toStringAsFixed(0)}',
      'lastMessageSenderId': senderId,
      'lastMessageTimestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Accept a chat-based offer (assign task to helper who sent the offer)
  Future<String?> acceptOffer(String taskId, String offerMessageId) async {
    final q = await _db
        .collectionGroup('messages')
        .where(FieldPath.documentId, isEqualTo: offerMessageId)
        .limit(1)
        .get();

    if (q.docs.isEmpty) return null;
    final doc = q.docs.first;
    final msg = doc.data() as Map<String, dynamic>;
    if ((msg['type'] ?? '') != 'offer') return null;

    final helperId = (msg['senderId'] ?? '') as String?; // helper who sent the offer
    if (helperId == null || helperId.isEmpty) return null;

    final chatRef = doc.reference.parent.parent;

    await _db.runTransaction((trx) async {
      trx.update(doc.reference, {
        'offerStatus': 'accepted',
        'timestamp': FieldValue.serverTimestamp(),
      });

      final taskRef = _db.collection('tasks').doc(taskId);
      trx.set(taskRef, {
        'status': 'assigned',
        'helperId': helperId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (chatRef != null) {
        trx.set(chatRef, {
          'lastMessage': 'Offer accepted',
          'lastMessageTimestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });

    return helperId;
  }

  Future<void> declineOffer(String taskId, String offerMessageId) async {
    final q = await _db
        .collectionGroup('messages')
        .where(FieldPath.documentId, isEqualTo: offerMessageId)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return;

    final doc = q.docs.first;
    final msg = doc.data() as Map<String, dynamic>;
    if ((msg['type'] ?? '') != 'offer') return;

    final chatRef = doc.reference.parent.parent;

    await _db.runTransaction((trx) async {
      trx.update(doc.reference, {
        'offerStatus': 'declined',
        'timestamp': FieldValue.serverTimestamp(),
      });
      if (chatRef != null) {
        trx.set(chatRef, {
          'lastMessage': 'Offer declined',
          'lastMessageTimestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  // -------------------------------
  // SERVICES (helper listings)
  // -------------------------------

  Stream<QuerySnapshot<Map<String, dynamic>>> streamHelperServices(String uid, {int limit = 200}) {
    return _db
        .collection('services')
        .where('helperId', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Future<String> createService(Map<String, dynamic> data) async {
    final ref = _db.collection('services').doc();
    await ref.set({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateService(String serviceId, Map<String, dynamic> patch) async {
    await _db.collection('services').doc(serviceId).set(
      {
        ...patch,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> toggleServiceActive(String serviceId, bool isActive) async {
    await _db.collection('services').doc(serviceId).set(
      {'isActive': isActive, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> deleteService(String serviceId) async {
    await _db.collection('services').doc(serviceId).delete();
  }

  // -------------------------------
  // SAVED SEARCHES
  // -------------------------------

  Future<String> createSavedSearch(String uid, Map<String, dynamic> filters, {String? name}) async {
    final ref = _db.collection('saved_searches').doc();
    await ref.set({
      'userId': uid,
      'name': (name == null || name.trim().isEmpty) ? 'My saved search' : name.trim(),
      'filters': filters,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  // -------------------------------
  // WALLET & TRANSACTIONS
  // -------------------------------

  Future<String> createTransaction({
    required String uid,
    required String type, // 'topup'|'commission'|'direct_contact_fee'|'post_gate'|'refund'|'payout'|'milestone'
    required int amount,
    String status = 'ok', // ok|pending|failed|refunded
    String? note,
  }) async {
    final tx = _db.collection('transactions').doc();
    await tx.set({
      'userId': uid,
      'type': type,
      'amount': amount,
      'status': status,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return tx.id;
  }

  Future<int> incrementWallet(String uid, int delta) async {
    return _db.runTransaction<int>((trx) async {
      final ref = _db.collection('users').doc(uid);
      final snap = await trx.get(ref);
      final m = snap.data() as Map<String, dynamic>? ?? {};
      final current = (m['walletBalance'] is num) ? (m['walletBalance'] as num).toInt() : 0;
      final next = current + delta;
      trx.set(ref, {
        'walletBalance': next,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return next;
    });
  }

  // -------------------------------
  // CONTACT LEDGER (first-time direct contact)
  // -------------------------------

  String _contactDocId(String posterId, String helperId) =>
      (posterId.compareTo(helperId) < 0) ? '${posterId}_$helperId' : '${helperId}_$posterId';

  Future<bool> hasContactLedger(String posterId, String helperId) async {
    final id = _contactDocId(posterId, helperId);
    final snap = await _db.collection('contacts').doc(id).get();
    return snap.exists && (snap.data()?['charged'] == true);
  }

  Future<void> markContactLedger(String posterId, String helperId) async {
    final id = _contactDocId(posterId, helperId);
    await _db.collection('contacts').doc(id).set({
      'posterId': posterId,
      'helperId': helperId,
      'charged': true,
      'firstContactAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // =========================================================
  // SHIMS for older codebases (method aliases/back-compat)
  // =========================================================

  // Old name: updateTaskStatus(taskId, status)
  Future<void> updateTaskStatus(String taskId, String status) =>
      updateTaskFields(taskId, {'status': status});

  // Old name: addProof(taskId, url)
  Future<void> addProof(String taskId, String url) => addTaskProofUrl(taskId, url);

  // Old name: createOffer(...) → route to top-level offer doc
  Future<String> createOffer({
    required String taskId,
    required String posterId,
    required String helperId,
    num? amount,
    String? message,
  }) =>
      createOfferDoc(
        taskId: taskId,
        posterId: posterId,
        helperId: helperId,
        amount: amount,
        message: message,
      );

  // ===== Legacy shim helpers (place INSIDE class FirestoreService) =====
  Future<DocumentSnapshot<Map<String, dynamic>>> getTaskDoc(String taskId) =>
      _db.collection('tasks').doc(taskId).get();

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamTaskDoc(String taskId) =>
      _db.collection('tasks').doc(taskId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> streamChatMessages(String channelId, {int limit = 200}) =>
      _db.collection('chats').doc(channelId).collection('messages')
          .orderBy('timestamp').limit(limit).snapshots();

  Future<void> sendTextMessage(String channelId, String senderId, String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final ref = _db.collection('chats').doc(channelId);
    await ref.collection('messages').add({
      'type': 'text', 'text': t, 'senderId': senderId, 'timestamp': FieldValue.serverTimestamp(),
    });
    await ref.set({
      'lastMessage': t, 'lastMessageSenderId': senderId, 'lastMessageTimestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> addFcmToken(String uid, String token) async =>
      _db.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]), 'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Stream<QuerySnapshot<Map<String, dynamic>>> streamTransactions(String uid, {int limit = 200}) =>
      _db.collection('transactions').where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true).limit(limit).snapshots();

  Future<DocumentSnapshot<Map<String, dynamic>>> getServiceDoc(String serviceId) =>
      _db.collection('services').doc(serviceId).get();

  Stream<QuerySnapshot<Map<String, dynamic>>> streamReviewsForUser(String revieweeId, {int limit = 50}) =>
      _db.collection('reviews').where('revieweeId', isEqualTo: revieweeId)
          .orderBy('createdAt', descending: true).limit(limit).snapshots();


  /// Internal helper to add/subtract coins in a transaction.
  Future<void> _applyWalletDeltaInTrx(Transaction trx, String uid, int delta) async {
    if (uid.isEmpty || delta == 0) return;
    final uref = _db.collection('users').doc(uid);
    final snap = await trx.get(uref);
    final m = snap.data() as Map<String, dynamic>? ?? {};
    final prev = (m['walletBalance'] is num) ? (m['walletBalance'] as num).toInt() : 0;
    final next = prev + delta;
    trx.set(uref, {
      'walletBalance': next,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }


  // -------------------------------------------------
  // ECONOMY HELPERS (coins gate + commission preview)
  // -------------------------------------------------

  /// Reads `users/{uid}.walletBalance` and checks if user meets the gate.
  Future<bool> hasMinCoinsToApply(String uid, {int minCoins = 400}) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      final m = snap.data() ?? {};
      final bal = (m['walletBalance'] is num) ? (m['walletBalance'] as num).toInt() : 0;
      return bal >= minCoins;
    } catch (_) {
      return false;
    }
  }

  /// Computes commission in coins for a given offer price.
  int commissionCoinsForPrice(num priceLkr, {int pct = 10}) {
    final raw = (priceLkr * pct) / 100.0;
    return raw.ceil();
  }

  // -------------------------------------------------
  // TIMELINE (audit trail per task) - additive
  // -------------------------------------------------
  Future<void> addTimelineEvent(
    String taskId,
    String type, {
    String? note,
    Map<String, dynamic>? data,
  }) async {
    final event = <String, dynamic>{
      'type': type, // e.g., 'en_route'|'arrived'|'in_progress'|'pending_completion'|'note'
      'note': note,
      'data': data,
      'ts': FieldValue.serverTimestamp(),
    };
    await _db.collection('tasks').doc(taskId).set({
      'timeline': FieldValue.arrayUnion([event]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }


// NEW: Public marketplace (rule-compliant)
// Requires server-side category gating (<=10) + allowed statuses.
// Uses 'categoryId' (normalized id). If your data still has 'category' names,
// temporarily switch the where() field below until migration completes.
Stream<QuerySnapshot<Map<String, dynamic>>> streamListedTasksGated({
  required List<String> categoryIds,  // normalized ids; <= 10
  String? type,                       // 'online' | 'physical'
  int limit = 250,
}) {
  if (categoryIds.isEmpty) {
    return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
  }

  Query<Map<String, dynamic>> q = _db.collection('tasks')
    .where('categoryId', whereIn: categoryIds.take(10).toList())
    .where('status', whereIn: kAllowedPublicStatuses);

  if (type != null && type.isNotEmpty) {
    q = q.where('type', isEqualTo: type);
  }

  return q.limit(limit).snapshots();
}


Future<void> settleTaskPayment({
  required String taskId,
  required String posterId,
  required String helperId,
  required num amount,     // base amount
  num tipAmount = 0,       // optional
}) async {
  final taskRef   = _db.collection('tasks').doc(taskId);
  final posterRef = _db.collection('users').doc(posterId);
  final helperRef = _db.collection('users').doc(helperId);

  final posterTxRef = _db.collection('transactions').doc(); // root-level
  final helperTxRef = _db.collection('transactions').doc();

  await _db.runTransaction((trx) async {
    // 1) Ensure task is in the right state (idempotency)
    final taskSnap = await trx.get(taskRef);
    if (!taskSnap.exists) {
      throw StateError('Task not found');
    }
    final t = taskSnap.data() as Map<String, dynamic>;
    final status = (t['status'] ?? '') as String;

    if (status == 'pending_rating') {
      // Already settled → noop for idempotency
      return;
    }
    if (status != 'pending_payment') {
      throw StateError('Task is not in pending_payment state');
    }

    // 2) Compute totals
    final total = (amount) + (tipAmount);
    if (total < 0) throw StateError('Total cannot be negative');

    // 3) Adjust wallet balances (FieldValue.increment creates if missing)
    trx.set(posterRef, {
      'walletBalance': FieldValue.increment(-total),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    trx.set(helperRef, {
      'walletBalance': FieldValue.increment(total),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final now = FieldValue.serverTimestamp();

    // 4) Write transactions (root-level, with userId)
    trx.set(posterTxRef, {
      'userId': posterId,
      'type': 'debit_task',
      'taskId': taskId,
      'counterparty': helperId,
      'amount': -total,
      'baseAmount': amount,
      'tipAmount': tipAmount,
      'createdAt': now,
    });

    trx.set(helperTxRef, {
      'userId': helperId,
      'type': 'credit_task',
      'taskId': taskId,
      'counterparty': posterId,
      'amount': total,
      'baseAmount': amount,
      'tipAmount': tipAmount,
      'createdAt': now,
    });

    // 5) Advance task
    trx.update(taskRef, {
      'status': 'pending_rating',
      'paymentCompletedAt': now,
      'tipAmount': tipAmount,
      'updatedAt': now,
    });
  });
}
}
