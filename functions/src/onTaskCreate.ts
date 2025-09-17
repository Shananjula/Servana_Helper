// functions/src/onTaskCreate.ts
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { FEES } from './fees';


const db = admin.firestore();


export const onTaskCreate = functions.firestore
.document('tasks/{tid}')
.onCreate(async (snap, ctx) => {
const data = snap.data() || {};
const posterId: string = String(data.posterId || '');
if (!posterId) return; // nothing we can do


const tid = ctx.params.tid as string;
const ledgerRef = db.doc(`wallet_ledger/post:${tid}`);


await db.runTransaction(async (tx) => {
const ledgerSnap = await tx.get(ledgerRef);
if (ledgerSnap.exists) return; // already charged via publishTask


const settingsRef = db.doc('settings/platform');
const settingsSnap = await tx.get(settingsRef);
const configuredPostFee = Number((settingsSnap.data() || {}).posting?.postFeeCoins ?? FEES.POST_FEE);
const POST_FEE = Math.max(configuredPostFee, 0);
if (POST_FEE <= 0) return;


const posterRef = db.doc(`users/${posterId}`);
const posterSnap = await tx.get(posterRef);
const bal = Number(posterSnap.get('servCoinBalance') || 0);


if (bal < POST_FEE) {
// Insufficient balance → remove the task to keep invariants
tx.delete(snap.ref);
return;
}


tx.update(posterRef, { servCoinBalance: admin.firestore.FieldValue.increment(-POST_FEE) });
tx.set(ledgerRef, {
uid: posterId,
kind: 'post_fee',
amount: -POST_FEE,
taskId: tid,
uniqueKey: `post:${tid}`,
createdAt: admin.firestore.FieldValue.serverTimestamp(),
});
});
});