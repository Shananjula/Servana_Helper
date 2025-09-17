// functions/src/recomputeAllowedForUser.ts (v3)
//
// Fixes legacy data + case-insensitive status matching.
// Also stores canonical slugs alongside raw ids to avoid mismatch with task fields.
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
try { admin.app(); } catch (e) { admin.initializeApp(); }
const db = admin.firestore();

function canon(s: string): string {
  return s.toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

export const recomputeAllowedForUser = functions.https.onCall(async (data, context) => {
  const uid = (typeof data?.uid === 'string' && data.uid.trim().length > 0)
    ? data.uid
    : context.auth?.uid;
  if (!uid) throw new functions.https.HttpsError('unauthenticated', 'No uid provided and not signed in.');

  // Read ALL docs (no where on status), then filter in code to be case-insensitive.
  const eligSnap = await db.collection(`users/${uid}/categoryEligibility`).get();

  const ids = new Set<string>();
  for (const d of eligSnap.docs) {
    const data = d.data() || {};
    const status = (String(data.status || '')).toLowerCase().trim();
    if (status !== 'approved') continue;

    const rawId = String(d.id);
    ids.add(rawId);
    ids.add(rawId.toLowerCase());
    ids.add(canon(rawId));

    // Optional extra fields we often see:
    const fId = data.categoryId || data.id;
    const fSlug = data.slug;
    const fLabel = data.label || data.name || data.title;

    if (typeof fId === 'string') { ids.add(fId); ids.add(fId.toLowerCase()); ids.add(canon(fId)); }
    if (typeof fSlug === 'string') { ids.add(fSlug); ids.add(fSlug.toLowerCase()); ids.add(canon(fSlug)); }
    if (typeof fLabel === 'string') { ids.add(fLabel); ids.add(fLabel.toLowerCase()); ids.add(canon(fLabel)); }
  }

  await db.doc(`users/${uid}`).set({
    allowedCategoryIds: Array.from(ids).sort(),
    allowedUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return { ok: true, count: ids.size };
});

export const onCategoryEligibilityWrite = functions.firestore
  .document('users/{uid}/categoryEligibility/{catId}')
  .onWrite(async (_change, context) => {
    const { uid } = context.params as { uid: string };
    // Reuse the same recompute logic
    await recomputeAllowedForUser.run({
      auth: { uid },
      data: { uid }
    } as any);
  });