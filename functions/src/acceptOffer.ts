// functions/src/acceptOffer.ts
// Canonical acceptance path for Servana.
// - Prefers: tasks/{taskId}/offers/{offerId}
// - Falls back to legacy: /offers/{offerId}
// - Mirrors phones onto the task with tolerant reads: phone ?? phoneNumber
// - Leaves wallet/commission logic to your existing approveOffer if you keep using it.

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

try { admin.app(); } catch { admin.initializeApp(); }
const db = admin.firestore();

export const acceptOffer = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Sign in required.');
  }

  const { taskId, offerId, offerMessageId } = (data || {}) as {
    taskId?: string;
    offerId?: string;
    offerMessageId?: string;
  };

  if (!taskId || (!offerId && !offerMessageId)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Provide taskId and offerId (or offerMessageId).'
    );
  }

  // --- Locate the offer (subcollection first, then legacy fallback) ---
  let offerRef: FirebaseFirestore.DocumentReference;
  let offerSnap: FirebaseFirestore.DocumentSnapshot;

  if (offerId) {
    const subRef = db.collection('tasks').doc(taskId).collection('offers').doc(offerId);
    const subSnap = await subRef.get();
    if (subSnap.exists) {
      offerRef = subRef; offerSnap = subSnap;
    } else {
      const legacyRef = db.collection('offers').doc(offerId);
      const legacySnap = await legacyRef.get();
      if (!legacySnap.exists) {
        throw new functions.https.HttpsError('not-found', `Offer ${offerId} not found (subcollection or legacy).`);
      }
      offerRef = legacyRef; offerSnap = legacySnap;
    }
  } else {
    // Optional mapping via messageId if your offers store it
    const q = await db.collectionGroup('offers')
      .where('messageId', '==', offerMessageId)
      .where('taskId', '==', taskId)
      .limit(1).get();
    if (q.empty) {
      throw new functions.https.HttpsError('not-found', `No offer found for messageId=${offerMessageId}`);
    }
    offerSnap = q.docs[0];
    offerRef = offerSnap.ref;
  }

  const offer = (offerSnap.data() || {}) as any;
  const helperId: string | undefined = offer.createdBy || offer.helperId;
  if (!helperId) {
    throw new functions.https.HttpsError('failed-precondition', 'Offer missing helper (createdBy/helperId).');
  }

  // Load task + poster
  const taskRef = db.collection('tasks').doc(taskId);
  const taskSnap = await taskRef.get();
  if (!taskSnap.exists) {
    throw new functions.https.HttpsError('not-found', `Task ${taskId} not found.`);
  }
  const task = taskSnap.data() || {};
  const posterId: string | undefined = task.posterId || task.createdBy || task.userId;
  if (!posterId) {
    throw new functions.https.HttpsError('failed-precondition', 'Task missing posterId.');
  }

  // Tolerant phone reads
  const getPhone = async (uid: string): Promise<string | null> => {
    const u = await db.collection('users').doc(uid).get();
    const d = (u.data() || {}) as any;
    return (d.phone as string) || (d.phoneNumber as string) || null;
  };
  const [posterPhone, helperPhone] = await Promise.all([getPhone(posterId), getPhone(helperId)]);

  // Assign the task (single source of truth)
  await taskRef.set({
    acceptedOfferId: offerRef.id,
    assignedHelperId: helperId,
    status: 'in_progress',
    assignedAt: admin.firestore.FieldValue.serverTimestamp(),
    posterPhoneNumber: posterPhone ?? null,
    assignedHelperPhoneNumber: helperPhone ?? null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  // Mark offer accepted (best effort)
  await offerRef.set({
    status: 'accepted',
    acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  // TODO: notifications / analytics if needed

  return { ok: true, taskId, offerId: offerRef.id, helperId };
});
