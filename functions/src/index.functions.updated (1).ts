 
// functions/src/index.ts
import * as admin from "firebase-admin";
try { admin.initializeApp(); } catch {}

export { inviteHelper } from "./inviteHelper";           // if present
export { acceptOffer } from "./acceptOffer";             // origin-aware accept (already added earlier)
export { onTaskCreate } from "./onTaskCreate";           // posting fee safety
export { onOfferSignals } from "./onOfferSignals";       // push notifications (if you added earlier)
export { mirrorOfferCreate, mirrorOfferUpdate, mirrorOfferDelete } from "./offerMirror"; // optional mirroring

// NEW — chat-based negotiation plumbing
export { onOfferCreateToChat, onOfferUpdateToChat } from "./offerChatBridge";
export { proposeCounter, rejectOffer, withdrawOffer, agreeToCounter, helperCounter } from "./counterOffers";
