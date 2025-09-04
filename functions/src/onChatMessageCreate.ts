// functions/src/onChatMessageCreate.ts
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
try { admin.app(); } catch { admin.initializeApp(); }
const db = admin.firestore();

export const onChatMessageCreate = functions.firestore
  .document('chats/{channelId}/messages/{messageId}')
  .onCreate(async (snap, ctx) => {
    const m = snap.data() || {};
    const channelId = ctx.params.channelId as string;
    const sender = String(m.senderId || '');
    const chatDoc = await db.collection('chats').doc(channelId).get();
    const chat = chatDoc.data() || {};
    const parts: string[] = chat.participants || chat.participantIds || [];
    const target = parts.find((u: string) => u && u !== sender);
    if (!target) return;

    const title = 'New message';
    const body  = String(m.text || 'Tap to open');

    // Save to in-app inbox
    await db.collection('users').doc(target).collection('notifications').add({
      userId: target,
      type: 'chat',
      title,
      body,
      channelId,
      read: false,
      archived: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Push to topic
    await admin.messaging().send({
      topic: `user_${target}`,
      notification: { title, body },
      data: { type: 'chat', channelId, title, body },
      android: { priority: 'high', notification: { channelId: 'servana_general', visibility: 'PUBLIC', sound: 'default', clickAction: 'FLUTTER_NOTIFICATION_CLICK' } },
      apns: { headers: { 'apns-priority': '10', 'apns-push-type': 'alert' }, payload: { aps: { alert: { title, body }, sound: 'default' } } }
    });
  });