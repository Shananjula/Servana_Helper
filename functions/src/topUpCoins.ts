
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

function assertAuth(context: functions.https.CallableContext) {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  return context.auth.uid;
}

/**
 * topUpCoins (DEV/TEST or post-payment credit)
 * Request: { amount: number, idempotencyKey?: string }
 * Behavior:
 *  - amount must be positive integer (coins)
 *  - idempotent on idempotencyKey if provided
 *  - increments users/{uid}.servCoinBalance
 *  - writes users/{uid}/transactions/{doc} with type:'topup'
 */
export const topUpCoins = functions.https.onCall(async (data, context) => {
  const uid = assertAuth(context);
  const rawAmt = Number(data?.amount ?? 0);
  const idempotencyKey: string | null = data?.idempotencyKey ?? null;

  if (!Number.isFinite(rawAmt) || rawAmt <= 0) {
    throw new functions.https.HttpsError("invalid-argument", "Amount must be > 0.");
  }
  const amount = Math.floor(rawAmt);

  const userRef = db.doc(`users/${uid}`);
  const txnRef = idempotencyKey
    ? db.doc(`users/${uid}/transactions/${idempotencyKey}`)
    : db.collection(`users/${uid}/transactions`).doc();

  await db.runTransaction(async (tx) => {
    const [userSnap, txnSnap] = await Promise.all([tx.get(userRef), tx.get(txnRef)]);

    // Idempotent
    if (txnSnap.exists) return;

    if (!userSnap.exists) {
      throw new functions.https.HttpsError("failed-precondition", "User profile not found.");
    }

    tx.update(userRef, {
      servCoinBalance: admin.firestore.FieldValue.increment(amount),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.set(txnRef, {
      userId: uid,
      type: "topup",
      amount: amount,
      status: "succeeded",
      unit: "coins",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  // Return fresh snapshot
  const fresh = await userRef.get();
  const coins = Number(fresh.data()?.servCoinBalance ?? 0);
  return { ok: true, balance: coins, amount };
});
