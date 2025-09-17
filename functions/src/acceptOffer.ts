import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();
const FEES = {
  HELPER_ACCEPT_FEE: 25, // charged only for public offers
} as const;

export const acceptOffer = functions.https.onCall(async (data, context) => {
  const posterId = context.auth?.uid;
  if (!posterId) {
    throw new functions.https.HttpsError('unauthenticated', 'The user is not authenticated.');
  }

  const offerId = String(data?.offerId || '');
  if (!offerId) {
    throw new functions.https.HttpsError('invalid-argument', 'offerId required');
  }

  await db.runTransaction(async (tx) => {
    const offerRef = db.doc(`offers/${offerId}`);
    const offerSnap = await tx.get(offerRef);
    if (!offerSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Offer not found');
    }

    const offer = offerSnap.data()!;
    const taskId = String(offer.taskId);
    const helperId = String(offer.helperId);
    const origin = String(offer.origin || 'public');

    const taskRef = db.doc(`tasks/${taskId}`);
    const taskSnap = await tx.get(taskRef);
    if (!taskSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Task not found');
    }
    if (taskSnap.get('posterId') !== posterId) {
      throw new functions.https.HttpsError('permission-denied', 'Not your task.');
    }

    // Charge logic depends on origin
    if (origin === 'public') {
      // Helper pays acceptance fee (idempotent)
      const helperRef = db.doc(`users/${helperId}`);
      const helperSnap = await tx.get(helperRef);
      const bal = Number(helperSnap.get('servCoinBalance') || 0);
      if (bal < FEES.HELPER_ACCEPT_FEE) {
        throw new functions.https.HttpsError('failed-precondition', 'HELPER_NEEDS_TOPUP');
      }

      const ledgerKey = `accept:${offerId}`;
      const ledgerRef = db.doc(`wallet_ledger/${ledgerKey}`);
      const ledgerSnap = await tx.get(ledgerRef);
      if (!ledgerSnap.exists) {
        tx.update(helperRef, {
          servCoinBalance: admin.firestore.FieldValue.increment(-FEES.HELPER_ACCEPT_FEE),
        });
        tx.set(ledgerRef, {
          uid: helperId,
          kind: 'accept_fee',
          amount: -FEES.HELPER_ACCEPT_FEE,
          taskId,
          offerId,
          uniqueKey: ledgerKey,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } else {
      // origin === 'direct' → no helper fee (poster already paid intro at DM time)
    }

    // Flip states
    tx.update(offerRef, {
      status: 'accepted',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(taskRef, {
      status: 'assigned',
      helperId,
      origin,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});
