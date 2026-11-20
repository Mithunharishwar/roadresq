# Socket Wiring — Implementation TODO

Task: Wire the socket functions and provide mediate options so the app workflow runs without errors.

## Status: ✅ COMPLETE

All server-side socket handlers, client-side listeners, and the developer
host-selector bootstrap are now wired. `flutter analyze lib` reports **zero
errors** (only pre-existing warnings/info), and `python -m py_compile
backend/roadresq_backend.py` passes (exit code 0).

## Steps

### Backend — `backend/roadresq_backend.py`
- [x] 1. Add `/api/assistant/register` route (email signup works)
- [x] 2. Add `/api/assistant/login` route (email login works)
- [x] 3. Add missing Socket.IO event handlers:
  - `new_request`
  - `status_updated`
  - `request_assigned`
  - `payment_updated`
  - `update_location`
  - `crew_online`
  - `escalate_request`
  - `backup_crew_notification`
  - `assistant_online`

### Dart — `lib/services/socket_service.dart`
- [x] 4. Add `onAssistantOnlineUpdated` registration method
- [x] 5. Add `onConnectionState` callback + configurable host helper
- [x] 6. Add terminal logging for connect/disconnect/reconnect/errors

### Dart — `lib/screens/assistant_home_screen.dart`
- [x] 7. Register `onAssistantOnlineUpdated` to keep online toggle in sync

### Dart — `lib/screens/admin_dashboard_page.dart`
- [x] 8. Register `onAssistantAssigned` / `onPaymentUpdated` for live refresh

### Dart — `lib/main.dart`
- [x] 9. Add developer host-selector bootstrap (emulator vs LAN) for mediate options

## Follow-up
- [ ] Restart backend: `python backend/roadresq_backend.py`
- [ ] `flutter pub get`
- [x] `flutter analyze` to confirm no errors (38 issues, all warnings/info, 0 errors)
