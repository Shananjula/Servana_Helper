// functions/src/approveOffer.ts
// Atomic approval with commission deduction in COINS + FCM.
// Sends topic messages to helper/poster: user_{uid}

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();
const db = admin.firestore();

const ECONOMY = {
  platformFeePct: 10,
  minApplyCoins: 400,
  graceMinutesForTopUp: 15,
};

export const approveOffer = functions.https.onCall(async (data, context) => {
  const taskId: string = data.taskId;
  const offerId: string = data.offerId;
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  if (!taskId || !offerId) {
    throw new functions.https.HttpsError('invalid-argument', 'taskId and offerId required');
  }

  const taskRef = db.collection('tasks').doc(taskId);
  const offerRef = db.collection('offers').doc(offerId);
  const txRef = db.collection('transactions').doc();
  let outcome: 'accepted'|'awaiting_topup' = 'accepted';
  let helperId = ''; let posterId = '';
  let price = 0; let commission = 0;

  await db.runTransaction(async (trx) => {
    const taskSnap = await trx.get(taskRef);
    const offerSnap = await trx.get(offerRef);
    if (!taskSnap.exists || !offerSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Task or Offer missing');
    }
    const task = taskSnap.data() || {};
    const offer = offerSnap.data() || {};

    helperId = String(offer.helperId || '');
    posterId = String(offer.posterId || '');
    price = Number(offer.price ?? offer.amount ?? 0);
    commission = Math.ceil((price * ECONOMY.platformFeePct) / 100);

    // Read helper balance
    const userRef = db.collection('users').doc(helperId);
    const userSnap = await trx.get(userRef);
    const u = userSnap.data() || {};
    const bal: number = Number(u.walletBalance || 0);

    if (bal >= commission) {
      // Deduct now
      trx.set(txRef, {
        userId: helperId,
        type: 'commission',
        amount: commission,
        direction: 'debit',
        status: 'ok',
        taskId,
        offerId,
        note: `Commission ${ECONOMY.platformFeePct}% on LKR ${price}`,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      trx.set(userRef, { walletBalance: bal - commission, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

      // Assign task + accept
      trx.set(taskRef, { status: 'assigned', helperId, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
      trx.set(offerRef, { status: 'accepted', acceptedAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

      outcome = 'accepted';
    } else {
      // Not enough coins — mark awaiting_topup
      const deadline = admin.firestore.Timestamp.fromDate(new Date(Date.now() + ECONOMY.graceMinutesForTopUp * 60 * 1000));
      trx.set(offerRef, { status: 'awaiting_topup', topUpDeadline: deadline, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
      outcome = 'awaiting_topup';
    }
  });

  // FCM notifications
  try {
    const helperTopic = `user_${helperId}`;
    const posterTopic = `user_${posterId}`;

    if (outcome === 'accepted') {
      await admin.messaging().send({ topic: helperTopic, data: { type: 'offer', taskId, offerId, title: 'Offer approved', body: 'Commission deducted and task assigned.' }});
      await admin.messaging().send({ topic: posterTopic, data: { type: 'task', taskId, title: 'Helper assigned', body: 'Your task has been assigned successfully.' }});
    } else {
      await admin.messaging().send({ topic: helperTopic, data: { type: 'offer', taskId, offerId, title: 'Top up needed', body: 'Add coins to secure the approval.' }});
    }
  } catch (e) {
    console.error('FCM send failed', e);
  }

  

// --- LOCKSCREEN block: visible notifications for helper/poster ---
try {
  const helperTopic = `user_${helperId}`;
  const posterTopic = `user_${posterId}`;

  if (outcome === 'accepted') {
    const titleH = 'Offer approved';
    const bodyH  = 'Commission deducted and task assigned.';
    const titleP = 'Task assigned';
    const bodyP  = 'Your task has been assigned successfully.';

    await admin.messaging().send({
      topic: helperTopic,
      notification: { title: titleH, body: bodyH },
      data: { type: 'offer', taskId: taskId, body: bodyH },
      android: { priority: 'high', notification: { channelId: 'servana_general', visibility: 'PUBLIC', sound: 'default', clickAction: 'FLUTTER_NOTIFICATION_CLICK' } },
      apns: { headers: { 'apns-priority': '10', 'apns-push-type': 'alert' }, payload: { aps: { alert: { title: titleH, body: bodyH }, sound: 'default' } } }
    });

    await admin.messaging().send({
      topic: posterTopic,
      notification: { title: titleP, body: bodyP },
      data: { type: 'offer', taskId: taskId, body: bodyP },
      android: { priority: 'high', notification: { channelId: 'servana_general', visibility: 'PUBLIC', sound: 'default', clickAction: 'FLUTTER_NOTIFICATION_CLICK' } },
      apns: { headers: { 'apns-priority': '10', 'apns-push-type': 'alert' }, payload: { aps: { alert: { title: titleP, body: bodyP }, sound: 'default' } } }
    });
  } else {
    const title = 'Top up needed';
    const body = 'Add coins to secure the approval.';
    await admin.messaging().send({
      topic: helperTopic,
      notification: { title, body },
      data: { type: 'offer', taskId: taskId, body },
      android: { priority: 'high', notification: { channelId: 'servana_general', visibility: 'PUBLIC', sound: 'default', clickAction: 'FLUTTER_NOTIFICATION_CLICK' } },
      apns: { headers: { 'apns-priority': '10', 'apns-push-type': 'alert' }, payload: { aps: { alert: { title, body }, sound: 'default' } } }
    });
  }
} catch (e) {
  console.error('FCM send failed', e);
}

// --- END LOCKSCREEN block ---

return { ok: true, outcome, commission, price };
});
