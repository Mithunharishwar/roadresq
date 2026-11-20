/**
 * RoadResQ Zone Seed Script (FEATURE 3)
 * Seeds the Firestore `zones` collection with Chennai urban + rural zones.
 * Each zone uses bounding-box geometry (latMin/latMax/lngMin/lngMax) that the
 * `checkZoneSecurity` Cloud Function uses for real point-in-bounds containment.
 *
 * Run with firebase-admin from the functions directory:
 *   node seedZones.js
 */

const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

const zones = [
  // ─── URBAN (Chennai core) ───
  {
    name: "Chennai Central",
    type: "urban",
    securityLevel: "low",
    latMin: 13.05,
    latMax: 13.12,
    lngMin: 80.22,
    lngMax: 80.30,
    requiresPhotoVerification: false,
    requiresEmergencySms: false,
    verificationCount: 1,
  },
  {
    name: "Anna Nagar",
    type: "urban",
    securityLevel: "low",
    latMin: 13.06,
    latMax: 13.10,
    lngMin: 80.18,
    lngMax: 80.24,
    requiresPhotoVerification: false,
    requiresEmergencySms: false,
    verificationCount: 1,
  },
  {
    name: "OMR Corridor",
    type: "urban",
    securityLevel: "medium",
    latMin: 12.90,
    latMax: 13.05,
    lngMin: 80.19,
    lngMax: 80.32,
    requiresPhotoVerification: false,
    requiresEmergencySms: false,
    verificationCount: 1,
  },

  // ─── RURAL (outskirts / low-density) ───
  {
    name: "Rural North (Red Hills)",
    type: "rural",
    securityLevel: "high",
    latMin: 13.12,
    latMax: 13.30,
    lngMin: 80.10,
    lngMax: 80.25,
    requiresPhotoVerification: true,
    requiresEmergencySms: true,
    verificationCount: 2,
  },
  {
    name: "Rural West (Poonamallee/Poonamallee)",
    type: "rural",
    securityLevel: "high",
    latMin: 13.02,
    latMax: 13.15,
    lngMin: 80.00,
    lngMax: 80.12,
    requiresPhotoVerification: true,
    requiresEmergencySms: true,
    verificationCount: 2,
  },
  {
    name: "Rural South (Maraimalai Nagar)",
    type: "rural",
    securityLevel: "high",
    latMin: 12.70,
    latMax: 12.90,
    lngMin: 80.00,
    lngMax: 80.18,
    requiresPhotoVerification: true,
    requiresEmergencySms: true,
    verificationCount: 2,
  },
];

async function seed() {
  const batch = db.batch();
  const existing = await db.collection("zones").get();

  // Clear existing zones (idempotent re-seed).
  existing.forEach((doc) => {
    batch.delete(doc.ref);
  });

  zones.forEach((z) => {
    const ref = db.collection("zones").doc();
    batch.set(ref, {
      ...z,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  await batch.commit();
  console.log(`Seeded ${zones.length} zones (urban + rural).`);
  process.exit(0);
}

seed().catch((err) => {
  console.error("Seed failed:", err);
  process.exit(1);
});
