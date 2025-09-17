// functions/src/maintenance/backfillOffersPosterId.ts
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

function ensureAuth(context: functions.https.CallableContext) {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }
}

async function ensureAuthorized(uid: string) {
  // Allow when settings/platform.debugMode == true OR uid is listed in debugUids OR custom token.admin flag.
  const plat = await db.doc("settings/platform").get();
  const data = plat.exists ? plat.data() || {} : {};
  const debug = data.debugMode === true;
  const allowedList =
    Array.isArray(data.debugUids) && (data.debugUids as string[]).includes(uid);
  // You can also set a custom claim 'admin' on your own user.
  // In callable context we can't read the token here (we're not passed it), but debug/allow-list is enough for safety.
  if (!debug && !allowedList) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Backfill is restricted. Enable settings/platform.debugMode or add your uid to debugUids."
    );
  }
}

/** Call with { taskId: "..." } — backfills posterId into tasks/{taskId}/offers/* that miss it. */
export const backfillOffersPosterId = functions
  .runWith({ timeoutSeconds: 540, memory: "512MB" })
  .https.onCall(async (data, context) => {
    ensureAuth(context);
    await ensureAuthorized(context.auth!.uid);

    const taskId = String(data?.taskId || "");
    if (!taskId) {
      throw new functions.https.HttpsError("invalid-argument", "taskId required");
    }

    const taskRef = db.doc(`tasks/${taskId}`);
    const taskSnap = await taskRef.get();
    if (!taskSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Task not found");
    }

    const posterId =
      String(
        taskSnap.get("posterId") ??
          taskSnap.get("poster_id") ??
          taskSnap.get("ownerId") ??
          taskSnap.get("userId") ??
          taskSnap.get("uid") ??
          ""
      ) || "";

    if (!posterId) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Task has no posterId (posterId/poster_id/ownerId/userId/uid empty)."
      );
    }

    const offersSnap = await taskRef.collection("offers").get();

    let scanned = 0;
    let patched = 0;
    let batch = db.batch();
    let inBatch = 0;

    for (const doc of offersSnap.docs) {
      scanned++;
      const d = doc.data();
      const needs =
        !("posterId" in d) || d.posterId === null || d.posterId === "";

      if (needs) {
        batch.update(doc.ref, {
          posterId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        patched++;
        inBatch++;
        if (inBatch >= 400) {
          await batch.commit();
          batch = db.batch();
          inBatch = 0;
        }
      }
    }

    if (inBatch > 0) await batch.commit();

    return { ok: true, taskId, scanned, patched };
  });
