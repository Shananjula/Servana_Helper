
// functions/src/offerChatBridge.ts
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

function chatIdFor(posterId: string, helperId: string, taskId: string) {
  // Deterministic, URL-safe id
  return `task_${taskId}__poster_${posterId}__helper_${helperId}`;
}

async function ensureChat(posterId: string, helperId: string, taskId: string) {
  const cid = chatIdFor(posterId, helperId, taskId);
  const cref = db.doc(`chats/${cid}`);
  const snap = await cref.get();
  if (!snap.exists) {
    await cref.set({
      chatId: cid,
      taskId,
      posterId,
      helperId,
      members: [posterId, helperId],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  } else {
    await cref.set({
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }
  return cid;
}

async function postMsg(cid: string, type: string, payload: Record<string, any>) {
  const mref = db.collection(`chats/${cid}/messages`).doc();
  await mref.set({
    type,
    ...payload,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

function pickOfferSnapshot(d: FirebaseFirestore.DocumentData) {
  const o = d || {};
  return {
    offerId: String(o.offerId || ""),
    taskId: String(o.taskId || ""),
    helperId: String(o.helperId || ""),
    posterId: String(o.posterId || ""),
    amount: o.amount ?? o.price ?? null,
    counterPrice: o.counterPrice ?? null,
    helperCounterPrice: o.helperCounterPrice ?? null,
    note: String(o.message ?? o.note ?? ""),
    status: String(o.status ?? ""),
    origin: String(o.origin ?? "public"),
    helperAgreed: Boolean(o.helperAgreed === true),
  };
}

// On offer CREATE: ensure chat and drop offer.created message
export const onOfferCreateToChat = functions.firestore
  .document("tasks/{tid}/offers/{oid}")
  .onCreate(async (snap, ctx) => {
    const d = snap.data() || {};
    // Backfill ids
    const tid = ctx.params.tid as string;
    const oid = ctx.params.oid as string;
    if (!d.taskId) d.taskId = tid;
    d.offerId = oid;

    // Resolve posterId (old offers may miss it)
    let posterId = String(d.posterId || "");
    if (!posterId) {
      const task = await db.doc(`tasks/${tid}`).get();
      posterId = String(task.get("posterId") || "");
      d.posterId = posterId;
    }
    const helperId = String(d.helperId || "");
    if (!posterId || !helperId) return;

    const cid = await ensureChat(posterId, helperId, tid);
    const snapPayload = pickOfferSnapshot(d);
    await postMsg(cid, "offer.created", {
      actorId: helperId,
      ...snapPayload,
    });
  });

// On offer UPDATE: mirror key transitions into chat
export const onOfferUpdateToChat = functions.firestore
  .document("tasks/{tid}/offers/{oid}")
  .onUpdate(async (change, ctx) => {
    const before = change.before.data() || {};
    const after  = change.after.data()  || {};
    const tid = ctx.params.tid as string;
    const oid = ctx.params.oid as string;

    // Ensure linkage
    const helperId = String(after.helperId || before.helperId || "");
    let posterId   = String(after.posterId || before.posterId || "");
    if (!posterId) {
      const task = await db.doc(`tasks/${tid}`).get();
      posterId = String(task.get("posterId") || "");
    }
    if (!posterId || !helperId) return;

    const cid = await ensureChat(posterId, helperId, tid);
    const snapPayload = pickOfferSnapshot({ ...after, offerId: oid, taskId: tid, posterId });

    // Detect transitions
    const becameCounter   = (before.status !== "counter")   && (after.status === "counter");
    const becameRejected  = (before.status !== "rejected")  && (after.status === "rejected");
    const becameWithdrawn = (before.status !== "withdrawn") && (after.status === "withdrawn");
    const helperAgreedNow = (!before.helperAgreed) && (after.helperAgreed === true);
    const helperCountered = (after.helperCounterPrice != null) &&
                            (before.helperCounterPrice !== after.helperCounterPrice);
    const becameAccepted  = (before.status !== "accepted") && (after.status === "accepted");

    const posts: Promise<any>[] = [];

    if (becameCounter) {
      posts.push(postMsg(cid, "offer.counter.poster", { actorId: posterId, ...snapPayload }));
    }
    if (becameRejected) {
      posts.push(postMsg(cid, "offer.rejected", { actorId: posterId, ...snapPayload }));
    }
    if (helperAgreedNow) {
      posts.push(postMsg(cid, "offer.agreed", { actorId: helperId, ...snapPayload }));
    }
    if (helperCountered) {
      posts.push(postMsg(cid, "offer.counter.helper", { actorId: helperId, ...snapPayload }));
    }
    if (becameWithdrawn) {
      posts.push(postMsg(cid, "offer.withdrawn", { actorId: helperId, ...snapPayload }));
    }
    if (becameAccepted) {
      posts.push(postMsg(cid, "offer.accepted", { actorId: posterId, ...snapPayload }));
    }

    if (posts.length) await Promise.all(posts);
    return;
  });
