 
// functions/src/counterOffers.ts
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

function assertAuth(ctx: functions.https.CallableContext) {
  if (!ctx.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }
  return ctx.auth.uid;
}

async function getOffer(offerId: string) {
  // Try top-level first
  const top = await db.doc(`offers/${offerId}`).get();
  if (top.exists) {
    const o = top.data() || {};
    const t = String(o.taskId || "");
    const path = `tasks/${t}/offers/${offerId}`;
    const sub = await db.doc(path).get();
    return { path, snap: sub.exists ? sub : top, isTop: !sub.exists };
  }
  // Otherwise search by subcollection path: need taskId in payloads
  throw new functions.https.HttpsError("invalid-argument", "Use top-level /offers or pass taskId to target offer.");
}

export const proposeCounter = functions.https.onCall(async (data, ctx) => {
  const uid = assertAuth(ctx);
  const offerId = String(data?.offerId || "");
  const counterPrice = Number(data?.price ?? NaN);
  const note = String(data?.note ?? "");

  if (!offerId || !Number.isFinite(counterPrice) || counterPrice <= 0) {
    throw new functions.https.HttpsError("invalid-argument", "offerId and positive price required");
  }

  return await db.runTransaction(async (tx) => {
    const { path, snap } = await getOffer(offerId);
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Offer not found");
    const o = snap.data() || {};
    const taskId = String(o.taskId || "");
    const helperId = String(o.helperId || "");

    // Poster ownership
    const task = await tx.get(db.doc(`tasks/${taskId}`));
    if (!task.exists) throw new functions.https.HttpsError("not-found", "Task not found");
    const posterId = String(task.get("posterId") || "");
    if (posterId !== uid) throw new functions.https.HttpsError("permission-denied", "Not your task");

    tx.update(db.doc(path), {
      status: "counter",
      counterPrice,
      counterNote: note,
      counterBy: uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ok: true, offerId, taskId, helperId, posterId, counterPrice };
  });
});

export const rejectOffer = functions.https.onCall(async (data, ctx) => {
  const uid = assertAuth(ctx);
  const offerId = String(data?.offerId || "");
  const reason = String(data?.reason ?? "");

  if (!offerId) throw new functions.https.HttpsError("invalid-argument", "offerId required");

  return await db.runTransaction(async (tx) => {
    const { path, snap } = await getOffer(offerId);
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Offer not found");
    const o = snap.data() || {};
    const taskId = String(o.taskId || "");

    const task = await tx.get(db.doc(`tasks/${taskId}`));
    if (!task.exists) throw new functions.https.HttpsError("not-found", "Task not found");
    const posterId = String(task.get("posterId") || "");
    if (posterId !== uid) throw new functions.https.HttpsError("permission-denied", "Not your task");

    tx.update(db.doc(path), {
      status: "rejected",
      rejectReason: reason,
      rejectedBy: uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { ok: true, offerId, taskId };
  });
});

export const withdrawOffer = functions.https.onCall(async (data, ctx) => {
  const uid = assertAuth(ctx);
  const offerId = String(data?.offerId || "");
  if (!offerId) throw new functions.https.HttpsError("invalid-argument", "offerId required");

  return await db.runTransaction(async (tx) => {
    const { path, snap } = await getOffer(offerId);
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Offer not found");
    const o = snap.data() || {};
    const helperId = String(o.helperId || "");
    if (helperId !== uid) throw new functions.https.HttpsError("permission-denied", "Not your offer");

    tx.update(db.doc(path), {
      status: "withdrawn",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { ok: true, offerId };
  });
});

export const agreeToCounter = functions.https.onCall(async (data, ctx) => {
  const uid = assertAuth(ctx);
  const offerId = String(data?.offerId || "");
  if (!offerId) throw new functions.https.HttpsError("invalid-argument", "offerId required");

  return await db.runTransaction(async (tx) => {
    const { path, snap } = await getOffer(offerId);
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Offer not found");
    const o = snap.data() || {};
    const helperId = String(o.helperId || "");
    if (helperId !== uid) throw new functions.https.HttpsError("permission-denied", "Not your offer");

    tx.update(db.doc(path), {
      helperAgreed: true,
      agreedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { ok: true, offerId };
  });
});



export const helperCounter = functions.https.onCall(async (data, ctx) => {
  const uid = assertAuth(ctx);
  const offerId = String(data?.offerId || "");
  const price = Number(data?.price ?? NaN);
  if (!offerId || !Number.isFinite(price) || price <= 0) {
    throw new functions.https.HttpsError("invalid-argument", "offerId and positive price required");
  }

  return await db.runTransaction(async (tx) => {
    const { path, snap } = await getOffer(offerId);
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Offer not found");
    const o = snap.data() || {};
    const helperId = String(o.helperId || "");
    if (helperId !== uid) throw new functions.https.HttpsError("permission-denied", "Not your offer");

    tx.update(db.doc(path), {
      status: "negotiating",
      helperCounterPrice: price,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { ok: true, offerId, helperId, helperCounterPrice: price };
  });
});

