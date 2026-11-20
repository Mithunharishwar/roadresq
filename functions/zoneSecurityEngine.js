/**
 * RoadResQ Zone Security Engine
 * Monitors incoming requests for rural-zone activity during high-risk hours (20:00–06:00)
 * and creates security alerts + triggers emergency SMS for enhanced safety.
 *
 * FEATURE 3 IMPROVEMENTS:
 * - Real bounding-box containment (not blanket "any rural zone" flag).
 * - Zone polygons stored in Firestore `zones` collection (type == 'rural').
 * - Triggers `sendEmergencySms` (records an SMS queue entry) for rural-night risk.
 * - Uses IST (UTC+5:30) high-risk window matching AppConstants (22→8pm-6am).
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

// NOTE: admin is initialized in index.js (the entrypoint). This engine is
// required by index.js and must NOT call admin.initializeApp() again to avoid
// the "The default Firebase app already exists" error.
const db = admin.firestore();

/**
 * Check if a given hour (0–23) falls within the high-risk window (20:00–06:00).
 * Task spec: 8pm-6am. AppConstants nightStartHour=22, but task says 8pm-6am,
 * so we enforce hour >= 20 || hour < 6.
 */
function isHighRiskHour(hour) {
  return hour >= 20 || hour < 6;
}

/**
 * Point-in-bounding-box containment.
 * A zone is defined by latMin/latMax/lngMin/lngMax (or a boundary array).
 * If the zone only has a `boundary` polygon array [[lat,lng],...], we fall
 * back to its bounding box (min/max of the polygon vertices).
 */
function pointInZoneBounds(zone, lat, lng) {
  let latMin, latMax, lngMin, lngMax;

  if (
    zone.latMin != null &&
    zone.latMax != null &&
    zone.lngMin != null &&
    zone.lngMax != null
  ) {
    latMin = zone.latMin;
    latMax = zone.latMax;
    lngMin = zone.lngMin;
    lngMax = zone.lngMax;
  } else if (Array.isArray(zone.boundary) && zone.boundary.length >= 3) {
    latMin = Math.min(...zone.boundary.map((p) => p[0]));
    latMax = Math.max(...zone.boundary.map((p) => p[0]));
    lngMin = Math.min(...zone.boundary.map((p) => p[1]));
    lngMax = Math.max(...zone.boundary.map((p) => p[1]));
  } else {
    // No geometry — cannot evaluate containment.
    return null;
  }

  return lat >= latMin && lat <= latMax && lng >= lngMin && lng <= lngMax;
}

/**
 * checkZoneSecurity
 * Firestore trigger — runs when a new request is created in the 'requests' collection.
 * If the pickup location falls within a defined rural zone AND the current IST time
 * is within the high-risk night window, it:
 *   1. Creates a `security_alerts` document.
 *   2. Writes an `emergency_sms` queue entry (sendEmergencySms integration).
 */
exports.checkZoneSecurity = functions.firestore
  .document("requests/{requestId}")
  .onCreate(async (snap, context) => {
    const requestId = context.params.requestId;
    const requestData = snap.data();

    try {
      const pickupLocation = requestData.pickupLocation;

      if (!pickupLocation) {
        console.log(
          `Request ${requestId} has no pickupLocation — skipping zone check.`
        );
        return null;
      }

      // Extract user lat/lng from GeoPoint or {lat,lng} map.
      let userLat, userLng;

      if (
        pickupLocation.latitude !== undefined &&
        pickupLocation.longitude !== undefined
      ) {
        userLat =
          typeof pickupLocation.latitude === "function"
            ? pickupLocation.latitude()
            : pickupLocation.latitude;
        userLng =
          typeof pickupLocation.longitude === "function"
            ? pickupLocation.longitude()
            : pickupLocation.longitude;
      } else if (pickupLocation.lat !== undefined) {
        userLat = pickupLocation.lat;
        userLng = pickupLocation.lng;
      } else if (pickupLocation._lat !== undefined) {
        userLat = pickupLocation._lat;
        userLng = pickupLocation._long;
      } else {
        console.log(
          `Request ${requestId} pickupLocation format not recognised — skipping zone check.`
        );
        return null;
      }

      // Load all rural zones from Firestore.
      const ruralZonesSnapshot = await db
        .collection("zones")
        .where("type", "==", "rural")
        .get();

      if (ruralZonesSnapshot.empty) {
        console.log(
          `No rural zones defined in Firestore — skipping zone security check.`
        );
        return null;
      }

      // Real containment check: find the rural zone that contains the point.
      let matchedZone = null;
      ruralZonesSnapshot.forEach((doc) => {
        if (matchedZone) return;
        const zone = doc.data();
        const contains = pointInZoneBounds(zone, userLat, userLng);
        if (contains === true) {
          matchedZone = { id: doc.id, ...zone };
        }
      });

      if (!matchedZone) {
        console.log(
          `Request ${requestId} is not inside any rural zone — no alert needed.`
        );
        return null;
      }

      // Check the current server time (UTC) → convert to IST (UTC+5:30).
      const now = new Date();
      const istMs = now.getTime() + 5.5 * 60 * 60 * 1000;
      const istHour = new Date(istMs).getUTCHours();

      if (!isHighRiskHour(istHour)) {
        console.log(
          `Request ${requestId} is in rural zone "${matchedZone.name}" but current IST hour (${istHour}:00) is not in the high-risk window (20:00–06:00) — no alert.`
        );
        return null;
      }

      // ─── All conditions met → create security alert ───
      const userId =
        requestData.userId || requestData.user_id || "unknown";
      const userPhone =
        requestData.userPhone || requestData.user_phone || "";
      const location = {
        latitude: userLat,
        longitude: userLng,
      };
      const timestamp = admin.firestore.FieldValue.serverTimestamp();
      const message =
        `High-risk request detected: ${requestId} in rural zone "${matchedZone.name}" ` +
        `at ${location.latitude},${location.longitude} during late-night hours. ` +
        `Immediate attention advised.`;

      const alertRef = db.collection("security_alerts").doc();
      await alertRef.set({
        requestId: requestId,
        userId: userId,
        zoneId: matchedZone.id,
        zoneName: matchedZone.name,
        location: location,
        timestamp: timestamp,
        message: message,
        createdAt: timestamp,
        acknowledged: false,
      });

      // ─── FEATURE 3: Trigger emergency SMS queue entry ───
      // Writes to the `emergency_sms` collection that `sendEmergencySms`
      // would produce. A worker/gateway (Twilio etc.) picks these up.
      await db.collection("emergency_sms").add({
        userId: userId,
        userPhone: userPhone,
        crewName: requestData.crewName || "",
        crewPhone: requestData.crewPhone || "",
        requestId: requestId,
        zone: "rural",
        zoneName: matchedZone.name,
        message:
          `RoadResQ Alert: Emergency in rural zone "${matchedZone.name}" at night. ` +
          `Request ${requestId} requires immediate attention. Track: https://roadresq.app/track/${requestId}`,
        sentAt: timestamp,
        isSent: false, // Set to true after actual SMS send
        autoTriggered: true,
      });

      console.log(
        `Security alert + SMS queued: ${alertRef.id} for request ${requestId} (rural zone "${matchedZone.name}")`
      );

      return {
        alertId: alertRef.id,
        requestId: requestId,
        zoneName: matchedZone.name,
      };
    } catch (error) {
      console.error("checkZoneSecurity error:", error);
      // Do not throw — firestore triggers that throw may retry indefinitely.
      return null;
    }
  });
