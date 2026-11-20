/**
 * RoadResQ Token Engine
 * Generates unique 6-character vehicle tokens for garage handover workflow.
 * Uses a confusable-free character set (no I/O/0/1) with uniqueness enforcement.
 */

const crypto = require("crypto");
const functions = require("firebase-functions");
const admin = require("firebase-admin");

const db = admin.firestore();

const TOKEN_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const TOKEN_LENGTH = 6;
const MAX_RETRIES = 10;
// Must stay in sync with `tokenTtl` in lib/providers/token_provider.dart.
// `verifyToken` skips its expiry check when `expiresAt` is absent, so a token
// written without this field would never expire.
const TOKEN_TTL_MINUTES = 30;

/**
 * Generate a cryptographically secure random token code from the allowed
 * character set.
 *
 * Uses crypto.randomInt (CSPRNG) rather than Math.random: this code authorises
 * a physical vehicle handover, so it must not be predictable from previously
 * issued tokens.
 */
function generateTokenCode() {
  let code = "";
  for (let i = 0; i < TOKEN_LENGTH; i++) {
    code += TOKEN_CHARS.charAt(crypto.randomInt(TOKEN_CHARS.length));
  }
  return code;
}

/**
 * Generate a unique token code that does not already exist in the tokens collection.
 * Retries up to MAX_RETRIES times on collision.
 */
async function generateUniqueTokenCode() {
  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    const code = generateTokenCode();
    const existing = await db
      .collection("tokens")
      .where("tokenCode", "==", code)
      .limit(1)
      .get();

    if (existing.empty) {
      return code;
    }
  }
  throw new Error(
    `Failed to generate unique token after ${MAX_RETRIES} attempts`
  );
}

/**
 * generateToken
 * Callable function — generates a 6-char vehicle token, stores it in Firestore,
 * and returns the token details including QR data.
 *
 * Input: { userId, crewId, garageId, vehicleNumber }
 * Output: { success, tokenId, tokenCode, qrData }
 */
exports.generateToken = functions.https.onCall(async (data, context) => {
  // Require authentication
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be signed in to generate a token."
    );
  }

  const { userId, crewId, garageId, vehicleNumber } = data;

  if (!userId || !crewId || !garageId || !vehicleNumber) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "All fields are required: userId, crewId, garageId, vehicleNumber."
    );
  }

  try {
    const tokenCode = await generateUniqueTokenCode();
    const qrData = `https://roadresq-e4b7b.web.app/token/${tokenCode}`;
    const now = admin.firestore.FieldValue.serverTimestamp();
    // This is what actually time-limits the token: verifyToken only enforces
    // expiry when expiresAt is present. Mirrors the client-side 30 min TTL.
    const expiresAt = admin.firestore.Timestamp.fromMillis(
      Date.now() + TOKEN_TTL_MINUTES * 60 * 1000
    );

    const tokenRef = db.collection("tokens").doc();
    await tokenRef.set({
      tokenCode: tokenCode,
      qrUrl: qrData,
      userId: userId,
      crewId: crewId,
      garageId: garageId,
      vehicleNumber: vehicleNumber,
      vehicleType: "",
      status: "generated",
      issuedFor: "garage_pickup",
      expiresAt: expiresAt,
      consumedAt: null,
      garageName: null,
      garagePhone: null,
      garageAddress: null,
      notes: null,
      createdAt: now,
      updatedAt: now,
      handedOverAt: null,
      repairStartedAt: null,
      readyForPickupAt: null,
      closedAt: null,
    });

    return {
      success: true,
      tokenId: tokenRef.id,
      tokenCode: tokenCode,
      qrData: qrData,
    };
  } catch (error) {
    console.error("generateToken error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});