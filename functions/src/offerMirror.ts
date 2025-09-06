// functions/src/offerMirror.ts
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
try { admin.app(); } catch { admin.initializeApp(); }
const db = admin.firestore();

export const onOfferCreate = functions.firestore
  .document("tasks/{taskId}/offers/{offerId}")
  .onCreate(async (snap, ctx) => {
    const offer = snap.data() || {};
    const { taskId, offerId } = ctx.params as { taskId: string, offerId: string };
    const task = (await db.doc(`tasks/${taskId}`).get()).data() || {};
    await db.doc(`offers/${offerId}`).set({
      ...offer,
      taskId,
      posterId: task.posterId ?? offer.posterId ?? null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });

export const onOfferUpdate = functions.firestore
  .document("tasks/{taskId}/offers/{offerId}")
  .onUpdate(async (chg, ctx) => {
    const after = chg.after.data() || {};
    const { taskId, offerId } = ctx.params as { taskId: string, offerId: string };
    await db.doc(`offers/${offerId}`).set({
      ...after,
      taskId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });

export const onOfferDelete = functions.firestore
  .document("tasks/{taskId}/offers/{offerId}")
  .onDelete(async (_snap, ctx) => {
    await db.doc(`offers/${ctx.params.offerId as string}`).delete();
  });
