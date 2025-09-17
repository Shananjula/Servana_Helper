// functions/src/index.ts
import * as admin from "firebase-admin";

try {
  admin.initializeApp();
} catch (_) {
  /* already initialized in emulator/test */
}

// === Your callable & trigger exports ===
export { publishTask } from "./publishTask";            // if present
export { inviteHelper } from "./inviteHelper";          // new (DM intro fee)
export { acceptOffer } from "./acceptOffer";            // origin-aware accept
export { onTaskCreate } from "./onTaskCreate";          // posting fee safety net

// Keep chat sync (if you have it)
export { onOfferCreate, onOfferUpdate } from "./offerToChat"; // if present

// Re-enable mirroring to top-level /offers
export {
  mirrorOfferCreate,
  mirrorOfferUpdate,
  mirrorOfferDelete,
} from "./offerMirror";
export { backfillOffersPosterId } from "./maintenance/backfillOffersPosterId";
export { backfillAllOffersPosterId } from "./maintenance/backfillAllOffersPosterId";
export { onOfferSignals } from "./onOfferSignals";