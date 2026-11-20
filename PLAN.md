# RoadResQ - Final Integration Plan

## Service Layer Layout
There are two service directories, by design after cleanup:
- **`lib/services/`** — primary services (22 files): `api_service`, `socket_service`, `matching_service`, and all Feature 1–6 services (`live_tracking_service`, `sos_security_service`, `payment_split_service`, `offline_queue_service`, `zone_security_service`), plus email/password `auth_service` used by `auth_provider`.
- **`lib/core/services/`** — legacy **Phone-OTP** `AuthService` (`sendOTP`/`verifyOTP`/`getUserRole`) used only by `lib/features/auth/login_screen.dart`. Its API is intentionally different from the primary `auth_service.dart`.

> Cleanup: the orphaned legacy `lib/core/services/firestore_service.dart` and `lib/core/services/location_service.dart` were **removed** — they were not imported anywhere (dead code). `flutter analyze` passed after removal.

## Current State: Already Integrated
- ✅ User role (login, home, rescue request, tracking, status, payment, history, support, profile)
- ✅ Mechanic role (login, home, location tracking, history, passbook, safety, community, profile)
- ✅ Assistant role (login, home, job management, history, profile)
- ✅ Admin dashboard (map, requests, hubs, mechanics, socket listeners)
- ✅ Backend with all endpoints (user, mechanic, assistant, admin, tokens, zones, payment)
- ✅ Socket events for real-time updates
- ✅ Firebase integration
- ✅ Razorpay payment integration

## Remaining Fixes (Zero-Error Target)

### Phase 1: Fix Flutter Analyze Warnings (8 issues)
1. Fix unnecessary casts in `admin_dashboard_page.dart` (lines 88-93)
2. Remove unused imports in `assistant_home_screen.dart` (shared_preferences, api_service)

### Phase 2: Core Functionality Enhancements
3. Add receipt generation to `PaymentScreen` after successful payment
4. Add assistant marker and ETA display to `UserTrackingScreen`
5. Add admin tabs (Users, Tokens, Zones management) to `AdminDashboardPage`

### Phase 3: Service Layer Fixes
6. Fix `ZoneSecurityService` - ensure proper cleanup pattern
7. Add loading states consistently across all screens

### Phase 4: Final Verification
8. Run `flutter analyze` to confirm zero errors/warnings
9. Verify backend starts correctly
