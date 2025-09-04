
import * as functions from "firebase-functions/v2";
import * as admin from "firebase-admin";

// Recompute allowedCategoryIds on any write to category_proofs or basic_docs.
export const onCategoryProofWrite = functions.firestore.onDocumentWritten(
  {
    document: "category_proofs/{docId}",
    region: "asia-south1",
  },
  async (event) => {
    const after = event.data?.after;
    if (!after) return;
    const data = after.data() as any;
    const uid = data.userId as string;
    if (!uid) return;
    await recomputeAllowed(uid);
  }
);

export const onBasicDocsWrite = functions.firestore.onDocumentWritten(
  {
    document: "basic_docs/{uid}",
    region: "asia-south1",
  },
  async (event) => {
    const uid = event.params.uid;
    await recomputeAllowed(uid);
  }
);

async function recomputeAllowed(uid: string) {
  const fs = admin.firestore();
  const proofsSnap = await fs.collection("category_proofs").where("userId", "==", uid).get();
  const basicDoc = await fs.collection("basic_docs").doc(uid).get();
  const basicApproved = basicDoc.exists && (basicDoc.data()?.status === "approved");

  const allowed = new Set<string>();
  for (const doc of proofsSnap.docs) {
    const p = doc.data();
    if (p.status !== "approved") continue;
    const catId = p.categoryId as string;
    const mode = p.mode as string;
    if (mode === "physical" && !basicApproved) {
      // Physical categories require basic docs approved
      continue;
    }
    allowed.add(catId);
  }

  await fs.collection("users").doc(uid).set({
    allowedCategoryIds: Array.from(allowed),
    allowedUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}
