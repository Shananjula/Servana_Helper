import * as functions from 'firebase-functions';
// If first contact, charge poster 50 once (idempotent on ledger key)
if (!alreadyConnected) {
const posterRef = db.doc(`users/${posterId}`);
const posterSnap = await tx.get(posterRef);
const bal = Number(posterSnap.get('servCoinBalance') || 0);
if (bal < FEES.DIRECT_DM_FEE) {
throw new functions.https.HttpsError('failed-precondition', 'POSTER_NEEDS_50');
}


const ledgerKey = `dmfee:${pair}`;
const ledgerRef = db.doc(`wallet_ledger/${ledgerKey}`);
const ledgerSnap = await tx.get(ledgerRef);
if (!ledgerSnap.exists) {
tx.update(posterRef, {
servCoinBalance: admin.firestore.FieldValue.increment(-FEES.DIRECT_DM_FEE),
lastTopupAt: posterSnap.get('lastTopupAt') || admin.firestore.FieldValue.serverTimestamp(),
});
tx.set(ledgerRef, {
uid: posterId,
kind: 'intro_fee',
amount: -FEES.DIRECT_DM_FEE,
helperId,
taskId,
uniqueKey: ledgerKey,
createdAt: admin.firestore.FieldValue.serverTimestamp(),
});
}


tx.set(contactRef, {
peerId: helperId,
everChatted: true,
introFeePaidByPoster: true,
firstContactAt: admin.firestore.FieldValue.serverTimestamp(),
lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
}, { merge: true });
} else {
tx.set(contactRef, { everChatted: true, lastMessageAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
}


// Create invite doc (UI can show it; acceptance will create/flip to auto-offer)
const inviteRef = db.collection('invites').doc();
tx.set(inviteRef, {
posterId,
helperId,
taskId,
categoryId,
origin: 'direct',
status: 'pending',
createdAt: admin.firestore.FieldValue.serverTimestamp(),
});
});


return { ok: true };
});