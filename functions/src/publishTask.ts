// functions/src/publishTask.ts
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
try { admin.app(); } catch { admin.initializeApp(); }
const db = admin.firestore();

type PlatformPosting = {
  posting?: {
    minBalanceCoins?: number,
    feePercent?: number,
    minFeeCoins?: number,
    maxFeeCoins?: number,
  }
};

function readCoins(u: FirebaseFirestore.DocumentData | undefined): number {
  if (!u) return 0;
  for (const f of ["servCoinBalance", "walletBalance", "coins"]) {
    const v = u[f];
    if (typeof v === "number" && isFinite(v)) return v;
  }
  return 0;
}
function writeCoins(update: Record<string, unknown>, newBalance: number) {
  update["servCoinBalance"] = newBalance;
  update["walletBalance"] = newBalance;
  update["coins"] = newBalance;
}
function pickBudget(task: any): number {
  const n = (x: any) => (typeof x === "number" ? x : 0);
  return Math.max(n(task?.budget), n(task?.price), n(task?.budgetMin));
}

export const publishTask = functions.https.onCall(async (data, ctx) => {
  if (!ctx.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in.");
  const taskId = data?.taskId as string | undefined;
  const idempotencyKey = data?.idempotencyKey as string | undefined;
  if (!taskId || !idempotencyKey) {
    throw new functions.https.HttpsError("invalid-argument", "taskId & idempotencyKey required.");
  }
  const uid = ctx.auth.uid!;
  const taskRef = db.collection("tasks").doc(taskId);
  const userRef = db.collection("users").doc(uid);
  const settingsRef = db.collection("settings").doc("platform");

  await db.runTransaction(async tx => {
    const [taskSnap, userSnap, setSnap] = await Promise.all([
      tx.get(taskRef), tx.get(userRef), tx.get(settingsRef)
    ]);
    if (!taskSnap.exists) throw new functions.https.HttpsError("not-found", "Task missing.");
    const task = taskSnap.data()!;
    const owner = (task.posterId ?? task.createdBy ?? uid);
    if (owner !== uid) throw new functions.https.HttpsError("permission-denied", "Not your task.");
    if ((task.status ?? 'draft') === 'open') return; // idempotent

    const posting = (setSnap.exists ? (setSnap.data() as PlatformPosting).posting : undefined) ?? {};
    const minBal = Number.isFinite(posting.minBalanceCoins) ? Number(posting.minBalanceCoins) : 200;
    const pct    = Number.isFinite(posting.feePercent)      ? Number(posting.feePercent)      : 5;
    const minFee = Number.isFinite(posting.minFeeCoins)     ? Number(posting.minFeeCoins)     : 5;
    const maxFee = Number.isFinite(posting.maxFeeCoins)     ? Number(posting.maxFeeCoins)     : 500;

    const walletDoc = await tx.get(userRef);
    const wallet = walletDoc.data() || {};
    const coins = readCoins(wallet);
    if (coins < minBal) throw new functions.https.HttpsError("failed-precondition", "insufficient_funds");

    // idempotency: reuse prior txn if same key
    const prior = await db.collectionGroup("transactions")
      .where("idempotencyKey", "==", idempotencyKey)
      .where("type", "==", "posting_fee")
      .where("taskId", "==", taskId).limit(1).get();

    let fee = 0, txnId: string | null = null;
    if (prior.empty) {
      const budget = pickBudget(task);
      fee = Math.max(minFee, Math.min(maxFee, Math.ceil((budget * pct) / 100)));
      const newBal = coins - fee;
      if (newBal < 0) throw new functions.https.HttpsError("failed-precondition", "insufficient_funds");

      const patch: Record<string, unknown> = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
      writeCoins(patch, newBal);
      tx.set(userRef, patch, { merge: true });

      const txnRef = userRef.collection("transactions").doc();
      txnId = txnRef.id;
      tx.set(txnRef, {
        type: "posting_fee",
        amountCoins: fee,
        taskId,
        idempotencyKey,
        status: "succeeded",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      txnId = prior.docs[0].id;
      fee = Number(prior.docs[0].data()?.amountCoins ?? 0);
    }

    tx.set(taskRef, {
      status: "open",
      postingFeeCoins: fee,
      postingFeeTxnId: txnId,
      postedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });

  return { ok: true };
});
