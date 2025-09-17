
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

const FEES = {
  DIRECT_DM_FEE: 50,   // poster pays on invite/DM
} as const;

function assertAuth(context: functions.https.CallableContext) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }
  return context.auth.uid;
}

/**
 * chargeDirectContactFee
 * Poster initiates a direct contact (invite/DM) to a helper for a category (and optional task).
 * - Charges POSTER 50 coins (idempotent).
 * - Writes a ledger transaction in users/{posterId}/transactions.
 * - Writes an invites/{inviteId} document with origin:'direct' (optional but recommended).
 */
export const chargeDirectContactFee = functions.https.onCall(async (data, context) => {
  const posterId = assertAuth(context);
  const helperId: string = data?.helperId;
  const categoryId: string = data?.categoryId;
  const taskId: string | null = data?.taskId ?? null;

  if (!helperId || !categoryId) {
    throw new functions.https.HttpsError("invalid-argument", "helperId and categoryId are required.");
  }

  const posterRef = db.doc(`users/${posterId}`);
  const helperRef = db.doc(`users/${helperId}`);

  // Build idempotency keys
  const uniq = `dm:${taskId ?? "none"}:${posterId}:${helperId}:${categoryId}`;
  const txnRef = db.doc(`users/${posterId}/transactions/${uniq}`);
  const inviteRef = db.doc(`invites/${uniq}`);

  await db.runTransaction(async (tx) => {
    const [posterSnap, helperSnap, txnSnap] = await Promise.all([
      tx.get(posterRef),
      tx.get(helperRef),
      tx.get(txnRef),
    ]);

    if (!posterSnap.exists) {
      throw new functions.https.HttpsError("failed-precondition", "Poster profile not found.");
    }
    if (!helperSnap.exists) {
      throw new functions.https.HttpsError("failed-precondition", "Helper profile not found.");
    }

    // Idempotent: if a transaction already exists, do nothing
    if (txnSnap.exists) {
      return;
    }

    const poster = posterSnap.data() || {};
    const helper = helperSnap.data() || {};

    const bal = Number(poster.servCoinBalance ?? 0);
    if (bal < FEES.DIRECT_DM_FEE) {
      throw new functions.https.HttpsError("failed-precondition", "INSUFFICIENT_COINS");
    }

    // Eligibility check (server-side safety): helper must be allowed for categoryId
    const allowed: string[] = Array.isArray(helper.allowedCategoryIds) ? helper.allowedCategoryIds : [];
    if (!allowed.includes(categoryId)) {
      throw new functions.https.HttpsError("failed-precondition", "HELPER_NOT_ELIGIBLE_FOR_CATEGORY");
    }

    // Decrement poster balance & write ledger row
    tx.update(posterRef, { servCoinBalance: admin.firestore.FieldValue.increment(-FEES.DIRECT_DM_FEE) });
    tx.set(txnRef, {
      type: "direct_contact_fee",
      amount: -FEES.DIRECT_DM_FEE,
      status: "succeeded",
      userId: posterId,
      helperId,
      categoryId,
      taskId,
      uniqueKey: uniq,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Optional: record invite for audit / UI. Rules allow poster to read.
    tx.set(inviteRef, {
      posterId,
      helperId,
      categoryId,
      taskId,
      origin: "direct",
      status: "sent",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true, inviteId: uniq, txnId: uniq };
});
