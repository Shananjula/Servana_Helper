import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

try { admin.app(); } catch { admin.initializeApp(); }
const db = admin.firestore();

export const onCategoryProofWrite = functions.firestore
  .document('category_proofs/{proofId}')
  .onWrite(async (change, context) => {
    const after = change.after.exists ? change.after.data() as any : null;
    if (!after) return;

    const uid: string | undefined = (after.uid || after.userId) as string | undefined;
    const proofId = context.params.proofId as string;
    const suffix = proofId.includes('_') ? proofId.substring(proofId.indexOf('_') + 1) : proofId;
    const categoryId: string = (after.categoryId as string | undefined) || suffix;

    if (!uid) return;

    const status = String(after.status || '').toLowerCase();
    const isVerified = status === 'verified' || status === 'approved';
    const isRejected = status === 'rejected';

    const userRef = db.collection('users').doc(uid);
    const arrayUnion = admin.firestore.FieldValue.arrayUnion;
    const arrayRemove = admin.firestore.FieldValue.arrayRemove;

    if (categoryId === 'basic') {
      const updates: admin.firestore.UpdateData = {};
      if (isVerified) {
        updates['flags.basicVerified'] = true;
        const phys = await db.collection('category_proofs').where('uid', '==', uid).get();
        const grant: string[] = [];
        for (const d of phys.docs) {
          const cid = (d.get('categoryId') as string | undefined) || d.id.split('_').slice(1).join('_');
          if (!cid || cid === 'basic') continue;
          const st = String(d.get('status') || '').toLowerCase();
          if (st !== 'verified' && st !== 'approved') continue;
          const cdoc = await db.collection('categories').doc(cid).get();
          if (cdoc.exists && cdoc.get('mode') === 'physical') grant.push(cid);
        }
        if (grant.length) updates['allowedCategoryIds'] = arrayUnion(...grant);
      } else if (isRejected) {
        updates['flags.basicVerified'] = false;
      }
      if (Object.keys(updates).length) await userRef.set(updates, { merge: true });
      return;
    }

    let mode: 'online'|'physical' = 'online';
    try {
      const cdoc = await db.collection('categories').doc(categoryId).get();
      const m = String(cdoc.get('mode') || '').toLowerCase();
      if (m === 'online' || m === 'physical') mode = m as any;
    } catch {}

    const updates: admin.firestore.UpdateData = {};
    if (isVerified) {
      if (mode === 'online') {
        updates['allowedCategoryIds'] = arrayUnion(categoryId);
      } else {
        const usr = await userRef.get();
        const basicVerified = !!usr.get('flags.basicVerified');
        if (basicVerified) updates['allowedCategoryIds'] = arrayUnion(categoryId);
      }
    } else if (isRejected) {
      updates['allowedCategoryIds'] = arrayRemove(categoryId);
    }

    if (Object.keys(updates).length) {
      await userRef.set(updates, { merge: true });
    }
  });
