import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { sendPushTo } from "./notify";

const db = admin.firestore();

export const onOfferSignals = functions.firestore
  .document("tasks/{tid}/offers/{oid}")
  .onUpdate(async (change, ctx) => {
    const before = change.before.data() || {};
    const after  = change.after.data()  || {};
    const tid = ctx.params.tid as string;
    const oid = ctx.params.oid as string;

    // Resolve poster/helper ids, even if older docs miss posterId
    const task = await db.doc(`tasks/${tid}`).get();
    const taskPoster = String(task.get("posterId") || "");
    const posterId = String(after.posterId || before.posterId || taskPoster || "");
    const helperId = String(after.helperId || before.helperId || "");

    if (!posterId || !helperId) return null;

    const taskTitle = (after.title || after.taskTitle || `Task ${tid}`).toString();

    // Detections
    const becameCounter   = (before.status !== "counter")   && (after.status === "counter");
    const becameRejected  = (before.status !== "rejected")  && (after.status === "rejected");
    const becameWithdrawn = (before.status !== "withdrawn") && (after.status === "withdrawn");
    const helperAgreedNow = (!before.helperAgreed) && (after.helperAgreed === true);
    const helperCountered = (after.helperCounterPrice != null) &&
                            (before.helperCounterPrice !== after.helperCounterPrice);

    const data = { offerId: oid, taskId: tid, route: "offer_details" };
    const pushes: Promise<any>[] = [];

    // Notify helper about poster actions
    if (becameCounter) {
      const price = after.counterPrice ?? after.amount ?? after.price;
      pushes.push(sendPushTo([helperId], "Counter offer", `Poster countered on “${taskTitle}” at ${price}`, data));
    }
    if (becameRejected) {
      pushes.push(sendPushTo([helperId], "Offer rejected", `Your offer was rejected on “${taskTitle}”.`, data));
    }

    // Notify poster about helper actions
    if (helperAgreedNow) {
      pushes.push(sendPushTo([posterId], "Helper accepted your counter",
        `They agreed to your price on “${taskTitle}”. Tap to accept.`, data));
    }
    if (helperCountered) {
      pushes.push(sendPushTo([posterId], "New counter from helper",
        `Helper countered on “${taskTitle}” at ${after.helperCounterPrice}.`, data));
    }
    if (becameWithdrawn) {
      pushes.push(sendPushTo([posterId], "Offer withdrawn",
        `Helper withdrew their offer on “${taskTitle}”.`, data));
    }

    if (pushes.length) await Promise.all(pushes);
    return null;
  });
