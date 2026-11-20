/// RoadResQ Application Constants
/// Centralized configuration - no hardcoded values in business logic.
class AppConstants {
  AppConstants._();

  // ────────────────────────────────
  // App Info
  // ────────────────────────────────
  static const String appName = 'RoadResQ';
  static const String appVersion = '2.0.0';
  static const String companyName = 'RoadResQ Technologies Pvt Ltd';
  static const String supportEmail = 'support@roadresq.com';
  static const String supportPhone = '+919876543210';

  // ────────────────────────────────
  // Dispatch Algorithm Weights
  // ────────────────────────────────
  static const double weightDistance = 0.40;
  static const double weightRating = 0.25;
  static const double weightActiveStatus = 0.20;
  static const double weightZone = 0.15;

  // ────────────────────────────────
  // Matching
  // ────────────────────────────────
  /// 2-Man matching radius — find 1 mechanic + 1 assistant within 10km.
  static const double maxCrewRadiusKm = 10.0;
  static const int maxBackupCrews = 3;
  static const int sosTimeoutSeconds = 300; // 5 minutes
  static const int locationUpdateIntervalMs = 2000; // 2s for night mode
  static const int normalLocationIntervalMs = 5000; // 5s for day mode

  // ────────────────────────────────
  // Token System
  // ────────────────────────────────
  static const int tokenLength = 6;
  static const String tokenChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  // ────────────────────────────────
  // Zone Security
  // ────────────────────────────────
  static const int nightStartHour = 22; // 10 PM
  static const int nightEndHour = 6; // 6 AM
  static const int ruralTrackingIntervalSec = 120; // 2 mins

  // ────────────────────────────────
  // Payment
  // ────────────────────────────────
  static const double platformCommissionPercent = 10.0;
  static const double gstPercent = 18.0;
  static const String razorpayTestKey = 'rzp_test_SbTmM0x0VYHxcN';

  // ────────────────────────────────
  // Firestore Collections
  // ────────────────────────────────
  static const String collectionUsers = 'users';
  static const String collectionCrews = 'crews';
  static const String collectionRequests = 'requests';
  static const String collectionJobs = 'jobs';
  static const String collectionTokens = 'tokens';
  static const String collectionZones = 'zones';
  static const String collectionGarages = 'garages';
  static const String collectionDisputes = 'disputes';
  static const String collectionAnalytics = 'analytics';
  static const String collectionNotifications = 'notifications';

  // ────────────────────────────────
  // Storage Paths
  // ────────────────────────────────
  static const String storageKycDocs = 'kyc_documents';
  static const String storageVehiclePhotos = 'vehicle_photos';
  static const String storageIssuePhotos = 'issue_photos';
  static const String storageProfilePics = 'profile_pictures';

  // ────────────────────────────────
  // Chennai Default Bounds
  // ────────────────────────────────
  static const double chennaiLat = 13.0827;
  static const double chennaiLng = 80.2707;
  static const double defaultZoom = 12.0;

  // ────────────────────────────────
  // Secure Storage Keys
  // ────────────────────────────────
  static const String keyAuthToken = 'auth_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUserId = 'user_id';
  static const String keyUserRole = 'user_role';
  static const String keyCrewId = 'crew_id';
  static const String keyOnboarded = 'onboarded';
}
