# 🚗 RoadResQ - On-Demand 2-Man Roadside Assistance Platform

**Patent-Protected Platform | Chennai, India**

RoadResQ is a production-ready, scalable, cross-platform Flutter application with Firebase backend that provides on-demand roadside assistance with a novel **2-Man Crew Dispatch System**, **Digital Vehicle Token System**, and **Zone-Based Security Logic**.

---

## 📋 Table of Contents

1. [System Architecture](#system-architecture)
2. [Core Patents](#core-patents)
3. [Tech Stack](#tech-stack)
4. [Project Structure](#project-structure)
5. [Setup Instructions](#setup-instructions)
6. [Firebase Configuration](#firebase-configuration)
7. [Cloud Functions](#cloud-functions)
8. [Firestore Schema](#firestore-schema)
9. [Security Rules](#security-rules)
10. [API Reference](#api-reference)
11. [Deployment](#deployment)
12. [Testing](#testing)

---

## 🏗 System Architecture

```
┌─────────────────────────────────────────────────────────┐
│              Flutter App (Cross-Platform)                │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Presentation Layer (Screens)                     │   │
│  │  - User App (SOS, Tracking, Payment, Token)       │   │
│  │  - Crew App (Mechanic + Assistant)                │   │
│  │  - Admin Web Panel                                │   │
│  └──────────────────────┬───────────────────────────┘   │
│  ┌──────────────────────┴───────────────────────────┐   │
│  │  State Management (Riverpod Providers)            │   │
│  │  Auth | Location | Request | Dispatch | Token     │   │
│  │  Job | Payment                                    │   │
│  └──────────────────────┬───────────────────────────┘   │
│  ┌──────────────────────┴───────────────────────────┐   │
│  │  Service Layer                                    │   │
│  │  Auth | Firestore | Location | Payment | Token    │   │
│  │  Socket | Storage | Notification                  │   │
│  └──────────────────────┬───────────────────────────┘   │
│  ┌──────────────────────┴───────────────────────────┐   │
│  │  Data Layer (Models)                              │   │
│  │  User | Crew | Request | Job | Token | Payment   │   │
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
│  │  FCM (Push Notifications) + Socket.IO Server      │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## 🔬 Core Patents

### 1️⃣ 2-Man Crew Dispatch System
- **Patent Point**: Simultaneous dispatch of 2 separate profiles (Mechanic + Assistant) for a single SOS request
- **Matching Algorithm**: Weighted matrix using Distance (40%) + Rating (25%) + Active Status (20%) + Zone (15%)
- **Assistant** handles "Customer Pickup" (like Rapido)
- **Mechanic** handles "Vehicle Service" (towing/repair)
- **Timeout Handling**: If no crew found in 5 mins → escalate to Admin + 3 backup crews

### 2️⃣ Digital Vehicle Token System
- **Patent Point**: 6-digit alphanumeric token + QR code linking User, Crew, Garage, Vehicle
- **Token Lifecycle**: `generated → handed_to_garage → repair_started → ready_for_pickup → closed`
- **All 3 parties** (User, Crew, Garage) can track token status in real-time
- QR code generation and validation for secure vehicle handover

### 3️⃣ Zone-Based Security Logic
- **Patent Point**: Dynamic security rules based on Urban/Rural geofencing
- **Urban**: 1 verification + OTP for crew
- **Rural**: 2 verifications + Live Photo + Emergency Contact Auto-SMS
- **Night Mode (10PM-6AM)**: Force share live location every 2 minutes

---

## 🛠 Tech Stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | Flutter 3.x, Material 3, Riverpod 2.x |
| **Backend** | Firebase Auth, Firestore, Cloud Functions (Node.js 18), Cloud Storage, FCM |
| **Maps** | google_maps_flutter, Geolocator, Geocoding, flutter_polyline_points |
| **Real-time** | Socket.IO Client |
| **Payment** | Razorpay Flutter SDK |
| **QR** | qr_flutter, mobile_scanner |
| **Other** | dio, flutter_secure_storage, intl, uuid, fl_chart, cached_network_image |

---

## 📁 Project Structure

```
roadresq/
├── lib/
│   ├── main.dart                          # App entry point
│   ├── firebase_options.dart              # Firebase config
│   ├── core/
│   │   ├── constants/
│   │   │   ├── app_constants.dart         # Centralized constants
│   │   │   └── api_endpoints.dart         # Cloud Functions URLs
│   │   ├── theme/
│   │   │   └── app_theme.dart             # Material 3 (light/dark)
│   │   └── utils/
│   │       ├── validators.dart            # Input validators
│   │       └── error_handler.dart         # Centralized error handling
│   ├── models/
│   │   ├── user_model.dart                # User profile
│   │   ├── crew_model.dart                # Mechanic/Assistant profile
│   │   ├── request_model.dart             # SOS request
│   │   ├── job_model.dart                 # Crew job record
│   │   ├── token_model.dart               # Digital vehicle token
│   │   ├── zone_model.dart                # Urban/Rural zone
│   │   ├── payment_model.dart             # Payment + receipt
│   │   └── garage_model.dart              # Partner garage
│   ├── services/
│   │   ├── auth_service.dart              # Firebase Auth
│   │   ├── firestore_service.dart         # Firestore CRUD
│   │   ├── location_service.dart          # GPS + tracking
│   │   ├── socket_service.dart            # Socket.IO events
│   │   ├── payment_service.dart           # Razorpay
│   │   ├── token_service.dart             # Token generation
│   │   ├── crew_dispatch_service.dart     # 2-man dispatch
│   │   ├── zone_security_service.dart     # Zone detection
│   │   ├── notification_service.dart      # In-app notifications
│   │   ├── storage_service.dart           # Firebase Storage
│   │   └── api_service.dart               # HTTP API client
│   ├── providers/
│   │   ├── auth_provider.dart             # Auth state
│   │   ├── location_provider.dart         # Location state
│   │   ├── request_provider.dart          # Request lifecycle
│   │   ├── dispatch_provider.dart         # 2-man dispatch (Patent)
│   │   ├── token_provider.dart            # Token lifecycle (Patent)
│   │   ├── job_provider.dart              # Job management
│   │   └── payment_provider.dart          # Payment + receipt (Patent)
│   └── screens/
│       ├── splash_screen.dart
│       ├── role_selection_screen.dart
│       ├── user_home_screen.dart
│       ├── rescue_request_screen.dart
│       ├── request_status_screen.dart
│       ├── user_tracking_screen.dart
│       ├── token_tracking_screen.dart     # QR + timeline (Patent)
│       ├── payment_screen.dart
│       ├── admin_dashboard_page.dart
│       └── ... (mechanic, assistant screens)
├── functions/
│   ├── package.json                       # Node.js dependencies
│   └── index.js                           # Cloud Functions
├── firestore.rules                        # Security rules
├── firestore.indexes.json                 # Composite indexes
├── pubspec.yaml                           # Flutter dependencies
├── README.md                              # This file
└── TODO.md                                # Progress tracker
```

---

## 🚀 Setup Instructions

### Prerequisites
- Flutter 3.x SDK ([Install](https://docs.flutter.dev/get-started/install))
- Node.js 18+ ([Install](https://nodejs.org/))
- Firebase CLI ([Install](https://firebase.google.com/docs/cli))
- Android Studio / Xcode (for device testing)
- Razorpay Test Account ([Sign up](https://razorpay.com/))

### Step 1: Clone & Install Flutter Dependencies
```bash
git clone https://github.com/your-org/roadresq.git
cd roadresq
flutter pub get
```

### Step 2: Firebase Setup
```bash
# Login to Firebase
firebase login

# Initialize Firebase project
firebase init

# Select: Firestore, Functions, Storage, Hosting (if needed)

# Deploy Firestore indexes
firebase deploy --only firestore:indexes

# Deploy Firestore rules
firebase deploy --only firestore:rules
```

### Step 3: Configure Firebase Options
Replace `lib/firebase_options.dart` with your generated Firebase configuration:
```dart
// Generate using: flutterfire configure
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    // ... your firebase options
  }
}
```

### Step 4: Configure Cloud Functions
```bash
cd functions
npm install

# Set Razorpay keys in Firebase config
firebase functions:config:set razorpay.key_id="rzp_test_XXXX"
firebase functions:config:set razorpay.key_secret="your_test_secret"

# Deploy functions
firebase deploy --only functions
```

### Step 5: Run the App
```bash
# Run on connected device
flutter run

# Run on emulator
flutter run -d chrome  # Web
flutter run -d emulator-5554  # Android
```

---

## 🔥 Firebase Configuration

### Environment Variables
```bash
# Razorpay Keys (required for payment)
firebase functions:config:set razorpay.key_id="rzp_test_XXXX"
firebase functions:config:set razorpay.key_secret="test_secret"

# Twilio (for SMS - optional)
firebase functions:config:set twilio.account_sid="ACxxx"
firebase functions:config:set twilio.auth_token="xxx"
firebase functions:config:set twilio.phone_number="+1234567890"
```

### Firestore Collections
| Collection | Description | Indexes |
|-----------|-------------|---------|
| `users` | User profiles | 0 |
| `crews` | Mechanic/Assistant profiles | 4 |
| `requests` | SOS rescue requests | 4 |
| `jobs` | Crew job records | 4 |
| `tokens` | Digital vehicle tokens | 4 |
| `payments` | Payment records | 3 |
| `zones` | Urban/Rural security zones | 1 |
| `garages` | Partner garages | 0 |
| `notifications` | Push notifications | 2 |
| `disputes` | Dispute records | 2 |
| `analytics` | Platform analytics | 0 |

---

## ⚡ Cloud Functions

### 1. `dispatchTwoManCrew` (HTTPS Callable)
- **Purpose**: Dispatches 1 Mechanic + 1 Assistant per SOS request
- **Algorithm**: Weighted scoring (Distance 40% + Rating 25% + Active 20% + Zone 15%)
- **Timeout**: 5 minutes → escalation to admin + 3 backup crews

### 2. `processCommission` (Firestore Trigger)
- **Trigger**: `onUpdate` of jobs document
- **Action**: Auto-deducts 10% platform commission when job is completed
- **Updates**: Crew totalEarnings, creates commission record

### 3. `generateInvoice` (HTTPS Callable)
- **Purpose**: Generates GST invoice with 18% GST
- **Output**: Receipt number, service amount, GST, commission, total

### 4. `sendEmergencySms` (HTTPS Callable)
- **Purpose**: Queues emergency SMS for rural zone requests
- **Integration**: Twilio (configure via Firebase config)

### 5. `escalateRequest` (HTTPS Callable)
- **Purpose**: Handles timeout escalation when no crew found
- **Action**: Updates request status, notifies admin + backup crews

---

## 📊 Firestore Schema

### requests/{requestId}
```json
{
  "userId": "string",
  "userName": "string",
  "userPhone": "string",
  "location": "GeoPoint",
  "address": "string",
  "vehicleType": "string",
  "issueType": "string",
  "status": "pending|assigned|active|completed|cancelled|escalated",
  "assignedMechanicId": "string?",
  "assignedAssistantId": "string?",
  "mechanicEtaMinutes": "number?",
  "assistantEtaMinutes": "number?",
  "jobGroupId": "string?",
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

### tokens/{tokenId}
```json
{
  "tokenCode": "string (6-char alphanumeric)",
  "qrUrl": "string",
  "userId": "string",
  "crewId": "string",
  "garageId": "string",
  "vehicleNumber": "string",
  "status": "generated|handed_to_garage|repair_started|ready_for_pickup|closed",
  "createdAt": "Timestamp",
  "handedOverAt": "Timestamp?",
  "repairStartedAt": "Timestamp?",
  "readyForPickupAt": "Timestamp?",
  "closedAt": "Timestamp?"
}
```

---

## 🛡 Security Rules

Role-based access control for all collections:
- **Users**: Can read/update own profile
- **Crews**: Can read own profile, update non-KYC fields
- **Requests**: Owner + assigned crew + admin can read/update
- **Tokens**: All 3 parties (User, Crew, Garage) + admin can read
- **Payments**: Created by Cloud Functions only
- **Zones**: Read by all, write by admin only
- **Analytics**: Read-only for admins

---

## 📡 API Reference

### Flutter Riverpod Providers
| Provider | Type | Purpose |
|----------|------|---------|
| `authProvider` | StateNotifier | Auth state management |
| `locationProvider` | StateNotifier | GPS tracking |
| `requestProvider` | StateNotifier | Rescue request lifecycle |
| `dispatchProvider` | StateNotifier | 2-man crew dispatch (Patent) |
| `tokenProvider` | StateNotifier | Digital vehicle token (Patent) |
| `jobProvider` | StateNotifier | Crew job management |
| `paymentProvider` | StateNotifier | Payment + receipt (Patent) |

### REST API Endpoints (Python Flask Backend)
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/user/signup` | User registration |
| POST | `/api/user/login` | User login |
| POST | `/api/mechanic/register` | Mechanic registration |
| POST | `/api/mechanic/login` | Mechanic login |
| POST | `/api/rescueRequests` | Create SOS request |
| GET | `/api/rescueRequests` | List all requests |
| PUT | `/api/rescueRequests/:id/assign` | Assign mechanic |
| PUT | `/api/rescueRequests/:id/status` | Update status |
| PUT | `/api/rescueRequests/:id/payment` | Update payment |
| GET | `/api/admin/users` | Admin: list users |
| GET | `/api/admin/tokens` | Admin: list tokens |
| GET | `/api/admin/zones` | Admin: list zones |

---

## 🚢 Deployment

### Flutter App
```bash
# Android
flutter build apk --release
# or
flutter build appbundle --release

# iOS
flutter build ios --release

# Web
flutter build web --release
```

### Firebase
```bash
# Deploy all
firebase deploy

# Deploy specific services
firebase deploy --only functions
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only storage
```

---

## 🧪 Testing

```bash
# Run Flutter tests
flutter test

# Run Flutter analyze
flutter analyze

# Test Cloud Functions locally
cd functions
npm run serve
```

---

## 📈 Scalability

- **Firestore Indexes**: 24 composite indexes optimized for all query patterns
- **Cloud Functions**: Stateless, auto-scaling Node.js 18 runtime
- **Crew Matching**: O(n) algorithm with geospatial filtering
- **Real-time Updates**: Socket.IO for low-latency crew tracking
- **Offline Support**: Firestore offline persistence enabled

---

## 🔒 Security

- **Authentication**: Firebase Auth with phone + email/password
- **Authorization**: Role-based Firestore security rules
- **Payment Security**: Razorpay with server-side signature verification
- **Data Encryption**: Firebase at-rest and in-transit encryption
- **Token Validation**: QR code scanning for secure vehicle handover

---

## 👥 Roles & Permissions

| Role | Capabilities |
|------|-------------|
| **User** | SOS request, track crew, make payment, scan tokens |
| **Mechanic** | Accept jobs, service vehicle, generate tokens, update status |
| **Assistant** | Accept jobs, pick up customer, assist mechanic |
| **Garage** | Accept tokens, update repair status, release vehicle |
| **Admin** | Manage users/crews, manage zones, analytics, disputes |

---

## 📄 License

Proprietary - Patent Pending. All rights reserved.

## 🤝 Support

- Email: support@roadresq.com
- Phone: +91 9876543210
- Website: https://roadresq.app
