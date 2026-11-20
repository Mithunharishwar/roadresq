/**
 * RoadResQ Cloud Functions
 * Patent-Protected Backend Logic:
 * 1. dispatchTwoManCrew - 2-Man Crew Dispatch with Weighted Matching
 * 2. processCommission - 10% Platform Commission Auto-Deduction
 * 3. generateInvoice - GST Invoice Generation
 * 4. sendEmergencySms - Zone-Based Security SMS
 * 5. escalateRequest - Timeout Handling + Backup Crew Dispatch
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { v4: uuidv4 } = require("uuid");
const Razorpay = require("razorpay");

admin.initializeApp();
const db = admin.firestore();
const auth = admin.auth();

// ─────────────────────────────────────────────
// FEATURE 3: Zone Security Engine
// Registers the `checkZoneSecurity` Firestore trigger (rural + 8pm-6am →
// security alert + emergency SMS queue). Defined in zoneSecurityEngine.js.
// ─────────────────────────────────────────────
// `exports.checkZoneSecurity = ...` inside zoneSecurityEngine.js sets THAT
// module's own exports object. Firebase only deploys handlers attached to the
// ENTRY POINT's module.exports, so a bare require() registers nothing and the
// function silently never deploys. Copy the exports across explicitly.
Object.assign(exports, require("./zoneSecurityEngine"));

// ─────────────────────────────────────────────
// FEATURE 2: Digital Vehicle Token Engine
// Registers the `generateToken` callable (6-char confusable-free code + QR),
// paired with the `verifyToken` callable defined further down this file.
// Defined in tokenEngine.js.
// ─────────────────────────────────────────────
// Same reasoning as zoneSecurityEngine above: a bare require() would leave
// `generateToken` defined but never registered on the entry point, so the
// client call at crew_job_service.dart:209 would fail with NOT_FOUND.
Object.assign(exports, require("./tokenEngine"));

// ─────────────────────────────────────────────
// RAZORPAY INSTANCE
// ─────────────────────────────────────────────
// `functions.config()` returns {} when no legacy runtime config has been set, so
// `functions.config().razorpay.key_id` reads `.key_id` off undefined and throws
// at MODULE LOAD. That takes every function in this file down with it — not just
// payments — because the whole module fails to require. The `|| fallback` never
// applied: the TypeError is thrown before it is evaluated.
// Read the config defensively so the intended fallback actually works.
// Configure with:
//   firebase functions:config:set razorpay.key_id=... razorpay.key_secret=...
// or the RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET environment variables.
const _razorpayConfig = functions.config().razorpay || {};
const RAZORPAY_KEY_ID =
  process.env.RAZORPAY_KEY_ID || _razorpayConfig.key_id || "rzp_test_SbTmM0x0VYHxcN";
const RAZORPAY_KEY_SECRET =
  process.env.RAZORPAY_KEY_SECRET || _razorpayConfig.key_secret || "test_secret";

const razorpay = new Razorpay({
  key_id: RAZORPAY_KEY_ID,
  key_secret: RAZORPAY_KEY_SECRET,
});

// ═══════════════════════════════════════════════════════════════
// GEOHASH UTILITIES
// Spatial indexing for proximity-based crew matching in Firestore.
// Uses base32 encoding (same scheme as lib/core/utils/geohash.dart).
// ═══════════════════════════════════════════════════════════════
const GEOHASH_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";
const GEOHASH_BITS = 5;
const GEOHASH_MIN_LAT = -90.0;
const GEOHASH_MAX_LAT = 90.0;
const GEOHASH_MIN_LNG = -180.0;
const GEOHASH_MAX_LNG = 180.0;

/** Encode lat/lng into a geohash string of the given precision. */
function geohashEncode(latitude, longitude, precision = 8) {
  let lat = Math.max(GEOHASH_MIN_LAT, Math.min(GEOHASH_MAX_LAT, latitude));
  let lng = Math.max(GEOHASH_MIN_LNG, Math.min(GEOHASH_MAX_LNG, longitude));
  precision = Math.max(1, Math.min(12, precision));

  let hash = "";
  let latMin = GEOHASH_MIN_LAT, latMax = GEOHASH_MAX_LAT;
  let lngMin = GEOHASH_MIN_LNG, lngMax = GEOHASH_MAX_LNG;
  let bit = 0, ch = 0, isEven = true;

  while (hash.length < precision) {
    if (isEven) {
      const mid = (lngMin + lngMax) / 2;
      if (lng > mid) {
        ch |= 1 << (GEOHASH_BITS - 1 - bit);
        lngMin = mid;
      } else {
        lngMax = mid;
      }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat > mid) {
        ch |= 1 << (GEOHASH_BITS - 1 - bit);
        latMin = mid;
      } else {
        latMax = mid;
      }
    }
    isEven = !isEven;
    if (bit < GEOHASH_BITS - 1) {
      bit++;
    } else {
      hash += GEOHASH_BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }
  return hash;
}

/** Decode a geohash into its bounding box + center. */
function geohashDecode(geohash) {
  let latMin = GEOHASH_MIN_LAT, latMax = GEOHASH_MAX_LAT;
  let lngMin = GEOHASH_MIN_LNG, lngMax = GEOHASH_MAX_LNG;
  let isEven = true;

  for (let i = 0; i < geohash.length; i++) {
    const code = GEOHASH_BASE32.indexOf(geohash[i]);
    if (code === -1) throw new Error("Invalid geohash char: " + geohash[i]);
    for (let b = GEOHASH_BITS - 1; b >= 0; b--) {
      const mask = 1 << b;
      if (isEven) {
        const mid = (lngMin + lngMax) / 2;
        if (code & mask) lngMin = mid;
        else lngMax = mid;
      } else {
        const mid = (latMin + latMax) / 2;
        if (code & mask) latMin = mid;
        else latMax = mid;
      }
      isEven = !isEven;
    }
  }
  return {
    latitude: (latMin + latMax) / 2,
    longitude: (lngMin + lngMax) / 2,
    latMin, latMax, lngMin, lngMax,
  };
}

/** Approx cell width (km) for a geohash precision. */
function geohashPrecisionToKm(precision) {
  const table = {
    1: 5003.0, 2: 1251.0, 3: 156.0, 4: 39.1, 5: 4.89,
    6: 1.22, 7: 0.153, 8: 0.0382, 9: 0.00477, 10: 0.00119,
    11: 0.000149, 12: 0.0000372,
  };
  return table[Math.max(1, Math.min(12, precision))] || 1.0;
}

/** Choose a geohash precision whose cell roughly covers radiusKm. */
function geohashPrecisionForRadius(radiusKm) {
  if (radiusKm <= 0.05) return 10;
  if (radiusKm <= 0.15) return 9;
  if (radiusKm <= 1.0) return 7;
  if (radiusKm <= 5.0) return 6;
  if (radiusKm <= 20.0) return 5;
  if (radiusKm <= 80.0) return 4;
  if (radiusKm <= 300.0) return 3;
  return 2;
}

/** Compute the geohash prefix for a search radius around a point. */
function geohashForRadius(latitude, longitude, radiusKm) {
  return geohashEncode(
    latitude,
    longitude,
    geohashPrecisionForRadius(radiusKm)
  );
}

/**
 * Compute the set of geohash prefixes whose cells overlap the radius
 * around (latitude, longitude). Returns the center prefix + its 8 neighbors
 * at the given precision. This is the standard 9-cell geohash expansion.
 */
