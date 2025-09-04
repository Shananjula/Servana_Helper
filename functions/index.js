/* eslint-disable max-len */
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

admin.initializeApp();
const db = admin.firestore();

// --- Gemini API Configuration (fixed endpoint) ---
var _cfg = functions.config ? functions.config() : {};
var _gem = _cfg && _cfg.gemini ? _cfg.gemini : {};
const GEMINI_API_KEY = _gem && _gem.key ? _gem.key : null;
const GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=" + (GEMINI_API_KEY || "");

// Define the commission fee constant
const HELPER_COMMISSION_FEE = 25.0;

// -------------------- Helpers --------------------
function normalizeCategoryId(s) {
  return String(s || "").trim().toLowerCase().replace(/\s+/g, "_");
}

// Central recompute for users/{uid}.allowedCategoryIds
async function recomputeAllowed(uid) {
  if (!uid) return null;

  var proofsSnap = await db.collection("category_proofs").where("userId", "==", uid).get();
  var extraSnap = await db.collection("category_proofs").where("uid", "==", uid).get();

  var proofs = [];
  proofsSnap.docs.forEach(function(d){ proofs.push(d); });
  extraSnap.docs.forEach(function(d){ proofs.push(d); });

  var basicSnap = await db.collection("basic_docs").doc(uid).get();
  var basicApproved = basicSnap.exists &&
    ["approved","verified"].indexOf(String((basicSnap.data()||{}).status || "").toLowerCase()) !== -1;

  var allowedSet = {};
  for (var i=0;i<proofs.length;i++) {
    var p = proofs[i].data() || {};
    var status = String(p.status || "").toLowerCase();
    if (["approved","verified"].indexOf(status) === -1) continue;
    var catId = String(p.categoryId || "").trim();
    if (!catId) continue;
    var mode = String(p.mode || "").toLowerCase() || "online";
    if (mode === "physical" && !basicApproved) continue;
    allowedSet[catId] = true;
  }
  var allowed = Object.keys(allowedSet);

  await db.collection("users").doc(uid).set({
    allowedCategoryIds: allowed,
    allowedUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    basicApproved: basicApproved
  }, { merge: true });

  return allowed;
}

// -------------------- AI FILTER --------------------
exports.parseFilterQuery = functions.https.onCall(async function(data, context){
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "You must be logged in to use this feature.");
  }
  var userQuery = data && data.query;
  if (!userQuery) {
    throw new functions.https.HttpsError("invalid-argument", "The function must be called with one argument 'query'.");
  }
  if (!GEMINI_API_KEY) {
    throw new functions.https.HttpsError("failed-precondition", "Missing Gemini API key. Set with: firebase functions:config:set gemini.key=YOUR_KEY");
  }
  var prompt = [
    "Analyze the following user query for a service app in Sri Lanka. Extract:",
    "- category (e.g., Plumbing, Electrician, Graphic Design)",
    "- location (e.g., Colombo, Kandy, Galle)",
    "- max_budget (a number, for queries like 'under 10000')",
    "- isVerified (true if user asks for 'verified', 'trusted', or 'professional' helpers)",
    "Respond ONLY with a valid JSON object (no extra text).",
    "If an entity is not mentioned, omit its key.",
    'User Query: "' + userQuery + '"',
    "JSON Response:"
  ].join("\n");

  try {
    var response = await fetch(GEMINI_API_URL, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        contents: [{parts: [{text: prompt}]}],
        generationConfig: { responseMimeType: "application/json" }
      })
    });
    if (!response.ok) {
      throw new functions.https.HttpsError("internal", "API call failed with status: " + response.status);
    }
    var result = await response.json();
    var text = result && result.candidates && result.candidates[0] &&
               result.candidates[0].content && result.candidates[0].content.parts &&
               result.candidates[0].content.parts[0] && result.candidates[0].content.parts[0].text;
    if (!text) {
      functions.logger.error("Unexpected Gemini API response:", result);
      throw new functions.https.HttpsError("internal", "Failed to parse the AI response.");
    }
    return JSON.parse(text);
  } catch (err) {
    functions.logger.error("Gemini/API JSON parse error:", err);
    throw new functions.https.HttpsError("internal", "Failed to parse filter query.", String(err && err.message || err));
  }
});

