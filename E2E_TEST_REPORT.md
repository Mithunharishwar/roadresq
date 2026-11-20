# RoadResQ E2E Test Report

- Base URL: `http://127.0.0.1:5050`
- Run tag: `E2E-1791308663`
- Result: **49/49 passed**, 0 failed

| Module | Step | Method | Path | Expected | Result | Detail |
|---|---|---|---|---|---|---|
| infra | GET /health | GET | `/health` | 200 | PASS | {'message': 'Server healthy', 'success': True} |
| infra | GET /db-test | GET | `/db-test` | 200 | PASS | {'mechanicCount': 42, 'message': 'Mongo working', 'success': True} |
| infra | GET / | GET | `/` | 200 | PASS | RoadResQ Socket Server Running |
| infra | Mongo reachable via /db-test | GET | `/db-test` | success=true | PASS | {'mechanicCount': 42, 'message': 'Mongo working', 'success': True} |
| user | signup | POST | `/api/user/signup` | 200/201 | PASS | {'message': 'User signup successful', 'success': True, 'user': {'_id': '6ac53377bf7328b5935d0ec4', 'createdAt': '2026-10-06T17:44:23.372668', 'email': |
| user | login (email+password) | POST | `/api/user/login` | 200 | PASS | {'message': 'User login successful', 'success': True, 'user': {'_id': '6ac53377bf7328b5935d0ec4', 'createdAt': '2026-10-06T17:44:23.372000', 'email':  |
| user | login rejects bad password | POST | `/api/user/login` | 401 | PASS | {'message': 'Invalid credentials', 'success': False} |
| user | login-otp (send) | POST | `/api/user/login-otp` | 200 | PASS | {'devMode': True, 'devNotice': 'Development OTP. Not a production SMS flow. Disable ROADRESQ_DEV_MODE to suppress.', 'devOtp': '1234', 'message': 'OTP |
| user | verify-otp (dev OTP) | POST | `/api/user/verify-otp` | 200 | PASS | {'message': 'OTP verified successfully', 'success': True, 'user': {'_id': '6ac53377bf7328b5935d0ec4', 'createdAt': '2026-10-06T17:44:23.372000', 'emai |
| user | verify-otp rejects bad OTP | POST | `/api/user/verify-otp` | 401 | PASS | {'message': 'Invalid OTP', 'success': False} |
| mechanic | register | POST | `/api/mechanic/register` | 200/201 | PASS | {'mechanic': {'_id': '6ac53377bf7328b5935d0ec5', 'active': True, 'available': True, 'completedRescues': 0, 'createdAt': '2026-10-06T17:44:23.594195',  |
| mechanic | login | POST | `/api/mechanic/login` | 200 | PASS | {'mechanic': {'_id': '6ac53377bf7328b5935d0ec5', 'active': True, 'available': True, 'completedRescues': 0, 'createdAt': '2026-10-06T17:44:23.594000',  |
| mechanic | login-otp (send) | POST | `/api/mechanic/login-otp` | 200 | PASS | {'devMode': True, 'devNotice': 'Development OTP. Not a production SMS flow. Disable ROADRESQ_DEV_MODE to suppress.', 'devOtp': '1234', 'mechanic': {'_ |
| mechanic | verify-otp | POST | `/api/mechanic/verify-otp` | 200 | PASS | {'mechanic': {'_id': '6ac53377bf7328b5935d0ec5', 'active': True, 'available': True, 'completedRescues': 0, 'createdAt': '2026-10-06T17:44:23.594000',  |
| mechanic | instant access | POST | `/api/mechanic/instant` | 200 | PASS | {'devMode': True, 'devNotice': 'Development-only instant access. This account is unverified and cannot be allocated rescues until an admin verifies it |
| mechanic | go online | PUT | `/api/mechanic/6ac53377bf7328b5935d0ec5/online` | 200 | PASS | {'mechanic': {'_id': '6ac53377bf7328b5935d0ec5', 'active': True, 'available': True, 'completedRescues': 0, 'createdAt': '2026-10-06T17:44:23.594000',  |
| mechanic | push location | PUT | `/api/mechanic/6ac53377bf7328b5935d0ec5/location` | 200 | PASS | {'mechanic': {'_id': '6ac53377bf7328b5935d0ec5', 'active': True, 'available': True, 'completedRescues': 0, 'createdAt': '2026-10-06T17:44:23.594000',  |
| mechanic | load requests (THE reported bug) | GET | `/api/mechanic/6ac53377bf7328b5935d0ec5/requests` | 200 list | PASS | [] |
| assistant | register | POST | `/api/assistant/register` | 200/201 | PASS | {'assistant': {'_id': '6ac53377bf7328b5935d0ec7', 'active': True, 'available': True, 'completedRescues': 0, 'createdAt': '2026-10-06T17:44:23.807259', |
| assistant | login | POST | `/api/assistant/login` | 200 | PASS | {'assistant': {'_id': '6ac53377bf7328b5935d0ec7', 'active': True, 'available': True, 'completedRescues': 0, 'createdAt': '2026-10-06T17:44:23.807000', |
| assistant | go online | PUT | `/api/assistant/6ac53377bf7328b5935d0ec7/online` | 200 | PASS | {'assistant': {'_id': '6ac53377bf7328b5935d0ec7', 'active': True, 'available': True, 'completedRescues': 0, 'createdAt': '2026-10-06T17:44:23.807000', |
| assistant | fetch jobs | GET | `/api/assistant/6ac53377bf7328b5935d0ec7/jobs` | 200 list | PASS | [] |
| rescue | create request | POST | `/api/rescueRequests` | 200/201 | PASS | {'message': 'Rescue request created successfully', 'request': {'_id': '6ac53377bf7328b5935d0ec8', 'acceptanceTimeMs': None, 'acceptedAt': None, 'alloc |
| rescue | list requests | GET | `/api/rescueRequests` | 200 list | PASS | len=54 |
| rescue | list available (was 500) | GET | `/api/rescueRequests/available` | 200 list | PASS | len=25 |
| rescue | get by id | GET | `/api/rescueRequests/6ac53377bf7328b5935d0ec8` | 200 | PASS | {'_id': '6ac53377bf7328b5935d0ec8', 'acceptanceTimeMs': None, 'acceptedAt': None, 'allocationLogId': '', 'amount': 0, 'arrivedAt': None, 'assignedDist |
| rescue | assign mechanic | PUT | `/api/rescueRequests/6ac53377bf7328b5935d0ec8/assign` | 200 | PASS | {'message': 'Mechanic assigned successfully', 'request': {'_id': '6ac53377bf7328b5935d0ec8', 'acceptanceTimeMs': None, 'acceptedAt': None, 'allocation |
| rescue | mechanic location update | PUT | `/api/rescueRequests/6ac53377bf7328b5935d0ec8/mechanic-location` | 200 | PASS | {'message': 'Mechanic location updated', 'success': True} |
| rescue | assign assistant | PUT | `/api/rescueRequests/6ac53377bf7328b5935d0ec8/assign-assistant` | 200 | PASS | {'message': 'Assistant assigned successfully', 'request': {'_id': '6ac53377bf7328b5935d0ec8', 'acceptanceTimeMs': None, 'acceptedAt': None, 'allocatio |
| rescue | assistant location update | PUT | `/api/rescueRequests/6ac53377bf7328b5935d0ec8/assistant-location` | 200 | PASS | {'message': 'Assistant location updated', 'success': True} |
| rescue | state machine refuses illegal jump | PUT | `/api/rescueRequests/6ac53377bf7328b5935d0ec8/status` | 400/409 refused | PASS | {'allowedNextStates': ['CANCELLED', 'MECHANIC_ACCEPTED', 'MECHANIC_DECLINED', 'NO_MECHANIC_AVAILABLE'], 'from': 'MECHANIC_ASSIGNED', 'message': 'illeg |
| rescue | status -> Accepted (legal) | PUT | `/api/rescueRequests/6ac53377bf7328b5935d0ec8/status` | 200 | PASS | {'message': 'Status updated successfully', 'request': {'_id': '6ac53377bf7328b5935d0ec8', 'acceptanceTimeMs': None, 'acceptedAt': '2026-10-06T17:44:24 |
| rescue | status -> On The Way (legal) | PUT | `/api/rescueRequests/6ac53377bf7328b5935d0ec8/status` | 200 | PASS | {'message': 'Status updated successfully', 'request': {'_id': '6ac53377bf7328b5935d0ec8', 'acceptanceTimeMs': None, 'acceptedAt': '2026-10-06T17:44:24 |
| rescue | record payment | PUT | `/api/rescueRequests/6ac53377bf7328b5935d0ec8/payment` | 200 | PASS | {'message': 'Payment updated successfully', 'request': {'_id': '6ac53377bf7328b5935d0ec8', 'acceptanceTimeMs': None, 'acceptedAt': '2026-10-06T17:44:2 |
| admin | list requests | GET | `/api/admin/requests` | 200 list | PASS | [{'_id': '6ac53377bf7328b5935d0ec8', 'acceptanceTimeMs': None, 'acceptedAt': '2026-10-06T17:44:24.118000', 'allocationLogId': '', 'amount': 500, 'arri |
| admin | list hubs | GET | `/api/admin/hubs` | 200 list | PASS | [{'_id': '6ac38825c2903ee134c25b61', 'createdAt': '2026-10-05T11:21:09.534000', 'id': '6ac38825c2903ee134c25b61', 'location': {'lat': 11.0168, 'lng':  |
| admin | list mechanics | GET | `/api/admin/mechanics` | 200 list | PASS | [{'_id': '6ac53377bf7328b5935d0ec7', 'active': True, 'available': True, 'completedRescues': 0, 'createdAt': '2026-10-06T17:44:23.807000', 'currentRequ |
| admin | list users | GET | `/api/admin/users` | 200 list | PASS | [{'_id': '6ac53377bf7328b5935d0ec4', 'createdAt': '2026-10-06T17:44:23.372000', 'email': 'e2e.user.1791308663@example.com', 'id': '6ac53377bf7328b5935 |
| admin | list zones | GET | `/api/admin/zones` | 200 list | PASS | [] |
| admin | list tokens | GET | `/api/admin/tokens` | 200 list | PASS | [] |
| admin | assign-mechanic | PUT | `/api/admin/assign-mechanic` | 200 | PASS | {'message': 'Mechanic assigned by admin', 'request': {'_id': '6ac53377bf7328b5935d0ec8', 'acceptanceTimeMs': None, 'acceptedAt': '2026-10-06T17:44:24. |
| admin | create zone | POST | `/api/admin/zones` | 200/201 | PASS | {'success': True, 'zone': {'_id': '6ac53378bf7328b5935d0ec9', 'createdAt': 'Tue, 06 Oct 2026 17:44:24 GMT', 'id': '6ac53378bf7328b5935d0ec9', 'latMax' |
| admin | delete own zone | DELETE | `/api/admin/zones/6ac53378bf7328b5935d0ec9` | 200 | PASS | {'message': 'Zone deleted', 'success': True} |
| token | create token | POST | `/api/admin/tokens` | 200/201 | PASS | {'success': True, 'token': {'_id': '6ac53378bf7328b5935d0eca', 'createdAt': '2026-10-06T17:44:24.388178', 'hubId': '', 'id': '6ac53378bf7328b5935d0eca |
| token | update status | PUT | `/api/admin/tokens/6ac53378bf7328b5935d0eca/status` | 200 | PASS | {'message': 'Token status updated', 'success': True} |
| token | release | PUT | `/api/admin/tokens/6ac53378bf7328b5935d0eca/release` | 200 | PASS | {'message': 'Token released', 'success': True} |
| token | delete own token | DELETE | `/api/admin/tokens/6ac53378bf7328b5935d0eca` | 200 | PASS | {'message': 'Token deleted', 'success': True} |
| socket | connect to /socket.io | WS | `/socket.io` | connected | PASS | sid=DwQ3bYU1JZNg_-JgAAAA |
| socket | receive 'new_request' broadcast | WS | `/socket.io` | event received | PASS | events seen=['connected', 'new_request'] |
