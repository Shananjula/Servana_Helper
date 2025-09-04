// functions/src/createTopUp.ts
// Dev/Starter Cloud Function for top-ups (no gateway).
// - Validates amount
// - Writes a completed 'topup' transaction
// - Increments users/{uid}.walletBalance
// Replace with real gateway flow in production.

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();
const db = admin.firestore();

export const createTopUp = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  const uid = context.auth.uid;
  const amount = Number(data.amount || 0);
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid amount');
  }

  const txRef = db.collection('transactions').doc();
  const userRef = db.collection('users').doc(uid);

  await db.runTransaction(async (trx) => {
    const userSnap = await trx.get(userRef);
    const user = userSnap.data() || {};
    const bal = Number(user.walletBalance || 0);

    trx.set(txRef, {
      userId: uid,
      type: 'topup',
      amount: amount,
      status: 'ok',
      direction: 'credit',
      note: 'CloudFunction top-up (dev)',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    trx.set(userRef, {
      walletBalance: bal + amount,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });

  return { ok: true };
});