// -------------------- ACCEPT OFFER --------------------
exports.acceptOffer = functions.https.onCall(async function(data, context){
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "You must be logged in to accept an offer.");
  }
  var posterId = context.auth.uid;
  var taskId = data && data.taskId;
  var offerId = data && data.offerId;
  if (!taskId || !offerId) {
    throw new functions.https.HttpsError("invalid-argument", "Call with 'taskId' and 'offerId'.");
  }

  var taskRef  = db.collection("tasks").doc(taskId);
  var offerRef = taskRef.collection("offers").doc(offerId);

  try {
    await db.runTransaction(async function(transaction){
      var taskDoc  = await transaction.get(taskRef);
      var offerDoc = await transaction.get(offerRef);

      if (!taskDoc.exists)  throw new functions.https.HttpsError("not-found", "Task not found.");
      if (!offerDoc.exists) throw new functions.https.HttpsError("not-found", "Offer not found.");

      var taskData  = taskDoc.data() || {};
      var offerData = offerDoc.data() || {};
      var helperId  = offerData.helperId;

      if (String(taskData.posterId || "") !== posterId) {
        throw new functions.https.HttpsError("permission-denied", "You are not the owner of this task.");
      }
      var status = String(taskData.status || "").toLowerCase();
      if (["open","listed","negotiating","negotiation"].indexOf(status) === -1) {
        throw new functions.https.HttpsError("failed-precondition", "This task is no longer open for offers.");
      }
      if (!helperId) {
        throw new functions.https.HttpsError("invalid-argument", "Offer has no helperId.");
      }

      // Category eligibility
      var helperRef = db.collection("users").doc(String(helperId));
      var helperDoc = await transaction.get(helperRef);
      if (!helperDoc.exists) throw new functions.https.HttpsError("not-found", "Helper not found.");

      var helperData = helperDoc.data() || {};
      var allowed = Array.isArray(helperData.allowedCategoryIds) ? helperData.allowedCategoryIds.map(String) : [];
      var taskCat = String((taskData.categoryId || taskData.category || "")).trim();

      if (!taskCat || allowed.indexOf(taskCat) === -1) {
        throw new functions.https.HttpsError("failed-precondition", "Helper is not verified for this task category.");
      }

      // Commission check
      var helperCoins = Number(helperData.servCoinBalance || 0);
      if (helperCoins < HELPER_COMMISSION_FEE) {
        throw new functions.https.HttpsError("failed-precondition", "Helper has insufficient coins to cover the commission.");
      }

      var finalAmount = null;
      if (offerData && offerData.amount !== undefined && offerData.amount !== null) {
        finalAmount = offerData.amount;
      } else if (offerData && offerData.price !== undefined && offerData.price !== null) {
        finalAmount = offerData.price;
      }

      var helperName      = helperData.displayName || "Unknown Helper";
      var helperAvatarUrl = helperData.photoURL || null;
      var helperPhone     = helperData.phoneNumber || null;

      var posterRef  = db.collection("users").doc(posterId);
      var posterDoc  = await transaction.get(posterRef);
      var posterPhone = posterDoc.exists && posterDoc.data() ? posterDoc.data().phoneNumber : null;

      // Assign task
      transaction.update(taskRef, {
        status: "assigned",
        finalAmount: finalAmount,
        assignedHelperId: helperId,
        assignedHelperName: helperName,
        assignedHelperAvatarUrl: helperAvatarUrl,
        assignedHelperPhoneNumber: helperPhone,
        posterPhoneNumber: posterPhone,
        assignmentTimestamp: admin.firestore.FieldValue.serverTimestamp(),
        participantIds: [posterId, helperId],
        assignedOfferId: offerId
      });

      // Commission debit
      transaction.update(helperRef, {
        servCoinBalance: admin.firestore.FieldValue.increment(-HELPER_COMMISSION_FEE),
      });

      var txRef = helperRef.collection("transactions").doc();
      transaction.set(txRef, {
        amount: -HELPER_COMMISSION_FEE,
        type: "commission",
        description: 'Commission for task: "' + (taskData.title || taskId) + '"',
        relatedTaskId: taskId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Offer becomes accepted
      transaction.update(offerRef, { status: "accepted", updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    });

    return { success: true, message: "Offer accepted successfully!" };
  } catch (error) {
    functions.logger.error("Error accepting offer:", error);
    if (error && error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", "An unexpected error occurred.");
  }
});

// -------------------- Notifications helper --------------------
async function sendAndSaveNotification(userId, title, body, dataPayload) {
  dataPayload = dataPayload || {};
  try {
    // In-app inbox
    await db.collection("users").doc(userId).collection("notifications").add({
      userId: userId,
      type: dataPayload.type || "system",
      title: title,
      body: body,
      channelId: dataPayload.channelId || undefined,
      taskId: dataPayload.taskId || undefined,
      offerId: dataPayload.offerId || undefined,
      read: false,
      archived: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Topic first (user_<uid>) so multiple devices receive it reliably
    const topic = `user_${userId}`;
    const message = {
      topic: topic,
      notification: { title, body },
      data: Object.assign({ title, body }, dataPayload),
      android: {
        priority: "high",
        collapseKey: dataPayload.collapseKey || undefined,
        notification: {
          channelId: "servana_general",
          visibility: "PUBLIC",
          sound: "default",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      },
      apns: {
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
        },
        payload: {
          aps: {
            alert: { title, body },
            sound: "default",
            // "interruption-level": "time-sensitive" // uncomment if appropriate
          },
        },
      },
    };
    await admin.messaging().send(message);

    // Also send to raw tokens if present (legacy path)
    const userDoc = await db.collection("users").doc(userId).get();
    if (userDoc.exists) {
      const fcmTokens = (userDoc.data() && userDoc.data().fcmTokens) || [];
      if (Array.isArray(fcmTokens) && fcmTokens.length > 0) {
        await admin.messaging().sendToDevice(
          fcmTokens,
          {
            notification: { title, body },
            data: Object.assign({ title, body }, dataPayload),
          },
          {
            android: { priority: "high" },
            apns: { headers: { "apns-priority": "10", "apns-push-type": "alert" } },
          }
        );
      }
    }
  } catch (error) {
    functions.logger.error("Error sending notification to " + userId + ":", error);
  }
}

// -------------------- Task Management & Activity --------------------
exports.onTaskCreateForActivity = functions.firestore
  .document("tasks/{taskId}")
  .onCreate(function(snap, context){
    var task = snap.data();
    if (!task || !task.posterId) return null;
    var chatRef = db.collection("chats").doc();
    return db.runTransaction(async function(transaction){
      transaction.set(snap.ref, {
        participantIds: [task.posterId],
        chatId: chatRef.id
      }, { merge: true });
      transaction.set(chatRef, {
        taskId: snap.id,
        participantIds: [task.posterId],
        isTaskChat: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  });

exports.onTaskUpdateForActivity = functions.firestore
  .document("tasks/{taskId}")
  .onUpdate(function(change, context){
    var before = change.before.data() || {};
    var after = change.after.data() || {};
    if (!before.assignedHelperId && after.assignedHelperId) {
      var chatRef = db.collection("chats").doc(after.chatId);
      return db.runTransaction(async function(transaction){
        transaction.update(change.after.ref, {
          participantIds: admin.firestore.FieldValue.arrayUnion(after.assignedHelperId),
        });
        transaction.update(chatRef, {
          participantIds: admin.firestore.FieldValue.arrayUnion(after.assignedHelperId),
        });
      });
    }
    return null;
  });

// -------------------- Task Radio --------------------
exports.onUrgentTaskCreate = functions.firestore
  .document("tasks/{taskId}")
  .onCreate(async function(snap, context){
    var task = snap.data();
    if (!task || !task.isUrgent || !task.location) return null;
    var liveHelpersSnapshot = await db.collection("users")
      .where("isLive", "==", true)
      .where("isHelper", "==", true)
      .get();
    if (liveHelpersSnapshot.empty) return null;

    var taskLat = task.location.latitude;
    var taskLon = task.location.longitude;
    var notificationPromises = [];
    var logPromises = [];

    liveHelpersSnapshot.forEach(function(doc){
      var helper = doc.data();
      if (helper && helper.workLocation) {
        var helperLat = helper.workLocation.latitude;
        var helperLon = helper.workLocation.longitude;
        var R = 6371;
        var dLat = (helperLat - taskLat) * (Math.PI / 180);
        var dLon = (helperLon - taskLon) * (Math.PI / 180);
        var a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
          Math.cos(taskLat * (Math.PI / 180)) *
          Math.cos(helperLat * (Math.PI / 180)) *
          Math.sin(dLon / 2) * Math.sin(dLon / 2);
        var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        var distance = R * c;
        if (distance <= 10) {
          notificationPromises.push(sendAndSaveNotification(
            doc.id,
            "🚨 Urgent Task Nearby!",
            '"' + (task.title || "") + '" is just ' + distance.toFixed(1) + "km away.",
            { type: "task_details", relatedId: snap.id }
          ));
          logPromises.push(
            snap.ref.collection("urgent_notifications_log").add({
              helperId: doc.id,
              helperName: (helper && helper.displayName) || "Unknown Helper",
              distance: distance,
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
            })
          );
        }
      }
    });
    return Promise.all(notificationPromises.concat(logPromises));
  });

// -------------------- AI moderation --------------------
exports.onNewTaskScan = functions.firestore
  .document("tasks/{taskId}")
  .onCreate(async function(snap, context){
    var task = snap.data();
    if (!task) return null;
    var contentToScan = (task.title || "") + " " + (task.description || "");
    var prompt = 'Analyze the following text for harmful content (hate speech, harassment, violence, explicit content). Respond with a single word: "Safe" or "Unsafe". Text: "' + contentToScan + '"';
    try {
      if (!GEMINI_API_KEY) return null;
      var response = await fetch(GEMINI_API_URL, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({ contents: [{ parts: [{ text: prompt }]}]}),
      });
      if (!response.ok) throw new Error("API call failed with status: " + response.status);
      var result = await response.json();
      var classification =
        result && result.candidates && result.candidates[0] &&
        result.candidates[0].content && result.candidates[0].content.parts &&
        result.candidates[0].content.parts[0] &&
        String(result.candidates[0].content.parts[0].text || "").trim();
      if (classification && classification.toLowerCase().indexOf("unsafe") !== -1) {
        await snap.ref.update({ status: "under_review" });
        await db.collection("reports").add({
          contentType: "task",
          reportedContentId: snap.id,
          contentSnippet: task.title,
          reason: "Automatically flagged by AI for harmful content.",
          reporterId: "system_ai",
          reporterName: "Community Watch AI",
          reportedUserId: task.posterId,
          status: "pending",
          reportedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      functions.logger.error("Error with Gemini API during content scan:", e);
    }
    return null;
  });

// -------------------- Offer notification --------------------
exports.sendOfferNotification = functions.firestore
  .document("tasks/{taskId}/offers/{offerId}")
  .onCreate(async function(snap, context){
    var offer = snap.data();
    if (!offer) return null;
    var taskDoc = await db.collection("tasks").doc(offer.taskId).get();
    if (!taskDoc.exists) return null;
    var task = taskDoc.data();
    if (!task) return null;
    return sendAndSaveNotification(
      task.posterId,
      'New Offer for "' + (task.title || "") + '"',
      (offer.helperName || "A helper") + " has made an offer of LKR " + (offer.amount || "") + ".",
      { type: "task_offer", relatedId: offer.taskId }
    );
  });

// -------------------- User setup --------------------
exports.onUserCreateSetup = functions.auth.user().onCreate(function(user){
  return db.collection("users").doc(user.uid).set({
    email: user.email,
    displayName: user.displayName,
    photoURL: user.photoURL,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    isHelper: false,
    trustScore: 10,
    servCoinBalance: 0
  }, { merge: true });
});

// -------------------- Keep tasks.categoryId normalized --------------------
exports.onTaskCreateBackfillCategoryId = functions.firestore
  .document("tasks/{taskId}")
  .onCreate(async function(snap, ctx){
    var t = snap.data() || {};
    var has = typeof t.categoryId === "string" && t.categoryId.trim() !== "";
    if (has) return null;
    var derived = normalizeCategoryId(t.category || "");
    if (!derived) return null;
    await snap.ref.set({
      categoryId: derived,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
    return null;
  });

// -------------------- Admin helpers --------------------
async function assertAdmin(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required");
  }
  var uid = context.auth.uid;
  var doc = await db.collection("users").doc(uid).get();
  var m = doc.data() || {};
  var isAdmin = (m.isAdmin === true) || (m.roles && m.roles.admin === true);
  if (!isAdmin) {
    throw new functions.https.HttpsError("permission-denied", "Admin only");
  }
  return uid;
}

exports.resolveDisputeAdmin = functions.https.onCall(async function(data, context){
  var uid = await assertAdmin(context);
  var disputeId = data && data.disputeId;
  var resolution = data && data.resolution;
  var posterDelta = data && data.posterDelta ? data.posterDelta : 0;
  var helperDelta = data && data.helperDelta ? data.helperDelta : 0;
  var notes = data && data.notes ? data.notes : "";
  if (!disputeId || !resolution) throw new functions.https.HttpsError("invalid-argument","Missing fields");

  var ref = db.collection("disputes").doc(disputeId);
  await db.runTransaction(async function(trx){
    var snap = await trx.get(ref);
    var m = snap.data() || {};
    var posterId = m.posterId || "";
    var helperId = m.helperId || "";

    async function applyDelta(userId, amt) {
      if (!userId || !amt) return;
      var uref = db.collection("users").doc(userId);
      var usnap = await trx.get(uref);
      var u = usnap.data() || {};
      var prev = u.walletBalance || 0;
      trx.set(uref, { walletBalance: prev + amt, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
      var tx = db.collection("transactions").doc();
      trx.set(tx, {
        userId: userId,
        type: "dispute_adjustment",
        amount: amt,
        status: "ok",
        notes: "dispute:" + disputeId + " " + (notes || ""),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await applyDelta(posterId, posterDelta);
    await applyDelta(helperId, helperDelta);
    trx.set(ref, {
      status: "resolved",
      resolution: resolution,
      resolutionNotes: notes,
      resolvedBy: uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    var audit = db.collection("admin_audit").doc();
    trx.set(audit, {
      actor: uid,
      action: "resolve_dispute",
      disputeId: disputeId,
      resolution: resolution,
      posterDelta: posterDelta,
      helperDelta: helperDelta,
      notes: notes,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
  });
  return { ok: true };
});

exports.createPayoutBatch = functions.https.onCall(async function(data, context){
  var uid = await assertAdmin(context);
  var lines = (data && Array.isArray(data.lines)) ? data.lines : [];
  if (!lines.length) throw new functions.https.HttpsError("invalid-argument","No lines");
  var total = 0;
  for (var i=0;i<lines.length;i++) {
    var amt = parseInt(lines[i].amount || 0, 10) || 0;
    total += amt;
  }
  var batchRef = db.collection("payouts").doc();
  await batchRef.set({
    status: "pending",
    total: total,
    lines: lines,
    createdBy: uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  var audit = db.collection("admin_audit").doc();
  await audit.set({actor: uid, action: "create_payout_batch", batchId: batchRef.id, total: total, createdAt: admin.firestore.FieldValue.serverTimestamp()});
  return { ok: true, id: batchRef.id };
});

exports.markPayoutPaid = functions.https.onCall(async function(data, context){
  var uid = await assertAdmin(context);
  var batchId = data && data.batchId;
  var txId = data && data.txId;
  if (!batchId || !txId) throw new functions.https.HttpsError("invalid-argument","Missing fields");
  var ref = db.collection("payouts").doc(batchId);
  await ref.set({
    status: "paid",
    txId: txId,
    paidAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    paidBy: uid
  }, { merge: true });
  var audit = db.collection("admin_audit").doc();
  await audit.set({actor: uid, action: "mark_payout_paid", batchId: batchId, txId: txId, createdAt: admin.firestore.FieldValue.serverTimestamp()});
  return { ok: true };
});

exports.sendCampaign = functions.https.onCall(async function(data, context){
  var uid = await assertAdmin(context);
  var title = data && data.title;
  var body = data && data.body;
  var category = data && data.category;
  var city = data && data.city;
  var trustMin = data && data.trustMin;
  if (!title || !body) throw new functions.https.HttpsError("invalid-argument","Missing title/body");
  var topics = [];
  if (category) {
    topics.push("tasks_" + String(category).toLowerCase());
    if (city) topics.push("tasks_" + String(category).toLowerCase() + "_" + String(city).toLowerCase());
  } else {
    topics.push("all_helpers");
  }
  for (var i=0;i<topics.length;i++) {
    var topic = topics[i];
    await admin.messaging().send({
      notification: { title: title, body: body },
      data: { type: "system", audience: topic },
      topic: topic
    });
  }
  var doc = {
    title: title,
    body: body,
    audience: topics.join(","),
    trustMin: trustMin || null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy: uid
  };
  await db.collection("campaigns").add(doc);
  return { ok: true, topics: topics };
});

// -------------------- Verification recompute triggers --------------------
exports.onCategoryProofWrite = functions.firestore
  .document("category_proofs/{docId}")
  .onWrite(async function(change, context){
    var after = change.after.exists ? change.after.data() : null;
    var before = change.before.exists ? change.before.data() : null;
    var uid = (after && (after.userId || after.uid)) || (before && (before.userId || before.uid)) || null;
    if (!uid) return null;
    await recomputeAllowed(uid);
    return null;
  });

exports.onBasicDocsWrite = functions.firestore
  .document("basic_docs/{uid}")
  .onWrite(async function(change, context){
    var uid = context.params && context.params.uid;
    if (!uid) return null;
    await recomputeAllowed(uid);
    return null;
  });

exports.recomputeAllowedForUser = functions.https.onCall(async function(data, context){
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated","Auth required");
  var token = context.auth.token || {};
  if (!(token.admin === true)) throw new functions.https.HttpsError("permission-denied","Admin only");
  var uid = data && data.uid;
  if (!uid) throw new functions.https.HttpsError("invalid-argument","uid is required");
  var allowed = await recomputeAllowed(uid);
  var basicSnap = await db.collection("basic_docs").doc(uid).get();
  var basicApproved = basicSnap.exists && ["approved","verified"].indexOf(String((basicSnap.data()||{}).status || "").toLowerCase()) !== -1;
  return { ok: true, allowed: allowed, basicApproved: basicApproved };
});

// NOTE: Removed old duplicate sync fanouts to avoid double-writes

// ---- Activity helpers ----
async function _addActivity(pathPieces, payload) {
  const fs = admin.firestore();
  const col = fs.collection(pathPieces.join("/"));
  await col.add({
    ts: admin.firestore.FieldValue.serverTimestamp(),
    by: payload.by || "system",
    ...payload,
  });
}

// Normalize legacy/variants
function _normStatus(s) {
  const v = String(s || "").toLowerCase();
  if (v === "verified") return "approved";
  return v;
}

// ---- Log activity for category_proofs changes ----
exports.logCategoryProofActivity = functions.firestore
  .document("category_proofs/{docId}")
  .onWrite(async (change, ctx) => {
    const docId = ctx.params.docId;
    const before = change.before.exists ? change.before.data() : null;
    const after  = change.after.exists  ? change.after.data()  : null;
    if (!after && !before) return null;

    const by = (after && (after.reviewedBy || after.reviewerId)) ||
               (before && (before.reviewedBy || before.reviewerId)) || "system";

    // Created => submitted
    if (!before && after) {
      await _addActivity(["category_proofs", docId, "activity"], {
        type: "submitted",
        status: _normStatus(after.status || "pending"),
        note: "Proof submitted",
        categoryId: after.categoryId || null,
        mode: after.mode || "online",
        by,
      });
      return null;
    }

    // Status transitions
    if (before && after) {
      const prev = _normStatus(before.status || "");
      const next = _normStatus(after.status || "");
      if (prev !== next) {
        await _addActivity(["category_proofs", docId, "activity"], {
          type: "status_change",
          from: prev || "unknown",
          to: next,
          status: next,
          categoryId: after.categoryId || null,
          mode: after.mode || "online",
          notes: after.notes || "",
          by,
        });
      } else if ((before.notes || "") !== (after.notes || "")) {
        // Notes changed without status change
        await _addActivity(["category_proofs", docId, "activity"], {
          type: "note",
          status: next || prev || "pending",
          notes: after.notes || "",
          categoryId: after.categoryId || null,
          mode: after.mode || "online",
          by,
        });
      }
    }
    return null;
  });

// ---- Log activity for basic_docs changes ----
exports.logBasicDocsActivity = functions.firestore
  .document("basic_docs/{uid}")
  .onWrite(async (change, ctx) => {
    const uid = ctx.params.uid;
    const before = change.before.exists ? change.before.data() : null;
    const after  = change.after.exists  ? change.after.data()  : null;
    if (!after && !before) return null;

    const by = (after && (after.reviewedBy || after.reviewerId)) ||
               (before && (before.reviewedBy || before.reviewerId)) || "system";

    if (!before && after) {
      await _addActivity(["basic_docs", uid, "activity"], {
        type: "submitted",
        status: _normStatus(after.status || "pending"),
        note: "Basic documents submitted",
        by,
      });
      return null;
    }

    if (before && after) {
      const prev = _normStatus(before.status || "");
      const next = _normStatus(after.status || "");
      if (prev !== next) {
        await _addActivity(["basic_docs", uid, "activity"], {
          type: "status_change",
          from: prev || "unknown",
          to: next,
          status: next,
          notes: after.notes || "",
          by,
        });
      } else if ((before.notes || "") !== (after.notes || "")) {
        await _addActivity(["basic_docs", uid, "activity"], {
          type: "note",
          status: next || prev || "pending",
          notes: after.notes || "",
          by,
        });
      }
    }
    return null;
  });
