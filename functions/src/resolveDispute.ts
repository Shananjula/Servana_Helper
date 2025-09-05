// functions/src/resolveDispute.ts
// Minimal, safe dispute resolver.
// Writes the resolution into /disputes/{disputeId}. You can connect wallet/coins later.

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

try { admin.app(); } catch { admin.initializeApp(); }
const db = admin.firestore();

export const resolveDispute = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Sign in required.');
  }

  const {
    disputeId,
    resolution,
    notes,
    posterCoinDelta,
    helperCoinDelta,
  } = (data || {}) as {
    disputeId?: string;
    resolution?: string;
    notes?: string;
    posterCoinDelta?: number;
    helperCoinDelta?: number;
  };

  if (!disputeId || !resolution) {
    throw new functions.https.HttpsError('invalid-argument', 'Provide disputeId and resolution.');
  }

  const disputeRef = db.collection('disputes').doc(disputeId);
  const snap = await disputeRef.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', `Dispute ${disputeId} not found.`);
  }

  await disputeRef.set({
    status: 'resolved',
    resolution,
    notes: notes ?? null,
    resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    resolvedBy: context.auth.uid,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    posterCoinDelta: typeof posterCoinDelta === 'number' ? posterCoinDelta : null,
    helperCoinDelta: typeof helperCoinDelta === 'number' ? helperCoinDelta : null,
  }, { merge: true });

  return { ok: true, disputeId, resolution };
});
