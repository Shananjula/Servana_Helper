import * as admin from "firebase-admin";

const db = admin.firestore();
const fcm = admin.messaging();

export async function getUserTokens(uid: string): Promise<string[]> {
  const snap = await db.doc(`users/${uid}`).get();
  const data = snap.exists ? (snap.data() || {}) : {};
  const arr = Array.isArray(data.fcmTokens) ? (data.fcmTokens as string[]) : [];
  const mapKeys = data.fcmTokens && typeof data.fcmTokens === "object"
    ? Object.keys(data.fcmTokens) : [];
  return Array.from(new Set<string>([...arr, ...mapKeys].filter(Boolean)));
}

export async function sendPushTo(
  uids: string[],
  title: string,
  body: string,
  data: Record<string, string> = {}
) {
  const tokens = new Set<string>();
  for (const uid of uids) (await getUserTokens(uid)).forEach(t => tokens.add(t));
  if (tokens.size === 0) return { sent: 0 };

  const res = await fcm.sendEachForMulticast({
    notification: { title, body },
    data,
    tokens: Array.from(tokens),
  });

  // Optional pruning of dead tokens (best-effort)
  const dead: string[] = [];
  res.responses.forEach((r, i) => {
    if (!r.success && r.error && String(r.error.code || "").includes("registration-token-not-registered")) {
      dead.push(Array.from(tokens)[i]);
    }
  });
  if (dead.length) {
    const batch = db.batch();
    for (const uid of new Set(uids)) {
      const ref = db.doc(`users/${uid}`);
      const snap = await ref.get();
      const val = snap.exists ? (snap.data() || {}) : {};
      const map = val.fcmTokens && typeof val.fcmTokens === "object" ? { ...val.fcmTokens } : {};
      dead.forEach(t => { if (map[t]) delete map[t]; });
      batch.set(ref, { fcmTokens: map }, { merge: true });
    }
    await batch.commit();
  }
  return { sent: tokens.size };
}
