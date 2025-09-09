
// functions/src/offerToChat.ts
import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';

const db = admin.firestore();

function chatIdFor(taskId: string, posterId: string, helperId: string): string {
  const a = posterId.replace(/[^a-zA-Z0-9_-]/g, '');
  const b = helperId.replace(/[^a-zA-Z0-9_-]/g, '');
  const sorted = a.localeCompare(b) <= 0 ? `${a}_${b}` : `${b}_${a}`;
  return `${taskId.replace(/[^a-zA-Z0-9_-]/g, '')}_${sorted}`;
}

export const onOfferCreate = functions.firestore
  .document('tasks/{taskId}/offers/{offerId}')
  .onCreate(async (snap, ctx) => {
    const o = snap.data() as any;
    const taskId = ctx.params.taskId;
    if (!o || !o.posterId || !o.helperId) return;
    const chatId = chatIdFor(taskId, o.posterId, o.helperId);
    const chatRef = db.collection('chats').doc(chatId);
    await db.runTransaction(async (tx) => {
      const c = await tx.get(chatRef);
      if (!c.exists) {
        tx.set(chatRef, {
          taskId, posterId: o.posterId, helperId: o.helperId,
          members: [o.posterId, o.helperId],
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          lastMsgAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      const msgRef = chatRef.collection('messages').doc();
      tx.set(msgRef, {
        type: 'offer',
        offerId: snap.id,
        price: o.price ?? o.amount,
        note: o.message ?? '',
        authorId: o.helperId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.update(chatRef, {
        lastMsg: 'New offer',
        lastMsgAt: admin.firestore.FieldValue.serverTimestamp(),
        lastOfferId: snap.id,
      });
      tx.update(snap.ref, { chatId });
    });
  });

export const onOfferUpdate = functions.firestore
  .document('tasks/{taskId}/offers/{offerId}')
  .onUpdate(async (change, ctx) => {
    const before = change.before.data() as any;
    const after = change.after.data() as any;
    const taskId = ctx.params.taskId;
    if (!after || !after.posterId || !after.helperId) return;
    const chatId = chatIdFor(taskId, after.posterId, after.helperId);
    const chatRef = db.collection('chats').doc(chatId);
    const msgRef = chatRef.collection('messages').doc();
    let type = 'system';
    if (before.status !== after.status) {
      if (after.status === 'counter') type = 'counter';
      else if (after.status === 'accepted') type = 'accept';
      else if (after.status === 'withdrawn') type = 'system';
    }
    await db.runTransaction(async (tx) => {
      tx.set(msgRef, {
        type,
        offerId: change.after.id,
        price: after.counterPrice ?? after.price ?? after.amount,
        note: after.message ?? '',
        authorId: (type === 'counter') ? after.posterId : after.helperId, // simplistic
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.update(chatRef, {
        lastMsg: type === 'accept' ? 'Offer accepted' : type === 'counter' ? 'Countered' : 'Offer updated',
        lastMsgAt: admin.firestore.FieldValue.serverTimestamp(),
        lastOfferId: change.after.id,
      });
    });
  });