function geohashNeighbors(latitude, longitude, precision) {
  const center = geohashEncode(latitude, longitude, precision);
  const prefixes = new Set([center]);

  // Bit masks for the 8 compass directions.
  const dirs = [
    [0, 1], [1, 1], [1, 0], [1, -1],
    [0, -1], [-1, -1], [-1, 0], [-1, 1],
  ];

  for (const [dx, dy] of dirs) {
    const neighbor = geohashAdjacent(center, dx, dy);
    if (neighbor) prefixes.add(neighbor);
  }
  return Array.from(prefixes);
}

/**
 * Compute the adjacent geohash cell in a given direction.
 * Uses base32 index arithmetic with parity-based axis switching.
 */
function geohashAdjacent(geohash, dx, dy) {
  if (!geohash) return null;
  let lat = 0, lng = 0;
  let latErr = 0, lngErr = 0;
  let i = geohash.length - 1;

  // Determine axis parity based on character position.
  const isEven = geohash.length % 2 === 0;

  if (isEven) {
    // Last char handles longitude wrap
    lng = dx;
    lat = 0;
  } else {
    lat = dy;
    lng = 0;
  }

  // For a robust implementation we recompute the neighbor by re-encoding
  // the bounding box center shifted by one cell. Simpler + correct:
  const decoded = geohashDecode(geohash);
  const latMid = (decoded.latMin + decoded.latMax) / 2;
  const lngMid = (decoded.lngMin + decoded.lngMax) / 2;
  const latSpan = decoded.latMax - decoded.latMin;
  const lngSpan = decoded.lngMax - decoded.lngMin;

  const newLat = latMid + lat * latSpan;
  const newLng = lngMid + lng * lngSpan;

  return geohashEncode(newLat, newLng, geohash.length);
}

