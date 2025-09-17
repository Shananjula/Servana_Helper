// functions/src/maintenance/backfillAllOffersPosterId.ts
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

function ensureAuth(context: functions.https.CallableContext) {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }
}

async function ensureAuthorized(uid: string) {
  const plat = await db.doc("settings/platform").get();
  const data = plat.exists ? (plat.data() || {}) : {};
  const debug = data.debugMode === true;
  const allowedList =
    Array.isArray(data.debugUids) && (data.debugUids as string[]).includes(uid);
  if (!debug && !allowedList) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Backfill is restricted. Enable settings/platform.debugMode or add your uid to debugUids."
    );
  }
}

/**
 * Scans tasks in documentId order, patches offers missing posterId.
 * Params:
 *  - startAfterTaskId?: string  // resume token
 *  - limitTasks?: number        // default 200
 *  - limitOffersPerTask?: number// default 1000 (safety bound; we scan then filter missing)
 *  - dryRun?: boolean           // default true (no writes)
 *  - onlyMissing?: boolean      // default true (if false, also realign wrong posterIds)
 */
export const backfillAllOffersPosterId = functions
  .runWith({ timeoutSeconds: 540, memory: "1GB" })
  .https.onCall(async (data, context) => {
    ensureAuth(context);
    await ensureAuthorized(context.auth!.uid);

    const startAfterTaskId = data?.startAfterTaskId ? String(data.startAfterTaskId) : null;
    const limitTasks = Math.min(Math.max(Number(data?.limitTasks ?? 200), 1), 1000);
    const limitOffersPerTask = Math.min(Math.max(Number(data?.limitOffersPerTask ?? 1000), 1), 5000);
    const dryRun = Boolean(data?.dryRun ?? true);
    const onlyMissing = Boolean(data?.onlyMissing ?? true);

    // Build task query
    let q: FirebaseFirestore.Query = db
      .collection("tasks")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(limitTasks);

    if (startAfterTaskId) {
      const startDoc = await db.doc(`tasks/${startAfterTaskId}`).get();
      if (startDoc.exists) q = q.startAfter(startDoc.id);
    }

    const tasksSnap = await q.get();

    let tasksScanned = 0;
    let offersScanned = 0;
    let patched = 0;
    let skippedNoPoster = 0;

    for (const taskDoc of tasksSnap.docs) {
      tasksScanned++;

      const posterId =
        String(
          taskDoc.get("posterId") ??
            taskDoc.get("poster_id") ??
            taskDoc.get("ownerId") ??
            taskDoc.get("userId") ??
            taskDoc.get("uid") ??
            ""
        ) || "";

      if (!posterId) {
        skippedNoPoster++;
        continue;
      }

      // Fetch offers subcollection (limit to avoid unbounded loads)
      const offersSnap = await taskDoc.ref.collection("offers").limit(limitOffersPerTask).get();

      let batch = db.batch();
      let inBatch = 0;

      for (const off of offersSnap.docs) {
        offersScanned++;
        const d = off.data() as any;
        const missing = !("posterId" in d) || d.posterId === null || d.posterId === "";
        const wrong = !missing && !onlyMissing && d.posterId !== posterId;

        if (missing || wrong) {
          if (!dryRun) {
            batch.update(off.ref, {
              posterId,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          patched++;
          inBatch++;
          if (inBatch >= 400) {
            if (!dryRun) await batch.commit();
            batch = db.batch();
            inBatch = 0;
          }
        }
      }

      if (inBatch > 0 && !dryRun) await batch.commit();
    }

    const nextStartAfterTaskId =
      tasksSnap.docs.length === limitTasks
        ? tasksSnap.docs[tasksSnap.docs.length - 1].id
        : null;

    return {
      ok: true,
      dryRun,
      onlyMissing,
      limitTasks,
      limitOffersPerTask,
      tasksScanned,
      offersScanned,
      patched,
      skippedNoPoster,
      nextStartAfterTaskId, // use this to resume
    };
  });
