/* functions/src/offerMirror.ts
   Mirrors subcollection offers at tasks/{taskId}/offers/{offerId}
   into a top-level collection /offers/{offerId} that the Poster app reads.
*/

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

/** Backfill posterId from the task if absent in the offer payload. */
async function ensurePosterId(taskId: string, offerPosterId?: string | null) {
  if (offerPosterId) return offerPosterId;
  const taskSnap = await db.doc(`tasks/${taskId}`).get();
  const task = taskSnap.exists ? taskSnap.data() || {} : {};
  return (task as any).posterId ?? null;
}

/** CREATE → write /offers/{offerId} */
export const mirrorOfferCreate = functions.firestore
  .document("tasks/{taskId}/offers/{offerId}")
  .onCreate(async (snap, ctx) => {
    const { taskId, offerId } = ctx.params as { taskId: string; offerId: string };
    const offer = snap.data() || {};
    const posterId = await ensurePosterId(taskId, (offer as any).posterId);

    await db.doc(`offers/${offerId}`).set(
      {
        ...offer,
        taskId,
        posterId,
        // keep a marker so we know this doc is mirrored:
        _mirroredFrom: `tasks/${taskId}/offers/${offerId}`,
        // stabilize timestamps
        createdAt: (offer as any).createdAt ?? admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });

/** UPDATE → upsert /offers/{offerId} */
export const mirrorOfferUpdate = functions.firestore
  .document("tasks/{taskId}/offers/{offerId}")
  .onUpdate(async (change, ctx) => {
    const { taskId, offerId } = ctx.params as { taskId: string; offerId: string };
    const after = change.after.data() || {};
    const posterId = await ensurePosterId(taskId, (after as any).posterId);

    await db.doc(`offers/${offerId}`).set(
      {
        ...after,
        taskId,
        posterId,
        _mirroredFrom: `tasks/${taskId}/offers/${offerId}`,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });

/** DELETE → delete /offers/{offerId} */
export const mirrorOfferDelete = functions.firestore
  .document("tasks/{taskId}/offers/{offerId}")
  .onDelete(async (_snap, ctx) => {
    const { offerId } = ctx.params as { offerId: string };
    await db.doc(`offers/${offerId}`).delete();
  });