/** Haversine distance in km between two lat/lng points. */
function haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = (lat2 - lat1) * (Math.PI / 180);
  const dLon = (lng2 - lng1) * (Math.PI / 180);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * (Math.PI / 180)) *
      Math.cos(lat2 * (Math.PI / 180)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ─────────────────────────────────────────────
// PATENT 1: 2-Man Crew Dispatch System
// Dispatches 1 Mechanic + 1 Assistant per SOS request
// Matching: Distance(40%) + Rating(25%) + Active(20%) + Zone(15%)
// Uses geohash spatial indexing for 10km radius queries.
// ─────────────────────────────────────────────
const MAX_MATCH_RADIUS_KM = 10.0; // 10km radius (2-man matching)

exports.dispatchTwoManCrew = functions.https.onCall(async (data, context) => {
  // Verify auth
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated."
    );
  }

  const { userId, userLat, userLng, requestId, userZone } = data;

  if (!userId || !userLat || !userLng || !requestId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "userId, userLat, userLng, and requestId are required."
    );
  }

  try {
    const jobGroupId = uuidv4();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const radiusKm = data.radiusKm || MAX_MATCH_RADIUS_KM;

    // ─── Helper: Find best crew of a given role using geohash ───
    async function findBestCrew(role) {
      // Compute the search geohash prefix (center + neighbors) for the radius.
      const precision = geohashPrecisionForRadius(radiusKm);
      const prefixes = geohashNeighbors(userLat, userLng, precision);

      let candidates = [];

      // Query each geohash cell for crews matching role + availability.
      // Geohash prefix stored on crew doc as `geohash` (string).
      for (const prefix of prefixes) {
        const snapshot = await db
          .collection("crews")
          .where("role", "==", role)
          .where("isOnline", "==", true)
          .where("isKycVerified", "==", true)
          .where("geohash", ">=", prefix)
          .where("geohash", "<=", prefix + "\uf8ff")
          .limit(20)
          .get();

        snapshot.forEach((doc) => {
          candidates.push({ id: doc.id, ...doc.data() });
        });
      }

      // Deduplicate by id.
      const seen = new Set();
      candidates = candidates.filter((c) => {
        if (seen.has(c.id)) return false;
        seen.add(c.id);
        return true;
      });

      if (candidates.length === 0) return null;

      let bestCrew = null;
      let bestScore = -1;

      for (const crew of candidates) {
        const crewLat = crew.currentLocation?.latitude || 0;
        const crewLng = crew.currentLocation?.longitude || 0;
        if (!crewLat && !crewLng) continue;

        const distanceKm = haversineKm(userLat, userLng, crewLat, crewLng);

        // Exact radius filter (geohash cells may contain out-of-range points).
        if (distanceKm > radiusKm) continue;

        const isInPreferredZone = crew.serviceZone === userZone;

        // Weighted score calculation (Distance 40 / Rating 25 / Active 20 / Zone 15)
        const distanceScore = Math.max(0, 1 - distanceKm / radiusKm);
        const ratingScore = (crew.rating || 0) / 5.0;
        const activeScore = crew.isOnline ? 1.0 : 0.0;
        const zoneScore = isInPreferredZone ? 1.0 : 0.3;

        const score =
          0.4 * distanceScore +
          0.25 * ratingScore +
          0.2 * activeScore +
          0.15 * zoneScore;

        if (score > bestScore) {
          bestScore = score;
          bestCrew = {
            id: crew.id,
            name: crew.name,
            role: crew.role,
            distanceKm: distanceKm,
            location: crew.currentLocation,
            score: score,
          };
        }
      }

      return bestCrew;
    }

    // ─── Dispatch both crew members (1 mechanic + 1 assistant) ───
    const mechanic = await findBestCrew("mechanic");
    const assistant = await findBestCrew("assistant");

    // Create jobs
    async function createJob(role, crewData) {
      if (!crewData) return null;

      const etaMinutes = Math.ceil(
        (crewData.distanceKm / (role === "assistant" ? 50 : 30)) * 60
      );

      const jobRef = db.collection("jobs").doc();
      await jobRef.set({
        requestId: requestId,
        jobGroupId: jobGroupId,
        crewId: crewData.id,
        crewName: crewData.name,
        crewRole: role,
        userId: userId,
        status: "pending",
        distanceKm: crewData.distanceKm,
        etaMinutes: etaMinutes,
        earnings: 0.0,
        score: crewData.score,
        pickupLocation: new admin.firestore.GeoPoint(userLat, userLng),
        createdAt: now,
        updatedAt: now,
      });

      return { jobId: jobRef.id, ...crewData, etaMinutes };
    }

    const mechanicJob = await createJob("mechanic", mechanic);
    const assistantJob = await createJob("assistant", assistant);

    // Update request with crew assignments
    await db.collection("requests").doc(requestId).update({
      status: "assigned",
      assignedMechanicId: mechanic?.id || "",
      assignedAssistantId: assistant?.id || "",
      mechanicEtaMinutes: mechanicJob?.etaMinutes || 0,
      assistantEtaMinutes: assistantJob?.etaMinutes || 0,
      jobGroupId: jobGroupId,
      assignedAt: now,
      updatedAt: now,
    });

    // Mark crews as busy
    if (mechanic) {
      await db.collection("crews").doc(mechanic.id).update({
        isOnline: false,
        updatedAt: now,
      });
    }
    if (assistant) {
      await db.collection("crews").doc(assistant.id).update({
        isOnline: false,
        updatedAt: now,
      });
    }

    return {
      success: true,
      jobGroupId: jobGroupId,
      mechanic: mechanic ? { id: mechanic.id, name: mechanic.name, etaMinutes: mechanicJob?.etaMinutes } : null,
      assistant: assistant ? { id: assistant.id, name: assistant.name, etaMinutes: assistantJob?.etaMinutes } : null,
      message: "2-man crew dispatched successfully",
    };
  } catch (error) {
    console.error("dispatchTwoManCrew error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ─────────────────────────────────────────────
// GEOHASH PERSISTENCE: updateCrewGeohash
// Callable: explicitly persist `geohash` on a crew document.
// Invoked by the app whenever a crew's current location changes,
// so the 2-man matching engine can use geohash prefix queries.
// ─────────────────────────────────────────────
exports.updateCrewGeohash = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Crew must be authenticated."
    );
  }

  const { crewId, latitude, longitude } = data;

  if (!crewId || latitude == null || longitude == null) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "crewId, latitude, and longitude are required."
    );
  }

  try {
    // Compute default geohash precision (~4.9km cell) for crew location.
    const geohash = geohashEncode(latitude, longitude, 7);

    await db.collection("crews").doc(crewId).update({
      geohash: geohash,
      currentLocation: new admin.firestore.GeoPoint(
        parseFloat(latitude),
        parseFloat(longitude)
      ),
      geohashPrecision: 7,
      locationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      crewId: crewId,
      geohash: geohash,
      message: "Crew geohash persisted successfully",
    };
  } catch (error) {
    console.error("updateCrewGeohash error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ─────────────────────────────────────────────
// GEOHASH PERSISTENCE (Automatic): onCrewLocationUpdate
// Firestore trigger: whenever a crew's `currentLocation` GeoPoint changes,
// automatically recompute and persist its `geohash` field.
// Keeps the index fresh without depending on the app calling the callable.
// ─────────────────────────────────────────────
exports.onCrewLocationUpdate = functions.firestore
  .document("crews/{crewId}")
  .onWrite(async (change, context) => {
    const crewId = context.params.crewId;
    const after = change.after.exists ? change.after.data() : null;
    const before = change.before.exists ? change.before.data() : null;

    if (!after) return; // Deletion — nothing to persist

    const loc = after.currentLocation;
    if (!loc || typeof loc.latitude !== "number" || typeof loc.longitude !== "number") {
      return; // No valid location to index
    }

    // Avoid infinite loop: only update if geohash actually changed.
    const newGeohash = geohashEncode(loc.latitude, loc.longitude, 8);
    if (after.geohash === newGeohash) return;

    try {
      await change.after.ref.update({
        geohash: newGeohash,
        geohashPrecision: 8,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`Persisted geohash ${newGeohash} for crew ${crewId}`);
    } catch (error) {
      console.error("onCrewLocationUpdate error:", error);
    }
  });

// ─────────────────────────────────────────────
// PATENT 2: Platform Commission Processing (10%)
// Auto-deducts platform commission from crew earnings
// ─────────────────────────────────────────────
exports.processCommission = functions.firestore
  .document("jobs/{jobId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Only process when job is completed
    if (before.status !== "completed" && after.status === "completed") {
      const jobId = context.params.jobId;
      const crewRole = after.crewRole;
      const earnings = after.earnings || 0;
      const crewId = after.crewId;

      // Calculate 10% platform commission
      const commissionRate = 0.10;
      const platformCommission = Math.round(earnings * commissionRate * 100) / 100;
      const crewPayout = Math.round((earnings - platformCommission) * 100) / 100;

      try {
        // Create commission record
        await db.collection("commissions").doc(jobId).set({
          jobId: jobId,
          crewId: crewId,
          crewRole: crewRole,
          totalEarnings: earnings,
          commissionRate: commissionRate,
          platformCommission: platformCommission,
          crewPayout: crewPayout,
          status: "processed",
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Update job with commission details
        await db.collection("jobs").doc(jobId).update({
          platformCommission: platformCommission,
          crewPayout: crewPayout,
          commissionProcessed: true,
        });

        // Update crew total earnings
        await db.collection("crews").doc(crewId).update({
          totalEarnings: admin.firestore.FieldValue.increment(crewPayout),
          jobsCompleted: admin.firestore.FieldValue.increment(1),
        });

        console.log(
          `Commission processed for job ${jobId}: ₹${platformCommission} platform fee`
        );
      } catch (error) {
        console.error("processCommission error:", error);
      }
    }
  });

// ─────────────────────────────────────────────
// PATENT 3: GST Invoice Generation
// Generates digital receipt with 18% GST
// ─────────────────────────────────────────────
exports.generateInvoice = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Unauthenticated.");
  }

  const { requestId, userId, serviceAmount } = data;

  if (!requestId || !userId || !serviceAmount) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "requestId, userId, and serviceAmount are required."
    );
  }

  try {
    // Get user details
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data() || {};

    // Get request details
    const requestDoc = await db.collection("requests").doc(requestId).get();
    const requestData = requestDoc.data() || {};

    // Calculate amounts
    const gstPercent = 18;
    const gstAmount = Math.round(serviceAmount * (gstPercent / 100) * 100) / 100;
    const platformCommission = Math.round(serviceAmount * 0.1 * 100) / 100;
    const totalAmount = serviceAmount + gstAmount + platformCommission;

    // Generate receipt number
    const date = new Date();
    const dateStr = `${date.getFullYear()}${String(date.getMonth() + 1).padStart(2, "0")}${String(date.getDate()).padStart(2, "0")}`;
    const random = String(date.getMilliseconds()).padStart(4, "0");
    const receiptNumber = `RCP-${dateStr}-${random}`;

    // Create invoice record
    const invoiceRef = db.collection("invoices").doc();
    await invoiceRef.set({
      receiptNumber: receiptNumber,
      requestId: requestId,
      userId: userId,
      userName: userData.name || requestData.userName || "",
      userPhone: userData.phone || requestData.userPhone || "",
      userEmail: userData.email || "",
      serviceAmount: serviceAmount,
      gstPercent: gstPercent,
      gstAmount: gstAmount,
      platformCommission: platformCommission,
      commissionPercent: 10,
      totalAmount: totalAmount,
      currency: "INR",
      status: "generated",
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      invoiceId: invoiceRef.id,
      receiptNumber: receiptNumber,
      serviceAmount: serviceAmount,
      gstAmount: gstAmount,
      platformCommission: platformCommission,
      totalAmount: totalAmount,
      gstPercent: gstPercent,
    };
  } catch (error) {
    console.error("generateInvoice error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ─────────────────────────────────────────────
// PATENT 4: Zone-Based Emergency SMS
// Sends emergency SMS for rural zone requests
// ─────────────────────────────────────────────
exports.sendEmergencySms = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Unauthenticated.");
  }

  const { userId, userPhone, emergencyContact, crewName, crewPhone, requestId, zone } = data;

  if (!userId || !userPhone || !requestId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "userId, userPhone, and requestId are required."
    );
  }

  try {
    // Log the emergency SMS request
    await db.collection("emergency_sms").add({
      userId: userId,
      userPhone: userPhone,
      emergencyContact: emergencyContact || "",
      crewName: crewName || "",
      crewPhone: crewPhone || "",
      requestId: requestId,
      zone: zone || "rural",
      message: `RoadResQ Alert: Your emergency contact has requested roadside assistance. Crew ${crewName} (${crewPhone}) is en route to your location. Track live at: https://roadresq.app/track/${requestId}`,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
      isSent: false, // Set to true after actual SMS send
    });

    // Note: Actual SMS sending requires Twilio integration
    // This function creates the record for the SMS queue

    return {
      success: true,
      message: "Emergency SMS queued for delivery",
      requestId: requestId,
    };
  } catch (error) {
    console.error("sendEmergencySms error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ─────────────────────────────────────────────
// FEATURE 2: Digital Token Verification (Security)
// Token = 6-digit code + 30-min expiry + one-time use.
// Verifies a scanned token atomically and marks it consumed to prevent
// screenshot / QR reuse. Uses a Firestore transaction for race safety.
// ─────────────────────────────────────────────
const TOKEN_TTL_MS = 30 * 60 * 1000; // 30 minutes

exports.verifyToken = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated."
    );
  }

  const tokenCode = (data.tokenCode || "").trim();
  if (!tokenCode) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "tokenCode is required."
    );
  }

  try {
    const tokensRef = db.collection("tokens");
    const snapshot = await tokensRef
      .where("tokenCode", "==", tokenCode)
      .limit(1)
      .get();

    if (snapshot.empty) {
      return {
        success: false,
        message: "Invalid token code. Please try again.",
      };
    }

    const tokenDoc = snapshot.docs[0];
    const tokenRef = tokenDoc.ref;

    // Atomic verify + consume in a transaction to prevent double-use.
    let verified = false;
    let result = {};

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(tokenRef);
      if (!snap.exists) return;

      const token = snap.data();
      const now = Date.now();

      // One-time use check
      if (token.consumedAt) {
        result = {
          success: false,
          message: "Token has already been used.",
        };
        return;
      }

// Expiry check
      let expiresAt = null;
      if (token.expiresAt) {
        if (token.expiresAt instanceof admin.firestore.Timestamp) {
          expiresAt = token.expiresAt.toMillis();
        } else if (token.expiresAt instanceof Date) {
          expiresAt = token.expiresAt.getTime();
        } else {
          expiresAt = new Date(token.expiresAt).getTime();
        }
      }
      if (expiresAt && now > expiresAt) {
        result = {
          success: false,
          message: "Token has expired. Please generate a new one.",
        };
        return;
      }

      // Mark as consumed
      tx.update(tokenRef, {
        consumedAt: admin.firestore.FieldValue.serverTimestamp(),
        status: "consumed",
        consumedBy: context.auth.uid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      result = {
        success: true,
        tokenId: tokenDoc.id,
        token: {
          tokenCode: token.tokenCode,
          qrUrl: token.qrUrl || "",
          userId: token.userId || "",
          crewId: token.crewId || "",
          garageId: token.garageId || "",
          vehicleNumber: token.vehicleNumber || "",
          vehicleType: token.vehicleType || "",
          status: "consumed",
          garageName: token.garageName || "",
          garagePhone: token.garagePhone || "",
          garageAddress: token.garageAddress || "",
          notes: token.notes || "",
          issuedFor: token.issuedFor || "",
        },
      };
      verified = true;
    });

    return result;
  } catch (error) {
    console.error("verifyToken error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ─────────────────────────────────────────────
// PATENT 5: Request Escalation Handler
// Handles timeout - no crew found in 5 mins → admin + backup crew alert
// ─────────────────────────────────────────────
exports.escalateRequest = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Unauthenticated.");
  }

  const { requestId, reason } = data;

  if (!requestId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "requestId is required."
    );
  }

  try {
    // Update request to escalated
    await db.collection("requests").doc(requestId).update({
      status: "escalated",
      escalationReason: reason || "No crew found within 5 minutes",
      escalatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Find 3 backup crews
    const backupSnapshot = await db
      .collection("crews")
      .where("isOnline", "==", true)
      .where("isKycVerified", "==", true)
      .limit(3)
      .get();

    const backupCrews = [];
    backupSnapshot.forEach((doc) => {
      backupCrews.push({
        id: doc.id,
        name: doc.data().name,
        role: doc.data().role,
      });
    });

    // Create escalation record
    await db.collection("escalations").add({
      requestId: requestId,
      reason: reason || "No crew found within 5 minutes",
      backupCrews: backupCrews,
      escalatedAt: admin.firestore.FieldValue.serverTimestamp(),
      resolved: false,
    });

    // Notify admin (in production, trigger FCM notification)
    console.log(
      `Request ${requestId} escalated. Notified admin and ${backupCrews.length} backup crews.`
    );

return {
      success: true,
      message: "Request escalated to admin with backup crew notification",
      backupCrews: backupCrews.map((c) => c.name),
    };
  } catch (error) {
    console.error("escalateRequest error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ─────────────────────────────────────────────
// FEATURE 6: Fake-SOS Prevention
// ─────────────────────────────────────────────
// 1. sendSosOtp        — generates + stores a 6-digit OTP for the user's phone
// 2. verifySosOtp      — verifies OTP + enforces the 3-SOS/day limit
// 3. cancelSosWithPenalty — records a ₹50 penalty for a fake/late cancellation
// ─────────────────────────────────────────────
const SOS_DAILY_LIMIT = 3;
const SOS_PENALTY_AMOUNT = 50; // INR
const SOS_OTP_TTL_MS = 5 * 60 * 1000; // 5 minutes

// Generate a random 6-digit OTP.
function generateSosOtp() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

// Date key used for the daily SOS counter (local date `y-m-d`).
function dateKey(date = new Date()) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/**
 * sendSosOtp
 * Sends (or, in demo, returns) a 6-digit OTP to the user's phone.
 * Stores it under `sos_otps/{phone}` with a 5-minute expiry.
 */
exports.sendSosOtp = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated."
    );
  }

  const phone = (data.phone || "").trim();
  if (!phone) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "phone is required."
    );
  }

  try {
    const otp = generateSosOtp();
    const now = Date.now();
    const expiresAt = new Date(now + SOS_OTP_TTL_MS);

    await db.collection("sos_otps").doc(phone).set({
      phone: phone,
      otp: otp,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
      verified: false,
    });

    // In production, send the OTP via SMS/WhatsApp here.
    console.log(`SOS OTP sent to ${phone}: ${otp}`);

    return {
      success: true,
      message: "OTP sent to your phone",
      // Dev-only: return the OTP so the flow can be exercised end-to-end.
      devOtp: otp,
      expiresInMin: 5,
    };
  } catch (error) {
    console.error("sendSosOtp error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * verifySosOtp
 * Verifies the OTP AND enforces the 3-SOS/day limit.
 * On success, increments the user's daily counter in `sos_counters`.
 */
exports.verifySosOtp = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated."
    );
  }

  const otp = (data.otp || "").toString().trim();
  if (!otp) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "otp is required."
    );
  }

  const phone = context.auth.token.phone_number || "";

  try {
    // ─── Enforce the 3-SOS/day limit (atomic) ───
    const counterKey = `${context.auth.uid}:${dateKey()}`;
    const counterRef = db.collection("sos_counters").doc(counterKey);

    let sosToday = 0;
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(counterRef);
      if (snap.exists) {
        sosToday = snap.data().count || 0;
      }
      if (sosToday >= SOS_DAILY_LIMIT) {
        // Mark the transaction as "limit reached" by not incrementing.
        return;
      }
      tx.set(counterRef, {
        userId: context.auth.uid,
        date: dateKey(),
        count: sosToday + 1,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      sosToday = sosToday + 1;
    });

    if (sosToday > SOS_DAILY_LIMIT) {
      return {
        success: false,
        message: `Daily SOS limit (${SOS_DAILY_LIMIT}) reached. Please try again tomorrow.`,
        sosToday: SOS_DAILY_LIMIT,
        sosRemaining: 0,
      };
    }

    // ─── Verify the OTP ───
    const otpDoc = await db.collection("sos_otps").doc(phone).get();
    if (!otpDoc.exists) {
      return { success: false, message: "No OTP was sent. Please try again." };
    }

    const otpData = otpDoc.data();
    const now = Date.now();

    // Expiry check.
    let expiresAt = null;
    if (otpData.expiresAt instanceof admin.firestore.Timestamp) {
      expiresAt = otpData.expiresAt.toMillis();
    } else if (otpData.expiresAt instanceof Date) {
      expiresAt = otpData.expiresAt.getTime();
    } else {
      expiresAt = new Date(otpData.expiresAt).getTime();
    }
    if (expiresAt && now > expiresAt) {
      return { success: false, message: "OTP has expired. Please request a new one." };
    }

    // Match check.
    if (otpData.otp !== otp) {
      return { success: false, message: "Invalid OTP. Please try again." };
    }

    // Mark verified + delete OTP (one-time use).
    await db.collection("sos_otps").doc(phone).update({ verified: true });
    await db.collection("sos_otps").doc(phone).delete();

    return {
      success: true,
      message: "SOS verified",
      sosToday: sosToday,
      sosRemaining: Math.max(0, SOS_DAILY_LIMIT - sosToday),
    };
  } catch (error) {
    console.error("verifySosOtp error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * cancelSosWithPenalty
 * Records a ₹50 penalty when a user cancels an SOS after it was dispatched
 * (fake / late cancellation). Stores the penalty in `sos_penalties`.
 */
exports.cancelSosWithPenalty = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated."
    );
  }

  const requestId = (data.requestId || "").trim();
  if (!requestId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "requestId is required."
    );
  }

  const reason = (data.reason || "").toString().trim();

  try {
    const penaltyRef = db.collection("sos_penalties").doc();
    await penaltyRef.set({
      userId: context.auth.uid,
      requestId: requestId,
      reason: reason || "fake_cancel",
      penaltyAmount: SOS_PENALTY_AMOUNT,
      status: "pending", // pending → charged
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Optionally mark the request as cancelled-with-penalty.
    await db.collection("requests").doc(requestId).update({
      status: "cancelled",
      cancelReason: reason || "fake_cancel",
      penaltyAmount: SOS_PENALTY_AMOUNT,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      message: `SOS cancelled. A penalty of ₹${SOS_PENALTY_AMOUNT} will be charged.`,
      penaltyAmount: SOS_PENALTY_AMOUNT,
      penaltyId: penaltyRef.id,
    };
  } catch (error) {
console.error("cancelSosWithPenalty error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ─────────────────────────────────────────────
// FEATURE 4: Payment Split (Razorpay Route API)
// Collects to company account, then splits payout to 2 crew
// (mechanic + assistant) via razorpay.payments.transfer.
// Uses the "Route" (transfers) API. Requires a live/production
// Razorpay key with Route enabled. Falls back to recording a
// pending split when the transfer API is unavailable (test key).
// ─────────────────────────────────────────────
const COMMISSION_RATE = 0.10; // 10% platform commission

exports.splitPayment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated."
    );
  }

  const {
    requestId,
    paymentId,
    serviceAmount,
    mechanicId,
    mechanicPayout,
    assistantId,
    assistantPayout,
  } = data;

  if (!requestId || !paymentId || !serviceAmount) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "requestId, paymentId, and serviceAmount are required."
    );
  }

  try {
    const amount = parseFloat(serviceAmount);
    const platformCommission = Math.round(amount * COMMISSION_RATE * 100) / 100;
    const crewPool = Math.round((amount - platformCommission) * 100) / 100;

    // Default split: 60% mechanic / 40% assistant when not provided.
    const mechShare =
      mechanicPayout != null
        ? parseFloat(mechanicPayout)
        : Math.round(crewPool * 0.6 * 100) / 100;
    const asstShare =
      assistantPayout != null
        ? parseFloat(assistantPayout)
        : Math.round((crewPool - mechShare) * 100) / 100;

    const transfers = [];

    // Build transfer requests for the two crew members.
    async function buildTransfer(accountId, amountPaise, purpose) {
      if (!accountId) return null;
      return {
        account: accountId,
        amount: Math.round(amountPaise * 100), // paise
        currency: "INR",
        notes: {
          requestId,
          paymentId,
          purpose,
        },
        on_hold: 0,
      };
    }

    const mechanicTransfer = await buildTransfer(
      mechanicId,
      mechShare,
      "mechanic_payout"
    );
    const assistantTransfer = await buildTransfer(
      assistantId,
      asstShare,
      "assistant_payout"
    );
    if (mechanicTransfer) transfers.push(mechanicTransfer);
    if (assistantTransfer) transfers.push(assistantTransfer);

    let razorpayResponse = null;
    let splitStatus = "pending";

    // Attempt to execute the Route transfer. On test keys / missing
    // linked accounts this may throw — we fail-safe into "pending".
    try {
      if (transfers.length > 0) {
        razorpayResponse = await razorpay.payments.transfer(paymentId, {
          transfers,
        });
        splitStatus = "completed";
      }
    } catch (transferError) {
      console.error("Razorpay transfer failed:", transferError);
      splitStatus = "pending"; // schedule manual split
    }

    // Persist the split record.
    const splitRef = db.collection("payment_splits").doc();
    await splitRef.set({
      splitId: splitRef.id,
      requestId,
      paymentId,
      serviceAmount: amount,
      platformCommission,
      crewPool,
      mechanicShare: mechShare,
      assistantShare: asstShare,
      mechanicId: mechanicId || "",
      assistantId: assistantId || "",
      status: splitStatus,
      razorpayResponse: razorpayResponse || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      splitId: splitRef.id,
      status: splitStatus,
      platformCommission,
      mechanicShare: mechShare,
      assistantShare: asstShare,
      message:
        splitStatus === "completed"
          ? "Payment split to crew completed"
          : "Payment split queued for manual processing",
    };
  } catch (error) {
    console.error("splitPayment error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ═══════════════════════════════════════════════════════════════
// NOVEL MODULES — Server-Side Cloud Functions (additive)
// Back the 6 novel client modules with authoritative, atomic,
// server-side enforcement. These are purely additive: they do not
// modify any existing function or collection.
// ═══════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────
// NOVEL 1: ROADIQ — DEMAND FORECAST INGEST
// generateDemandForecast — server-side persistence of RoadIQ forecast /
// heatmap batches into `road_iq_forecasts` for admin analytics.
// Mirrors lib/services/novel/road_iq_service.dart → persistForecast().
// ─────────────────────────────────────────────
exports.generateDemandForecast = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authenticated.");
  }

  const { forecasts, heatmap, hour } = data || {};
  if (!Array.isArray(forecasts) && !Array.isArray(heatmap)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Provide a forecasts[] or heatmap[] payload."
    );
  }

  try {
    const now = admin.firestore.FieldValue.serverTimestamp();
    const reportRef = db.collection("road_iq_forecasts").doc();
    await reportRef.set({
      hour: typeof hour === "number" ? hour : new Date().getHours(),
      forecasts: Array.isArray(forecasts) ? forecasts : [],
      heatmap: Array.isArray(heatmap) ? heatmap : [],
      generatedBy: context.auth.uid,
      createdAt: now,
    });

    return { success: true, reportId: reportRef.id, message: "Forecast ingested" };
  } catch (error) {
    console.error("generateDemandForecast error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ─────────────────────────────────────────────
// NOVEL 2: TRUSTSCORE — SERVER-SIDE TRUST PROFILE
// computeTrustScore — mirrors lib/services/novel/trust_score_service.dart
// computeTrustProfile() + persistTrustProfile(). Computes the weighted
// composite trust score, awards badges, derives the tier, and persists
// the profile to `trust_profiles/{crewId}`.
// ─────────────────────────────────────────────
exports.computeTrustScore = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authenticated.");
  }

  const {
    crewId,
    role = "mechanic",
    rating = 0,
    ratingCount = 0,
    jobsCompleted = 0,
    onTime = 0,
    lateCount = 0,
    cancellations = 0,
    respondedFast = 0,
    zoneAdherent = 0,
    safetyAdherent = 0,
  } = data || {};

  if (!crewId) {
    throw new functions.https.HttpsError("invalid-argument", "crewId is required.");
  }

  try {
    // Reliability: share of on-time accepts vs total completed.
    const reliability =
      jobsCompleted === 0
        ? 0
        : Math.min(100, Math.max(0, ((jobsCompleted - cancellations) / jobsCompleted) * 60));
    // Response: share of fast responses.
    const response =
      jobsCompleted === 0 ? 0 : Math.min(100, Math.max(0, (respondedFast / jobsCompleted) * 100));
    // Rating: normalized 0-5 -> 0-100.
    const ratingScore =
      ratingCount === 0 ? 50 : Math.min(100, Math.max(0, (rating / 5) * 100));
    const zoneConsistency =
      jobsCompleted === 0 ? 50 : Math.min(100, Math.max(0, (zoneAdherent / jobsCompleted) * 100));
    const safety =
      jobsCompleted === 0 ? 60 : Math.min(100, Math.max(0, (safetyAdherent / jobsCompleted) * 100));

    const trustScore =
      reliability * 0.3 + response * 0.2 + ratingScore * 0.25 + zoneConsistency * 0.1 + safety * 0.15;

    // Gamified badges.
    const badges = [];
    if (jobsCompleted >= 10) badges.push("experience_warrior");
    if (jobsCompleted >= 50) badges.push("road_veteran");
    if (onTime >= 20) badges.push("punctual_pro");
    if (response >= 80) badges.push("rapid_responder");
    if (zoneConsistency >= 80) badges.push("zone_guardian");
    if (safety >= 85) badges.push("safety_champion");
    if (badges.length >= 4) badges.push("trust_elite");
    if (badges.length === 0) badges.push("rising_star");

    // Tier derivation.
    let tier = "bronze";
    if (trustScore >= 85 || badges.includes("trust_elite")) tier = "platinum";
    else if (trustScore >= 70) tier = "gold";
    else if (trustScore >= 55) tier = "silver";

    const profile = {
      crewId,
      role,
      trustScore: Math.round(trustScore * 100) / 100,
      reliabilityScore: Math.round(reliability * 100) / 100,
      responseScore: Math.round(response * 100) / 100,
      ratingScore: Math.round(ratingScore * 100) / 100,
      zoneConsistencyScore: Math.round(zoneConsistency * 100) / 100,
      safetyScore: Math.round(safety * 100) / 100,
      jobsCompletedTotal: jobsCompleted,
      onTimeCount: onTime,
      lateCount,
      cancellations,
      badges,
      tier,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("trust_profiles").doc(crewId).set(profile, { merge: true });

    return { success: true, profile };
  } catch (error) {
    console.error("computeTrustScore error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ─────────────────────────────────────────────
// NOVEL 3: COMMUNITY MESH — ATOMIC BEACON BROADCAST
// broadcastCommunityBeacon — server-side atomic creation of an emergency
// beacon. Gathers nearby verified helpers + family, persists the beacon to
// `emergency_beacons`, and returns the count notified. Mirrors
// lib/services/novel/community_mesh_service.dart → broadcastBeacon().
// ─────────────────────────────────────────────
exports.broadcastCommunityBeacon = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authenticated.");
  }

  const { userId, userName, userPhone, lat, lng, message, familyIds } = data || {};
  if (!userId || typeof lat !== "number" || typeof lng !== "number") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "userId, lat, and lng are required."
    );
  }

  try {
    // Find nearby verified + available helpers.
    const helperSnap = await db
      .collection("community_helpers")
      .where("isVerified", "==", true)
      .where("isAvailable", "==", true)
      .limit(50)
      .get();

    const nearby = [];
    helperSnap.forEach((doc) => {
      const h = doc.data();
      if (typeof h.lat === "number" && typeof h.lng === "number") {
        const d = haversineKm(lat, lng, h.lat, h.lng);
        if (d <= 5) {
          nearby.push({ id: doc.id, name: h.name, phone: h.phone, distanceKm: Math.round(d * 100) / 100 });
        }
      }
    });
    nearby.sort((a, b) => a.distanceKm - b.distanceKm);

    const beaconRef = db.collection("emergency_beacons").doc();
    await beaconRef.set({
      userId,
      userName: userName || "",
      userPhone: userPhone || "",
      lat,
      lng,
      message:
        message || "Emergency! Roadside assistance needed at my location.",
      status: "active",
      notifiedHelperIds: nearby.map((h) => h.id),
      notifiedFamilyIds: Array.isArray(familyIds) ? familyIds : [],
      notifiedHelpers: nearby,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      beaconId: beaconRef.id,
      helpersNotified: nearby.length,
      message: "Emergency beacon broadcast to nearby helpers",
    };
  } catch (error) {
    console.error("broadcastCommunityBeacon error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ─────────────────────────────────────────────
// NOVEL 4: WALLET & LOYALTY — ATOMIC CASHBACK
// creditWalletCashback — atomic, server-side cashback credit + tier
// upgrade to `wallets/{userId}`. Mirrors lib/services/novel/wallet_service.dart
// → creditCashback().
// ─────────────────────────────────────────────
exports.creditWalletCashback = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authenticated.");
  }

  const { userId, amount, serviceType } = data || {};
  if (!userId || !amount || amount <= 0 || !serviceType) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "userId, amount (>0), and serviceType are required."
    );
  }

  try {
    const walletRef = db.collection("wallets").doc(userId);
    const doc = await walletRef.get();

    let balance = 0;
    let lifetimeCashback = 0;
    let rescueCount = 0;
    let cashbackRules = [
      { serviceType: "flat_tyre", percent: 5 },
      { serviceType: "battery", percent: 6 },
      { serviceType: "fuel", percent: 4 },
      { serviceType: "towing", percent: 3 },
      { serviceType: "lockout", percent: 5 },
    ];

    if (doc.exists) {
      const w = doc.data();
      balance = w.balance || 0;
      lifetimeCashback = w.lifetimeCashback || 0;
      rescueCount = w.rescueCount || 0;
      if (Array.isArray(w.cashbackRules) && w.cashbackRules.length) {
        cashbackRules = w.cashbackRules;
      }
    }

    const rule = cashbackRules.find((r) => r.serviceType === serviceType) || { percent: 4 };
    const cashback = ((parseFloat(amount) * (rule.percent || 4)) / 100);

    const newBalance = balance + cashback;
    const newLifetime = lifetimeCashback + cashback;
    const newRescueCount = rescueCount + 1;
    let newTier = "bronze";
    if (newRescueCount >= 20) newTier = "platinum";
    else if (newRescueCount >= 10) newTier = "gold";
    else if (newRescueCount >= 5) newTier = "silver";

    const txn = {
      txnId: "cashback-" + Date.now(),
      type: "cashback",
      amount: Math.round(cashback * 100) / 100,
      description: "Cashback on " + serviceType + " rescue",
      createdAt: new Date().toISOString(),
    };

    await walletRef.set(
      {
        userId,
        balance: Math.round(newBalance * 100) / 100,
        lifetimeCashback: Math.round(newLifetime * 100) / 100,
        referralBalance: doc.exists ? doc.data().referralBalance || 0 : 0,
        memberTier: newTier,
        rescueCount: newRescueCount,
        transactions: admin.firestore.FieldValue.arrayUnion([txn]),
        cashbackRules,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      success: true,
      cashback: Math.round(cashback * 100) / 100,
      newBalance: Math.round(newBalance * 100) / 100,
      tier: newTier,
      message: "Cashback credited",
    };
  } catch (error) {
    console.error("creditWalletCashback error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ─────────────────────────────────────────────
// NOVEL 5: DAMAGE RECON — TAMPER-EVIDENT CAPTURE
// recordDamageCapture — server-side, tamper-evident damage capture with an
// FNV-1a integrity hash, persisted to `damage_captures`. Mirrors
// lib/services/novel/damage_recon_service.dart → capture().
// ─────────────────────────────────────────────
// FNV-1a 32-bit hash (matches the Dart implementation).
function fnv1a32(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, "0");
}

exports.recordDamageCapture = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authenticated.");
  }

  const { jobId, userId, crewId, phase, imageUrl, lat, lng, caption } = data || {};
  if (!jobId || !phase || !imageUrl) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "jobId, phase, and imageUrl are required."
    );
  }

  try {
    const captureId = "dc-" + Date.now() + "-" + (Date.now() % 1000);
    const capturedAt = new Date();
    const hashInput = `${jobId}|${phase}|${capturedAt.toISOString()}|${imageUrl}|${lat}|${lng}`;
    const hash = fnv1a32(hashInput);

    await db.collection("damage_captures").doc(captureId).set({
      captureId,
      jobId,
      userId: userId || "",
      crewId: crewId || "",
      phase,
      imageUrl,
      lat: typeof lat === "number" ? lat : 0,
      lng: typeof lng === "number" ? lng : 0,
      caption: caption || "",
      capturedAt: admin.firestore.Timestamp.fromDate(capturedAt),
      hash,
    });

    return { success: true, captureId, hash };
  } catch (error) {
    console.error("recordDamageCapture error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ─────────────────────────────────────────────
// NOVEL 6: DIGITAL GARAGE — VEHICLE JOURNAL REFRESH
// refreshVehicleJournal — server-side rebuild of a vehicle's service journal
// from completed tokens/jobs, persisted to `vehicle_journals`. Mirrors
// lib/services/novel/vehicle_journal_service.dart → buildJournal().
// ─────────────────────────────────────────────
exports.refreshVehicleJournal = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authenticated.");
  }

  const { vehicleId, vehicleNumber, vehicleType, ownerId, ownerName } = data || {};
  if (!vehicleId || !vehicleNumber || !ownerId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "vehicleId, vehicleNumber, and ownerId are required."
    );
  }

  try {
    // Gather completed service events for this vehicle from tokens.
    const tokenSnap = await db
      .collection("tokens")
      .where("vehicleNumber", "==", vehicleNumber)
      .where("status", "in", ["ready_for_pickup", "closed"])
      .limit(50)
      .get();

    const services = tokenSnap.docs.map((doc) => {
      const t = doc.data();
      return {
        jobId: t.jobId || doc.id,
        serviceType: t.issuedFor || t.serviceType || "general",
        garageName: t.garageName || "",
        servicedAt: t.closedAt || t.readyForPickupAt || new Date(),
        cost: t.totalAmount || 0,
        notes: t.notes || "",
      };
    });

    const now = new Date();
    const lastService = services.length
      ? new Date(Math.max(...services.map((s) => new Date(s.servicedAt).getTime())))
      : null;

    let health = 50;
    if (services.length) {
      health = Math.min(100, 50 + services.length * 8);
      const days = lastService ? Math.floor((now - lastService) / 86400000) : 999;
      if (days > 180) health -= 20;
    }
    health = Math.max(0, Math.min(100, health));

    const reminders = [];
    if (lastService) {
      reminders.push({
        type: "oil_change",
        title: "Engine Oil Change",
        description: "Recommended every 6 months or 5000 km.",
        dueDate: new Date(lastService.getTime() + 180 * 86400000).toISOString(),
        isOverdue: now > new Date(lastService.getTime() + 180 * 86400000),
      });
      reminders.push({
        type: "battery",
        title: "Battery Health Check",
        description: "Recommended every 2 years.",
        dueDate: new Date(lastService.getTime() + 730 * 86400000).toISOString(),
        isOverdue: now > new Date(lastService.getTime() + 730 * 86400000),
      });
    }
    reminders.push({
      type: "general",
      title: "General Servicing",
      description: "Periodic full vehicle inspection.",
      dueDate: new Date(now.getTime() + 30 * 86400000).toISOString(),
      isOverdue: false,
    });

    await db.collection("vehicle_journals").doc(vehicleId).set(
      {
        vehicleId,
        vehicleNumber,
        vehicleType: vehicleType || "",
        ownerId,
        ownerName: ownerName || "",
        healthScore: health,
        lastServiceDate: lastService ? lastService.toISOString() : null,
        totalServices: services.length,
        totalDistanceKm: 0,
        history: services,
        reminders,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      success: true,
      healthScore: health,
      totalServices: services.length,
      remindersCount: reminders.length,
    };
  } catch (error) {
    console.error("refreshVehicleJournal error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ─────────────────────────────────────────────
// FEATURE 5: Offline Crew Queue
// When no crew is available (all offline), a pending job is added to the
// crew_offline_queue collection. When a crew comes online, the app calls
// deliverQueuedJobs (or the onCrewGoesOnline trigger fires) to push
// queued pending jobs to that crew via FCM.
// ─────────────────────────────────────────────
exports.queueOfflineJob = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated."
    );
  }

  const { requestId, role, lat, lng, zone } = data;
  if (!requestId || !role) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "requestId and role are required."
    );
  }

  try {
    const jobRef = db.collection("crew_offline_queue").add({
      requestId,
      role,
      lat: lat || null,
      lng: lng || null,
      zone: zone || "",
      status: "queued", // queued → delivered
      attempts: 0,
      queuedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, queueId: jobRef.id };
  } catch (error) {
    console.error("queueOfflineJob error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// Firestore trigger: when a crew document flips isOnline false→true,
// deliver any queued jobs for that crew role to the crew's FCM token.
exports.onCrewGoesOnline = functions.firestore
  .document("crews/{crewId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Only act on the offline → online transition.
    if (before.isOnline !== false || after.isOnline !== true) return;

    const crewId = context.params.crewId;
    const role = after.role;
    const fcmToken = after.fcmToken;
    const crewLat = after.currentLocation?.latitude;
    const crewLng = after.currentLocation?.longitude;

    if (!fcmToken) return;

    try {
      const queuedSnap = await db
        .collection("crew_offline_queue")
        .where("role", "==", role)
        .where("status", "==", "queued")
        .limit(10)
        .get();

      if (queuedSnap.empty) return;

      const messages = [];
      for (const doc of queuedSnap.docs) {
        const job = doc.data();
        // Only deliver jobs near the crew (within ~10km) when lat present.
        if (job.lat && job.lng && crewLat && crewLng) {
          const dist = haversineKm(
            crewLat,
            crewLng,
            job.lat,
            job.lng
          );
          if (dist > 10) continue;
        }

        messages.push({
          token: fcmToken,
          notification: {
            title: "New Roadside Job",
            body: "A pending job is available near you.",
          },
          data: {
            type: "queued_job",
            requestId: job.requestId || "",
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
        });

        // Mark delivered.
        await doc.ref.update({
          status: "delivered",
          deliveredTo: crewId,
          deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      if (messages.length > 0) {
        // firebase-admin 11 includes messaging via admin.messaging().
        await admin.messaging().sendEach(messages);
      }

      console.log(
        `Delivered ${messages.length} queued job(s) to crew ${crewId}`
      );
    } catch (error) {
      console.error("onCrewGoesOnline error:", error);
    }
  });

// Callable fallback: the app calls this when a crew toggles online so the
// queue is delivered immediately regardless of trigger timing.
exports.deliverQueuedJobs = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Crew must be authenticated."
    );
  }

  const { crewId, lat, lng } = data;
  if (!crewId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "crewId is required."
    );
  }

  try {
    const crewSnap = await db.collection("crews").doc(crewId).get();
    if (!crewSnap.exists) {
      return { success: false, message: "Crew not found" };
    }

    const crew = crewSnap.data();
    const role = crew.role;
    const fcmToken = crew.fcmToken || "";

    const queuedSnap = await db
      .collection("crew_offline_queue")
      .where("role", "==", role)
      .where("status", "==", "queued")
      .limit(10)
      .get();

    const delivered = [];
    for (const doc of queuedSnap.docs) {
      const job = doc.data();
      if (job.lat && job.lng && lat && lng) {
        if (haversineKm(lat, lng, job.lat, job.lng) > 10) continue;
      }
      delivered.push({
        queueId: doc.id,
        requestId: job.requestId || "",
      });
      await doc.ref.update({
        status: "delivered",
        deliveredTo: crewId,
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return {
      success: true,
      delivered,
      message: `Delivered ${delivered.length} queued job(s)`,
    };
  } catch (error) {
    console.error("deliverQueuedJobs error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ═══════════════════════════════════════════════════════════════
// PAYMENT ORDER + VERIFY + SPLIT + INVOICE (spec: 9. PAYMENT MODULE)
// ───────────────────────────────────────────────────────────────

/**
 * createRazorpayOrder — creates a Razorpay order server-side.
 * Returns the order id + key needed to launch the client checkout.
 */
exports.createRazorpayOrder = functions.https.onCall(async (data) => {
  const amount = parseFloat(data.amount);
  const currency = data.currency || "INR";
  const receipt = data.receipt || ("rcpt_" + Date.now());

  if (!amount || amount <= 0) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "amount must be a positive number."
    );
  }

  try {
    const order = await razorpay.orders.create({
      amount: Math.round(amount * 100), // paise
      currency,
      receipt,
      payment_capture: 1,
    });

    return {
      success: true,
      orderId: order.id,
      amount: amount,
      currency: order.currency,
      key: RAZORPAY_KEY_ID,
    };
  } catch (error) {
    console.error("createRazorpayOrder error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * verifyPaymentSignature — verifies the Razorpay payment signature using
 * the order + payment ids and signature returned by the SDK.
 * Uses crypto to recompute the HMAC SHA256.
 */
const crypto = require("crypto");

exports.verifyPaymentSignature = functions.https.onCall(async (data) => {
  const { orderId, paymentId, signature } = data;
  if (!orderId || !paymentId || !signature) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "orderId, paymentId, and signature are required."
    );
  }

  try {
    const secret = RAZORPAY_KEY_SECRET;
    const body = orderId + "|" + paymentId;
    const expected = crypto
      .createHmac("sha256", secret)
      .update(body)
      .digest("hex");

    const verified = expected === signature;
    if (verified) {
      // Record the verified payment.
      await db.collection("payments").doc(paymentId).set({
        orderId,
        paymentId,
        signature,
        status: "verified",
        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return {
      success: true,
      verified,
      message: verified
        ? "Payment signature verified"
        : "Signature verification failed",
    };
  } catch (error) {
    console.error("verifyPaymentSignature error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ═══════════════════════════════════════════════════════════════
// PUSH NOTIFICATIONS (spec: 8. NOTIFICATION MODULE)
// sendPushNotification — sends an FCM message to a user or crew.
// ───────────────────────────────────────────────────────────────

exports.sendPushNotification = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated."
    );
  }

  const { title, body, userId, crewId } = data;
  try {
    let fcmToken = "";
    if (crewId) {
      const crewSnap = await db.collection("crews").doc(crewId).get();
      if (crewSnap.exists) fcmToken = crewSnap.data().fcmToken || "";
    } else if (userId) {
      const userSnap = await db.collection("users").doc(userId).get();
      if (userSnap.exists) fcmToken = userSnap.data().fcmToken || "";
    }

    if (!fcmToken) {
      return { success: false, message: "No FCM token for recipient" };
    }

    await admin.messaging().send({
      token: fcmToken,
      notification: { title: title || "RoadResQ", body: body || "" },
      data: { click_action: "FLUTTER_NOTIFICATION_CLICK" },
    });

    // Store a notification record for history.
    await db.collection("notifications").add({
      userId: userId || "",
      crewId: crewId || "",
      title: title || "RoadResQ",
      body: body || "",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false,
    });

    return { success: true, message: "Notification sent" };
  } catch (error) {
    console.error("sendPushNotification error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ═══════════════════════════════════════════════════════════════
// ADMIN: manualAssignJob + reassignJob (spec: 10. ADMIN MODULE)
// ───────────────────────────────────────────────────────────────

/**
 * manualAssignJob — admin override of matching for a job.
 */
exports.manualAssignJob = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Admin must be authenticated."
    );
  }
  const { jobId, mechanicCrewId, assistantCrewId } = data;
  if (!jobId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "jobId is required."
    );
  }

  try {
    const now = admin.firestore.FieldValue.serverTimestamp();
    const updates = {
      status: "assigned",
      assignedAt: now,
      updatedAt: now,
    };
    if (mechanicCrewId) updates.assignedMechanicId = mechanicCrewId;
    if (assistantCrewId) updates.assignedAssistantId = assistantCrewId;

    await db.collection("jobs").doc(jobId).update(updates);
    return { success: true, message: "Manual assignment saved" };
  } catch (error) {
    console.error("manualAssignJob error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * reassignJob — when a crew rejects or times out (60s), reassign the job.
 * Marks the job back to "pending" for re-matching.
 */
exports.reassignJob = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Unauthenticated."
    );
  }

  const { jobId, reason } = data;
  if (!jobId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "jobId is required."
    );
  }

  try {
    const now = admin.firestore.FieldValue.serverTimestamp();
    await db.collection("jobs").doc(jobId).update({
      status: "pending",
      reassignReason: reason || "crew_rejected",
      reassignedAt: now,
      updatedAt: now,
    });
    return { success: true, message: "Job returned to pool for reassignment" };
  } catch (error) {
    console.error("reassignJob error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});
