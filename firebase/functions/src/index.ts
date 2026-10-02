import {initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {computeRedemption, InvalidDraftError} from "./points";

initializeApp();

const db = getFirestore();

/**
 * Redeems an intake QR for the calling user. This is the only code path that
 * awards points: firestore.rules block clients from writing points, stats,
 * transactions, or a QR's `used` flag.
 *
 * Input: {qrId}, the doc id from the `KITAKITAR_QR:<qrId>` payload.
 * Returns: {pointsUser, co2Saved, totalWeight}.
 */
export const redeemQr = onCall({maxInstances: 10}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Please log in to claim Kitar Points.");
  }

  const qrId: unknown = request.data?.qrId;
  if (typeof qrId !== "string" || qrId.trim() === "" || qrId.includes("/")) {
    throw new HttpsError("invalid-argument", "Invalid QR code payload.");
  }

  const qrRef = db.collection("qr_codes").doc(qrId);

  // A transaction (not a batch) so two concurrent claims of the same QR
  // can't both see `used == false`.
  return db.runTransaction(async (tx) => {
    const qrSnap = await tx.get(qrRef);
    if (!qrSnap.exists) {
      throw new HttpsError("not-found", "QR code not found");
    }
    const qr = qrSnap.data() ?? {};
    if (qr.used === true) {
      throw new HttpsError("failed-precondition", "This QR code has already been used");
    }
    const centerId: unknown = qr.centerId;
    if (typeof centerId !== "string" || centerId === "") {
      throw new HttpsError("failed-precondition", "Invalid QR code");
    }
    if (centerId === uid) {
      throw new HttpsError("permission-denied", "A center can't claim its own QR code");
    }

    let redemption;
    try {
      redemption = computeRedemption(qr.transactionDraft);
    } catch (e) {
      if (e instanceof InvalidDraftError) {
        throw new HttpsError("failed-precondition", e.message);
      }
      throw e;
    }
    const {materials, totalWeight, pointsUser, co2Saved, stats} = redemption;
    const pointsCenter = pointsUser;

    const centerRef = db.collection("centers").doc(centerId);
    const centerSnap = await tx.get(centerRef);
    if (!centerSnap.exists) {
      throw new HttpsError("failed-precondition", "Recycling center not found");
    }

    const now = FieldValue.serverTimestamp();
    const statsIncrements: Record<string, FieldValue> = {};
    for (const [type, weight] of Object.entries(stats)) {
      statsIncrements[type] = FieldValue.increment(weight);
    }

    tx.update(qrRef, {
      used: true,
      usedBy: uid,
      usedAt: now,
    });
    tx.create(db.collection("transactions").doc(), {
      userId: uid,
      centerId,
      materials,
      totalWeight,
      pointsUser,
      pointsCenter,
      co2Saved,
      createdAt: now,
      qrCodeId: qrId,
    });
    tx.set(db.collection("users").doc(uid), {
      points: FieldValue.increment(pointsUser),
      totalWeight: FieldValue.increment(totalWeight),
      carbonFootprint: FieldValue.increment(co2Saved),
      stats: statsIncrements,
    }, {merge: true});
    tx.update(centerRef, {
      points: FieldValue.increment(pointsCenter),
      totalWeight: FieldValue.increment(totalWeight),
      carbonFootprint: FieldValue.increment(co2Saved),
    });

    return {pointsUser, co2Saved, totalWeight};
  });
});
