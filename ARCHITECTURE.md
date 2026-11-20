# RoadResQ Architecture — Production-Ready, Patentable Platform

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App (Cross-Platform)          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Presentation Layer (Views)                       │   │
│  │  - User App (Screens)                             │   │
│  │  - Crew App (Mechanic + Assistant)                │   │
│  │  - Admin Web Panel                               │   │
│  └──────────────────────┬───────────────────────────┘   │
│  ┌──────────────────────┴───────────────────────────┐   │
│  │  State Management (Riverpod Providers)           │   │
│  └──────────────────────┬───────────────────────────┘   │
│  ┌──────────────────────┴───────────────────────────┐   │
│  │  Service Layer                                    │   │
│  │  Auth | Firestore | Location | Payment | Token    │   │
│  └──────────────────────┬───────────────────────────┘   │
│  ┌──────────────────────┴───────────────────────────┐   │
│  │  Data Layer (Models)                              │   │
│  └──────────────────────────────────────────────────┘   │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────┐
│                   Firebase Backend                       │
│  ┌──────────┬──────────┬───────────┬────────────────┐   │
│  │ Firebase │ Firestore│ Cloud     │ Cloud Storage  │   │
│  │ Auth     │  (NoSQL) │ Functions │  (Images/Docs) │   │
│  └──────────┴──────────┴───────────┴────────────────┘   │
│  ┌──────────────────────────────────────────────────┐   │
│  │  FCM (Push Notifications)                        │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## Core Novelty Modules (Patentable)

### 1. 2-Man Crew Dispatch System
- Patent Point: Simultaneous dispatch of 2 separate profiles (Mechanic + Assistant) for a single SOS request
- Matching Algorithm: Distance + Rating + Active Status + Zone weight matrix
- Assistant handles "Customer Pickup" (like Rapido), Mechanic handles "Vehicle Service"

### 2. Digital Vehicle Token System  
- Patent Point: 6-digit alphanumeric token + QR code linking User, Crew, Garage, Vehicle
- Token lifecycle: generated → handed_to_garage → repair_started → ready_for_pickup → closed
- All 3 parties (User, Crew, Garage) track status in real-time

### 3. Zone-Based Security Logic
- Patent Point: Dynamic security rules based on Urban/Rural geofencing
- Urban: 1 verification + OTP. Rural: 2 verifications + Live Photo + Emergency SMS
- Night mode (10PM-6AM): Force location share every 2 minutes

## Tech Stack
- **Frontend**: Flutter 3.x, Material 3, Riverpod 2.x
- **Backend**: Firebase Auth, Firestore, Cloud Functions (Node.js), Cloud Storage, FCM
- **Maps**: google_maps_flutter, Geolocator, Geocoding
- **Payment**: Razorpay Flutter SDK
- **Other**: dio, flutter_secure_storage, intl, uuid, qr_flutter, mobile_scanner

## Folder Structure
```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── constants/
│   ├── theme/
│   ├── utils/
│   └── widgets/
├── models/
│   ├── user_model.dart
│   ├── crew_model.dart
│   ├── request_model.dart
│   ├── job_model.dart
│   ├── token_model.dart
│   └── zone_model.dart
├── services/
│   ├── auth_service.dart
│   ├── firestore_service.dart
│   ├── location_service.dart
│   ├── dispatch_service.dart
│   ├── token_service.dart
│   ├── zone_service.dart
│   ├── payment_service.dart
│   ├── notification_service.dart
│   └── storage_service.dart
├── providers/
│   ├── auth_provider.dart
│   ├── location_provider.dart
│   ├── request_provider.dart
│   ├── dispatch_provider.dart
│   ├── token_provider.dart
│   ├── job_provider.dart
│   └── payment_provider.dart
├── views/
│   ├── user/
│   ├── crew/
│   └── admin/
└── routes/
    └── app_router.dart
```

## Firestore Indexes Required
- `requests` collection: `status` + `timestamp` DESC
- `crews` collection: `isOnline` + `role` + `currentLocation`
- `jobs` collection: `crewId` + `status` + `timestamp`
- `tokens` collection: `tokenCode` + `status`
