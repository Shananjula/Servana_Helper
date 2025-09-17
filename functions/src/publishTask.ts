// functions/src/publishTask.ts
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// Initialize Firebase Admin outside the function to avoid re-initialization
try { admin.app(); } catch { admin.initializeApp(); }
const db = admin.firestore();
const FEES = {
  POST_MIN_BALANCE: 500,
  POST_FEE: 20
};

type PlatformPosting = {
  posting?: {
    minBalanceCoins?: number,
    feePercent?: number,
    minFeeCoins?: number,
    maxFeeCoins?: number,
  }
};

/**
 * Reads the available servCoinBalance from a Firestore document.
 * Handles various field names and ensures the value is a valid number.
 * @param u The user document data.
 * @returns The servCoinBalance, or 0 if not found or invalid.
 */
function readCoins(u: FirebaseFirestore.DocumentData | undefined): number {
  if (!u) return 0;
  for (const f of ["servCoinBalance", "walletBalance", "coins"]) {
    const v = u[f];
    if (typeof v === "number" && isFinite(v)) return v;
  }
  return 0;
}

/**
 * Updates a record with a new balance, ensuring consistency across different field names.
 * @param update The record to update.
 * @param newBalance The new coin balance to write.
 */
function writeCoins(update: Record<string, unknown>, newBalance: number) {
  update["servCoinBalance"] = newBalance;
  update["walletBalance"] = newBalance;
  update["coins"] = newBalance;
}

/**
 * Picks the primary budget value from a task object.
 * @param task The task data.
 * @returns The budget amount.
 */
function pickBudget(task: any): number {
  const n = (x: any) => (typeof x === "number" ? x : 0);
  return Math.max(n(task?.budget), n(task?.price), n(task?.budgetMin));
}

/**
 * The main callable function to publish a task and deduct a fee.
 * This function uses a Firestore transaction to ensure atomicity and idempotency.
 */
export const publishTask = functions.https.onCall(async (data, ctx) => {
  if (!ctx.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to publish a task.");
  }
  const uid = ctx.auth.uid!;
  const { taskId, taskPayload } = data; // Assuming taskPayload contains the task details

  if (!taskId || !taskPayload) {
    throw new functions.https.HttpsError("invalid-argument", "Task ID and payload are required.");
  }

  const db = admin.firestore();

  await db.runTransaction(async (tx) => {
    // Read the poster's balance and platform settings
    const posterRef = db.doc(`users/${uid}`);
    const settingsRef = db.doc('settings/platform');
    const [posterSnap, settingsSnap] = await Promise.all([
      tx.get(posterRef), tx.get(settingsRef)
    ]);
    const posterBal = readCoins(posterSnap.data());

    // Read configured fees from settings, using defaults if not set
    const configuredMin = Number((settingsSnap.data() || {}).posting?.minBalanceCoins ?? FEES.POST_MIN_BALANCE);
    const configuredPostFee = Number((settingsSnap.data() || {}).posting?.postFeeCoins ?? FEES.POST_FEE);

    // Enforce hard floors for minimum balance and post fee
    const MIN = Math.max(configuredMin, FEES.POST_MIN_BALANCE);
    const POST_FEE = Math.max(configuredPostFee, 0);

    // Gate: Check if the poster has enough balance
    if (posterBal < MIN + POST_FEE) {
      throw new functions.https.HttpsError('failed-precondition', 'Insufficient funds to post the task and pay the fee.');
    }

    // Use the provided task ID for idempotency
    const taskRef = db.collection('tasks').doc(taskId);
    const ledgerRef = db.doc(`wallet_ledger/post_fee:${taskId}`);
    const ledgerSnap = await tx.get(ledgerRef);

    // Check if the task already exists
    const taskSnap = await tx.get(taskRef);
    if (taskSnap.exists && (taskSnap.data()?.status === 'open' || taskSnap.data()?.status === 'listed')) {
        // The task is already published, handle idempotently
        return;
    }

    // Create the task document with a status of 'listed'
    const now = admin.firestore.FieldValue.serverTimestamp();
    tx.set(taskRef, {
      ...taskPayload,
      id: taskId,
      posterId: uid,
      status: 'listed',
      createdAt: now,
      updatedAt: now,
    });

    // Charge POST_FEE exactly once (idempotent check on the ledger doc)
    if (!ledgerSnap.exists && POST_FEE > 0) {
      // Deduct the fee from the poster's balance
      const newBalance = posterBal - POST_FEE;
      const posterUpdate: Record<string, unknown> = {
        updatedAt: now,
        balance: newBalance
      };
      writeCoins(posterUpdate, newBalance);
      tx.update(posterRef, posterUpdate);

      // Create a ledger entry for the fee
      tx.set(ledgerRef, {
        uid,
        kind: 'post_fee',
        amount: -POST_FEE,
        taskId,
        uniqueKey: `post_fee:${taskId}`,
        createdAt: now,
      });
    }
  });

  return { ok: true, message: `Task ${taskId} published successfully.` };
});
