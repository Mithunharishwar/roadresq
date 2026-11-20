import logging
import os
import sys
import time

# ── Console encoding safety ─────────────────────────────────────────────────
# The Windows default stdio encoding is cp1252, which cannot encode the emoji
# used in this module's diagnostics. An unencodable print() raises
# UnicodeEncodeError INSIDE the request or socket handler, and Flask surfaces
# that as an HTTP 500. It broke /api/mechanic/instant and killed the Socket.IO
# 'connect' handler outright (so no client could ever finish connecting).
# Force UTF-8 and never raise on an unencodable character again.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

from flask import Flask, request, jsonify
from flask.json.provider import DefaultJSONProvider
from flask_cors import CORS
from flask_socketio import SocketIO, emit
from bson import ObjectId
from pymongo.errors import ServerSelectionTimeoutError, PyMongoError
from datetime import datetime, timedelta

# ── Shared modules introduced by the audit remediation ──────────────────────
# Configuration, database access, serializers and the status machine now live
# in their own modules so there is exactly one source of truth for each.
import allocation
import db as rq_db
import realtime
import sms as sms_service
import otp as otp_service
import status_machine as sm
from auth import hash_password, needs_rehash, verify_password
from config import Config
from serializers import (
    error as err_json,
    serialize_garage,
    serialize_hub,
    serialize_mechanic,
    serialize_request,
    serialize_token,
    serialize_user,
)

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("roadresq")

app = Flask(__name__)


# ── BSON-safe JSON encoding ─────────────────────────────────────────────────
# Mongo documents carry BSON types that the stdlib encoder cannot represent.
# Without this, one un-converted field anywhere in a result set turns the entire
# endpoint into an empty-bodied HTTP 500 — which the Flutter client can only
# report as a meaningless "Invalid JSON response". Fixing the encoder globally
# means a missed conversion degrades to a correct response instead of an outage.
class _MongoJSONProvider(DefaultJSONProvider):
    """Teach jsonify to render BSON values (ObjectId) instead of raising."""

    def default(self, obj):
        if isinstance(obj, ObjectId):
            return str(obj)
        return super().default(obj)


app.json = _MongoJSONProvider(app)

# Secret comes from the environment (config.Config). No literal is shipped.
# §39
app.config['SECRET_KEY'] = Config.SECRET_KEY

CORS(app)

socketio = SocketIO(
    app,
    cors_allowed_origins="*",
    async_mode="threading",
    logger=Config.DEBUG,
    engineio_logger=Config.DEBUG,
)

# Register the socket with the shared realtime hub so HTTP route modules in the
# api_v2 blueprint can broadcast without importing this module. §23
realtime.register(socketio)

# =========================
# MONGODB
# =========================
# Connection details come from the environment; one client for the whole
# process, shared with api_v2 through the `db` module. §4, §36
db = rq_db.get_db()

rescue_requests = rq_db.rescue_requests()
mechanics = rq_db.mechanics()
users = rq_db.users()
hubs = rq_db.hubs()
garages = rq_db.garages()

if rq_db.ping():
    log.info("MongoDB connected (%s)", Config.DB_NAME)
else:
    log.error(
        "MongoDB unreachable at %s — API calls that touch the database will fail",
        Config.MONGO_URI,
    )

# Create every declared index at boot (idempotent). §36
try:
    _index_summary = rq_db.ensure_indexes(verbose=False)
    log.info(
        "Indexes: %d ready, %d failed",
        _index_summary["createdCount"],
        _index_summary["failedCount"],
    )
except Exception as exc:  # pragma: no cover - never block boot on indexes
    log.warning("Index setup skipped: %s", exc)

# =========================
# HELPERS
# =========================
def safe_object_id(value):
    try:
        return ObjectId(value)
    except Exception:
        return None


def id_match(value):
    """Mongo filter matching a linkage id stored EITHER as a string or as an ObjectId.

    `mechanicId` is written inconsistently across `rescue_requests` — verified
    directly in Mongo: 13 documents store it as a str and 9 as an ObjectId. A
    filter using only the string form therefore matched nothing for those 9
    rows, so a mechanic who genuinely had 9 jobs saw an empty request list. This
    matches both representations so stored form can no longer hide data.

    Read-side only, deliberately: normalising the stored type would change what
    other readers expect, whereas accepting both is safe either way.
    """
    if value is None or value == "":
        return {"$in": ["", None]}

    candidates = [value]
    if isinstance(value, str) and ObjectId.is_valid(value):
        candidates.append(ObjectId(value))
    return {"$in": candidates}

# NOTE: serialize_request / serialize_mechanic / serialize_user / serialize_hub
# are imported from `serializers.py`. The previous local copies were the source
# of two defects: they emitted the stored password in `serialize_mechanic` and
# `serialize_user`, and they defaulted missing coordinates to (0, 0) — which
# silently placed every location-less request in the Gulf of Guinea. §38, §39

def json_error(message, status=400):
    """Canonical error envelope. Delegates to serializers.error. §38"""
    return jsonify(err_json(message, status)), status

# =========================
# BASIC ROUTES
# =========================
@app.route('/')
def home():
    return 'RoadResQ Socket Server Running'

@app.route('/api/payments/config', methods=['GET'])
def payments_config():
    """Public payment settings for the app.

    The publishable key id is safe to expose; the secret never leaves the
    server. This exists so the Flutter client does not have to ship a Razorpay
    key compiled into its source, where it cannot be rotated without a rebuild.
    """
    return jsonify({
        "success": True,
        "enabled": Config.payments_enabled(),
        "keyId": Config.RAZORPAY_KEY_ID,
        "testMode": Config.RAZORPAY_TEST_MODE,
        "currency": Config.PRICING_CURRENCY,
    }), 200


@app.route('/api/system/sms-status', methods=['GET'])
def sms_status():
    """What the app and admin console can show about login-code delivery.

    Deliberately reports configuration, not success: a provider can still be
    down. `delivered` outcomes are per request (`smsSent` in the login response).
    """
    return jsonify({
        "success": True,
        "sms": sms_service.status(),
        "otp": {
            "length": Config.OTP_LENGTH,
            "ttlSeconds": Config.OTP_TTL_SECONDS,
            "maxAttempts": Config.OTP_MAX_ATTEMPTS,
            "resendCooldownSeconds": Config.OTP_RESEND_COOLDOWN_SECONDS,
            "maxPerHour": Config.OTP_MAX_PER_HOUR,
        },
        "devMode": Config.DEV_MODE,
    }), 200


@app.route('/health')
def health():
    return jsonify({
        'success': True,
        'message': 'Server healthy'
    }), 200

@app.route('/db-test')
def db_test():
    try:
        count = mechanics.count_documents({})
        return jsonify({
            "success": True,
            "message": "Mongo working",
            "mechanicCount": count
        }), 200
    except Exception as e:
        return jsonify({
            "success": False,
            "message": str(e)
        }), 500

# =========================
# USER AUTH
# =========================
@app.route('/api/user/signup', methods=['POST'])
def user_signup():
    data = request.get_json(silent=True) or {}

    name = data.get('name', '').strip()
    email = data.get('email', '').strip().lower()
    password = data.get('password', '').strip()
    phone = data.get('phone', '').strip()

    if not name or not email or not password or not phone:
        return json_error('All fields are required', 400)

    existing = users.find_one({"email": email})
    if existing:
        return json_error('User already exists', 409)

    doc = {
        "name": name,
        "email": email,
        # Hashed before storage — the plaintext password is never persisted. §39
        "password": hash_password(password),
        "phone": phone,
        "role": "user",
        "createdAt": datetime.utcnow(),
        "updatedAt": datetime.utcnow(),
    }

    try:
        result = users.insert_one(doc)
    except PyMongoError as exc:
        return json_error(f'Database error: {exc}', 500)

    doc["_id"] = result.inserted_id

    return jsonify({
        "success": True,
        "message": "User signup successful",
        "user": serialize_user(doc),
    }), 201

@app.route('/api/user/login', methods=['POST'])
def user_login():
    data = request.get_json(silent=True) or {}

    email = data.get('email', '').strip().lower()
    password = data.get('password', '').strip()

    if not email or not password:
        return json_error('Email and password are required', 400)

    user = users.find_one({"email": email})

    # Password is verified in constant time against the stored hash. Legacy
    # plaintext rows still work and are upgraded to a hash on first login. §39
    if not user or not verify_password(user.get("password"), password):
        return json_error('Invalid credentials', 401)

    if needs_rehash(user.get("password")):
        try:
            users.update_one(
                {"_id": user["_id"]},
                {"$set": {"password": hash_password(password),
                          "updatedAt": datetime.utcnow()}},
            )
        except PyMongoError:
            log.warning('Password rehash failed for user %s', user.get('_id'))

    return jsonify({
        "success": True,
        "message": "User login successful",
        "user": serialize_user(user),
    }), 200


# ── OTP delivery ───────────────────────────────────────────────────────────
def _issue_and_send_otp(phone, purpose, response):
    """Attach a real, single-use login code to a login response.

    The code is random, hashed at rest and expires; see otp.py. Delivery is
    attempted through sms.py. The response never claims `smsSent: true` unless
    the provider accepted the message, and the plaintext code is returned only
    as the clearly-named `devOtp` field while DEV_MODE is on.
    """
    try:
        code = otp_service.issue(phone, purpose)
    except otp_service.OtpError as exc:
        return json_error(exc.message, exc.status)

    result = sms_service.send_otp(phone, code)

    response["smsSent"] = result.ok
    response["provider"] = result.provider

    if result.ok:
        otp_service.mark_delivered(phone, purpose, result.provider)
        return jsonify(response), 200

    # No provider: the login still has to work in development, but the client is
    # told the truth about delivery.
    if not Config.DEV_MODE:
        return json_error(
            f"Could not send the login code: {result.detail}", 502
        )

    response["devOtp"] = code
    response["devNotice"] = result.detail
    return jsonify(response), 200


@app.route('/api/user/login-otp', methods=['POST'])
def user_login_otp():
    data = request.get_json(silent=True) or {}

    phone = data.get('phone', '').strip()
    if not phone:
        return json_error('Phone is required', 400)

    user = users.find_one({"phone": phone})

    if not user:
        doc = {
            "name": "User",
            "email": "",
            "password": "",
            "phone": phone,
            "role": "user",
            "createdAt": datetime.utcnow(),
            "updatedAt": datetime.utcnow(),
        }
        try:
            result = users.insert_one(doc)
        except PyMongoError as exc:
            return json_error(f'Database error: {exc}', 500)
        doc["_id"] = result.inserted_id
        user = doc

    response = {
        "success": True,
        "message": "OTP sent successfully",
        "user": serialize_user(user),
        "devMode": Config.DEV_MODE,
    }

    return _issue_and_send_otp(phone, 'user', response)

@app.route('/api/user/verify-otp', methods=['POST'])
def user_verify_otp():
    data = request.get_json(silent=True) or {}

    phone = data.get('phone', '').strip()
    otp = data.get('otp', '').strip()

    if not phone or not otp:
        return json_error('Phone and OTP are required', 400)

    try:
        otp_service.verify(phone, 'user', otp)
    except otp_service.OtpError as exc:
        return json_error(exc.message, exc.status)

    user = users.find_one({"phone": phone})

    if not user:
        doc = {
            "name": "User",
            "email": "",
            "password": "",
            "phone": phone,
            "role": "user",
            "createdAt": datetime.utcnow(),
            "updatedAt": datetime.utcnow(),
        }
        try:
            result = users.insert_one(doc)
        except PyMongoError as exc:
            return json_error(f'Database error: {exc}', 500)
        doc["_id"] = result.inserted_id
        user = doc

    return jsonify({
        "success": True,
        "message": "OTP verified successfully",
        "user": serialize_user(user),
    }), 200

# =========================
# MECHANIC AUTH
# =========================
@app.route('/api/mechanic/register', methods=['POST'])
def mechanic_register():
    data = request.get_json(silent=True) or {}

    name = data.get('name', '').strip()
    email = data.get('email', '').strip().lower()
    password = data.get('password', '').strip()
    phone = data.get('phone', '').strip()

    if not name or not email or not password:
        return json_error('Name, email, and password are required', 400)

    existing = mechanics.find_one({"email": email})
    if existing:
        return json_error('Mechanic already exists', 409)

    doc = {
        "name": name,
        "email": email,
        # Hashed before storage. §39
        "password": hash_password(password),
        "phone": phone,
        "role": "mechanic",
        "online": False,
        "available": True,
        "location": {},
        # A new account is NOT a verified professional. Verification is a
        # separate, explicit admin decision. §8, §32
        "verified": False,
        "verificationStatus": "pending",
        "services": [],
        "vehicleTypes": [],
        "rating": 0.0,
        "ratingCount": 0,
        "completedRescues": 0,
        "workload": 0,
        "createdAt": datetime.utcnow(),
        "updatedAt": datetime.utcnow(),
    }

    try:
        result = mechanics.insert_one(doc)
    except PyMongoError as exc:
        return json_error(f'Database error: {exc}', 500)

    doc["_id"] = result.inserted_id

    return jsonify({
        "success": True,
        "message": "Mechanic registered successfully",
        "mechanic": serialize_mechanic(doc),
    }), 201

@app.route('/api/mechanic/login', methods=['POST'])
def mechanic_login():
    data = request.get_json(silent=True) or {}

    email = data.get('email', '').strip().lower()
    password = data.get('password', '').strip()

    if not email or not password:
        return json_error('Email and password are required', 400)

    mechanic = mechanics.find_one({"email": email})

    # Constant-time verification against the stored hash; legacy plaintext rows
    # are upgraded transparently on first successful login. §39
    if not mechanic or not verify_password(mechanic.get("password"), password):
        return json_error('Invalid mechanic credentials', 401)

    if mechanic.get("isBanned"):
        return json_error('This account is suspended', 403)

    if needs_rehash(mechanic.get("password")):
        try:
            mechanics.update_one(
                {"_id": mechanic["_id"]},
                {"$set": {"password": hash_password(password),
                          "updatedAt": datetime.utcnow()}},
            )
        except PyMongoError:
            log.warning('Password rehash failed for mechanic %s', mechanic.get('_id'))

    return jsonify({
        "success": True,
        "message": "Mechanic login successful",
        "mechanic": serialize_mechanic(mechanic),
    }), 200

@app.route('/api/mechanic/login-otp', methods=['POST'])
def mechanic_login_otp():
    data = request.get_json(silent=True) or {}

    phone = data.get('phone', '').strip()
    if not phone:
        return json_error('Phone is required', 400)

    mechanic = mechanics.find_one({"phone": phone})

    if not mechanic:
        doc = {
            "name": "Mechanic",
            "email": "",
            "password": "",
            "phone": phone,
            "role": "mechanic",
            "online": False,
            "available": True,
            "location": {},
            "verified": False,
            "verificationStatus": "pending",
            "services": [],
            "vehicleTypes": [],
            "rating": 0.0,
            "ratingCount": 0,
            "completedRescues": 0,
            "workload": 0,
            "createdAt": datetime.utcnow(),
            "updatedAt": datetime.utcnow(),
        }
        try:
            result = mechanics.insert_one(doc)
        except PyMongoError as exc:
            return json_error(f'Database error: {exc}', 500)
        doc["_id"] = result.inserted_id
        mechanic = doc

    response = {
        "success": True,
        "message": "OTP sent successfully",
        "mechanic": serialize_mechanic(mechanic),
        "devMode": Config.DEV_MODE,
    }

    return _issue_and_send_otp(phone, 'mechanic', response)

@app.route('/api/mechanic/verify-otp', methods=['POST'])
def mechanic_verify_otp():
    data = request.get_json(silent=True) or {}

    phone = data.get('phone', '').strip()
    otp = data.get('otp', '').strip()

    if not phone or not otp:
        return json_error('Phone and OTP are required', 400)

    # Development OTP is accepted only while DEV_MODE is on. §7, §42
    try:
        otp_service.verify(phone, 'mechanic', otp)
    except otp_service.OtpError as exc:
        return json_error(exc.message, exc.status)

    mechanic = mechanics.find_one({"phone": phone})

    if not mechanic:
        doc = {
            "name": "Mechanic",
            "email": "",
            "password": "",
            "phone": phone,
            "role": "mechanic",
            "online": False,
            "available": True,
            "location": {},
            "verified": False,
            "verificationStatus": "pending",
            "services": [],
            "vehicleTypes": [],
            "rating": 0.0,
            "ratingCount": 0,
            "completedRescues": 0,
            "workload": 0,
            "createdAt": datetime.utcnow(),
            "updatedAt": datetime.utcnow(),
        }
        try:
            result = mechanics.insert_one(doc)
        except PyMongoError as exc:
            return json_error(f'Database error: {exc}', 500)
        doc["_id"] = result.inserted_id
        mechanic = doc

    return jsonify({
        "success": True,
        "message": "OTP verified successfully",
        "mechanic": serialize_mechanic(mechanic),
    }), 200

@app.route('/api/mechanic/instant', methods=['POST'])
def mechanic_instant():
    data = request.get_json(silent=True) or {}
    log.info("/api/mechanic/instant called")

    # This endpoint creates an account with no password and no verification. It
    # is a development convenience only and is refused when DEV_MODE is off.
    # §7, §42 — never leave fake authentication active in production mode.
    if not Config.DEV_MODE:
        return json_error(
            'Instant mechanical access is a development-only feature '
            '(ROADRESQ_DEV_MODE=off)', 403
        )

    phone = data.get('phone', '').strip()
    name = data.get('name', '').strip() or 'Mechanic'

    mechanic = None
    if phone:
        mechanic = mechanics.find_one({"phone": phone})

    if not mechanic:
        doc = {
            "name": name,
            "email": "",
            "password": "",
            "phone": phone,
            "role": "mechanic",
            "online": False,
            "available": True,
            "location": {},
            # Demo accounts are NOT verified and declare no services, so they
            # cannot be picked up by the allocation engine until an admin
            # verifies them and their capabilities are set. §8, §17
            "verified": False,
            "verificationStatus": "pending",
            "services": [],
            "vehicleTypes": [],
            "rating": 0.0,
            "ratingCount": 0,
            "completedRescues": 0,
            "workload": 0,
            "isDemoAccount": True,
            "createdAt": datetime.utcnow(),
            "updatedAt": datetime.utcnow(),
        }
        try:
            result = mechanics.insert_one(doc)
        except PyMongoError as exc:
            return json_error(f'Database error: {exc}', 500)
        doc["_id"] = result.inserted_id
        mechanic = doc

    response = {
        "success": True,
        "message": "Instant access granted",
        "devMode": True,
        "devNotice": (
            "Development-only instant access. This account is unverified and "
            "cannot be allocated rescues until an admin verifies it."
        ),
        "mechanic": serialize_mechanic(mechanic),
    }
    log.info('mechanic instant access created: id=%s', mechanic.get('_id'))
    return jsonify(response), 200

# =========================
# MECHANIC STATUS / LOCATION
# =========================
@app.route('/api/mechanic/<mechanic_id>/online', methods=['PUT'])
def update_mechanic_online(mechanic_id):
    oid = safe_object_id(mechanic_id)
    if not oid:
        return json_error('Invalid mechanic ID', 400)

    data = request.get_json(silent=True) or {}
    online = bool(data.get('online', False))

    result = mechanics.update_one(
        {"_id": oid},
        {"$set": {"online": online}}
    )

    if result.matched_count == 0:
        return json_error('Mechanic not found', 404)

    mechanic = mechanics.find_one({"_id": oid})
    payload = serialize_mechanic(mechanic)

    socketio.emit('mechanic_online_updated', {
        'success': True,
        'mechanicId': mechanic_id,
        'name': payload.get('name', ''),
        'online': online,
        'isOnline': online,
    })

    return jsonify({
        "success": True,
        "message": "Mechanic online status updated",
        "mechanic": payload,
    }), 200

@app.route('/api/mechanic/<mechanic_id>/location', methods=['PUT'])
def update_mechanic_location(mechanic_id):
    oid = safe_object_id(mechanic_id)
    if not oid:
        return json_error('Invalid mechanic ID', 400)

    data = request.get_json(silent=True) or {}
    lat = data.get('lat')
    lng = data.get('lng')

    if lat is None or lng is None:
        return json_error('lat and lng are required', 400)

    # Reject out-of-range coordinates rather than persisting them. §38
    try:
        lat_f = float(lat)
        lng_f = float(lng)
    except (TypeError, ValueError):
        return json_error('lat and lng must be numeric', 400)

    if not (-90 <= lat_f <= 90) or not (-180 <= lng_f <= 180):
        return json_error(
            'lat must be within -90..90 and lng within -180..180', 400
        )

    result = mechanics.update_one(
        {"_id": oid},
        {"$set": {
            "location": {"lat": lat_f, "lng": lng_f},
            # Timestamped so the allocation engine's location-staleness rule
            # has something to evaluate. §17
            "locationUpdatedAt": datetime.utcnow(),
            "updatedAt": datetime.utcnow(),
        }}
    )

    if result.matched_count == 0:
        return json_error('Mechanic not found', 404)

    mechanic = mechanics.find_one({"_id": oid})
    payload = serialize_mechanic(mechanic)

    # Previously this handler wrote to MongoDB but broadcast nothing, so a user
    # tracking their mechanic saw a frozen marker until they refreshed. §22, §23
    location_event = {
        'success': True,
        'mechanicId': mechanic_id,
        'requestId': data.get('requestId', ''),
        'lat': lat_f,
        'lng': lng_f,
    }
    realtime.emit_event('mechanic_location_updated', location_event)
    realtime.emit_event('mechanic_location_global_updated', location_event)

    return jsonify({
        "success": True,
        "message": "Mechanic location updated",
        "mechanic": payload,
    }), 200

@app.route('/api/mechanic/<mechanic_id>/requests', methods=['GET'])
def fetch_mechanic_requests(mechanic_id):
    # FIXED: this previously returned EVERY request that was in an assigned-or-
    # later state, so every mechanic could see every other mechanic's jobs.
    # It now returns only the requests assigned to this mechanic. §39
    try:
        docs = rescue_requests.find(
            # id_match, not a bare equality: mechanicId is stored as a string on
            # 13 requests and as an ObjectId on 9, so the string-only filter hid
            # every ObjectId row from its assigned mechanic.
            {"mechanicId": id_match(mechanic_id)}
        ).sort('createdAt', -1).limit(200)
        return jsonify([serialize_request(d) for d in docs]), 200
    except PyMongoError as exc:
        return json_error(f'Database error: {exc}', 500)

# =========================
# ASSISTANT (Milestone 1) — routes to serve the assistant panel
# Assistants are stored in the `mechanics` collection (reused), and their
# assigned jobs live on `rescue_requests` documents via `assistantId`.
# =========================
@app.route('/api/assistant/register', methods=['POST'])
def assistant_register():
    data = request.get_json(silent=True) or {}

    name = data.get('name', '').strip()
    email = data.get('email', '').strip().lower()
    password = data.get('password', '').strip()
    phone = data.get('phone', '').strip()

    if not name or not email or not password:
        return json_error('Name, email, and password are required', 400)

    existing = mechanics.find_one({"email": email})
    if existing:
        return json_error('Assistant already exists', 409)

    doc = {
        "name": name,
        "email": email,
        # Hash at rest. This previously stored the raw password, and login
        # matched it by plaintext equality, so assistant credentials were
        # readable in the database. §39
        "password": hash_password(password),
        "phone": phone,
        "online": False,
        "location": {},
        "role": "assistant",
        "createdAt": datetime.utcnow(),
    }

    result = mechanics.insert_one(doc)
    doc["_id"] = result.inserted_id

    return jsonify({
        "success": True,
        "message": "Assistant registered successfully",
        "assistant": serialize_mechanic(doc),
    }), 201


@app.route('/api/assistant/login', methods=['POST'])
def assistant_login():
    data = request.get_json(silent=True) or {}

    email = data.get('email', '').strip().lower()
    password = data.get('password', '').strip()

    if not email or not password:
        return json_error('Email and password are required', 400)

    assistant = mechanics.find_one({
        "email": email,
        "role": "assistant",
    })

    # Constant-time check against the stored hash. This previously matched the
    # password by plaintext equality ({"password": password}), which required
    # storing it unhashed. §39
    if not assistant or not verify_password(assistant.get("password"), password):
        return json_error('Invalid assistant credentials', 401)

    if needs_rehash(assistant.get("password")):
        try:
            mechanics.update_one(
                {"_id": assistant["_id"]},
                {"$set": {"password": hash_password(password),
                          "updatedAt": datetime.utcnow()}},
            )
        except PyMongoError:
            log.warning('Password rehash failed for assistant %s',
                        assistant.get('_id'))

    return jsonify({
        "success": True,
        "message": "Assistant login successful",
        "assistant": serialize_mechanic(assistant),
    }), 200


# ── Assistant phone-OTP login ───────────────────────────────────────────────
# Assistants live in the `mechanics` collection with role="assistant". There was
# no assistant OTP endpoint, so the client's "verify" step re-called send-OTP and
# accepted any code. These mirror the user/mechanic flow. Unlike those, a login
# OTP is only issued for an EXISTING assistant account, so this cannot be used to
# self-register a privileged role.
@app.route('/api/assistant/login-otp', methods=['POST'])
def assistant_login_otp():
    data = request.get_json(silent=True) or {}

    phone = data.get('phone', '').strip()
    if not phone:
        return json_error('Phone is required', 400)

    assistant = mechanics.find_one({"phone": phone, "role": "assistant"})
    if not assistant:
        return json_error('No assistant account for this phone number', 404)

    response = {
        "success": True,
        "message": "OTP sent successfully",
        "assistant": serialize_mechanic(assistant),
        "devMode": Config.DEV_MODE,
    }
    return _issue_and_send_otp(phone, 'assistant', response)


@app.route('/api/assistant/verify-otp', methods=['POST'])
def assistant_verify_otp():
    data = request.get_json(silent=True) or {}

    phone = data.get('phone', '').strip()
    otp = data.get('otp', '').strip()

    if not phone or not otp:
        return json_error('Phone and OTP are required', 400)

    try:
        otp_service.verify(phone, 'assistant', otp)
    except otp_service.OtpError as exc:
        return json_error(exc.message, exc.status)

    assistant = mechanics.find_one({"phone": phone, "role": "assistant"})
    if not assistant:
        return json_error('No assistant account for this phone number', 404)

    return jsonify({
        "success": True,
        "message": "OTP verified successfully",
        "assistant": serialize_mechanic(assistant),
    }), 200


# =========================
# GARAGE — register / login
# =========================
# Garages previously had NO server-side identity: the client accepted any
# non-empty string as a "garage ID" and opened the dashboard that verifies and
# releases vehicle tokens. These routes give a garage a real credential check,
# with the password hashed at rest (never stored or compared in plaintext).
@app.route('/api/garage/register', methods=['POST'])
def garage_register():
    data = request.get_json(silent=True) or {}

    garage_code = data.get('garageId', '').strip()
    name = data.get('name', '').strip()
    phone = data.get('phone', '').strip()
    password = data.get('password', '').strip()

    if not garage_code or not name or not password:
        return json_error('garageId, name and password are required', 400)

    if garages.find_one({"garageId": garage_code}):
        return json_error('Garage already registered', 409)

    doc = {
        "garageId": garage_code,
        "name": name,
        "phone": phone,
        "email": data.get('email', '').strip().lower(),
        "password": hash_password(password),
        # A new garage starts unverified; token work should be gated on this
        # until an admin approves it.
        "verified": False,
        "createdAt": datetime.utcnow(),
        "updatedAt": datetime.utcnow(),
    }

    try:
        result = garages.insert_one(doc)
    except PyMongoError as exc:
        return json_error(f'Database error: {exc}', 500)
    doc["_id"] = result.inserted_id

    return jsonify({
        "success": True,
        "message": "Garage registered successfully",
        "garage": serialize_garage(doc),
    }), 201


@app.route('/api/garage/login', methods=['POST'])
def garage_login():
    data = request.get_json(silent=True) or {}

    garage_code = data.get('garageId', '').strip()
    password = data.get('password', '').strip()

    if not garage_code or not password:
        return json_error('garageId and password are required', 400)

    garage = garages.find_one({"garageId": garage_code})

    # Constant-time comparison against the stored hash. §39
    if not garage or not verify_password(garage.get("password"), password):
        return json_error('Invalid garage credentials', 401)

    if needs_rehash(garage.get("password")):
        try:
            garages.update_one(
                {"_id": garage["_id"]},
                {"$set": {"password": hash_password(password),
                          "updatedAt": datetime.utcnow()}},
            )
        except PyMongoError:
            log.warning('Password rehash failed for garage %s', garage.get('_id'))

    return jsonify({
        "success": True,
        "message": "Garage login successful",
        "garage": serialize_garage(garage),
    }), 200


@app.route('/api/garage/<garage_id>/jobs', methods=['GET'])
def fetch_garage_jobs(garage_id):
    """Requests linked to this garage.

    The Garage dashboard used to stream Firestore `jobs`, which the app cannot
    read at all: there is no Firebase Auth session (logins go through this
    backend), so every rule beginning with isAuthenticated() denies the request
    and the screen showed a permission error. This is the garage's real data
    path.

    `garageId` is not written onto any request yet — verified directly in Mongo:
    0 of 55 `rescue_requests` documents carry it, and `tokens` is empty — so this
    legitimately returns an empty list today. It starts returning rows the moment
    a request records `garageId`.
    """
    docs = rescue_requests.find({"garageId": id_match(garage_id)}).sort('createdAt', -1)

    return jsonify([serialize_request(d) for d in docs]), 200


@app.route('/api/garage/<garage_id>/inbox', methods=['GET'])
def fetch_garage_inbox(garage_id):
    """Open requests a garage can take in.

    `GET /api/garage/<id>/jobs` only returns requests that ALREADY carry this
    garage's id, and nothing ever wrote that field — so the dashboard was
    permanently empty and the garage had no way to acquire work. This is the
    missing entry point: requests not yet linked to any garage and not finished.

    Closed/cancelled work is excluded so a garage cannot pick up a dead request,
    and the page is capped because the collection is unbounded.
    """
    finished = [
        'CLOSED', 'CANCELLED', 'Closed', 'Cancelled', 'closed', 'cancelled',
        'completed', 'Completed', 'COMPLETED', 'PAYMENT_COMPLETED',
    ]
    query = {
        'status': {'$nin': finished},
        '$or': [
            {'garageId': {'$exists': False}},
            {'garageId': None},
            {'garageId': ''},
        ],
    }

    try:
        docs = rescue_requests.find(query).sort('createdAt', -1).limit(50)
        return jsonify([serialize_request(d) for d in docs]), 200
    except PyMongoError as exc:
        return json_error(f'Database error: {exc}', 500)


@app.route('/api/rescueRequests/<request_id>/garage', methods=['PUT'])
def link_request_to_garage(request_id):
    """Hand a request over to a garage (the physical vehicle handover).

    Writes `garageId` onto the request — the single field the garage's own job
    list filters on. Refuses to take work that already belongs to a different
    garage, because that would silently move a customer's vehicle between
    businesses. Repeating the same link is a no-op, not an error, so a double tap
    is safe.
    """
    data = request.get_json(silent=True) or {}
    garage_id = (data.get('garageId') or '').strip()
    if not garage_id:
        return json_error('garageId is required', 400)

    oid = safe_object_id(request_id)
    if not oid:
        return json_error('Invalid request ID', 400)

    existing = rescue_requests.find_one({'_id': oid})
    if not existing:
        return json_error('Request not found', 404)

    current = (existing.get('garageId') or '').strip()
    if current and current != garage_id:
        # Must be a real 409, not a 200 carrying a failure body: the client uses
        # the status code to tell "someone else owns this" from "it worked".
        return jsonify(err_json(f'This request already belongs to garage {current}', 409)), 409

    if current == garage_id:
        return jsonify({
            'success': True,
            'alreadyLinked': True,
            'request': serialize_request(existing),
        }), 200

    rescue_requests.update_one({'_id': oid}, {'$set': {
        'garageId': garage_id,
        'garageLinkedAt': datetime.utcnow(),
        'updatedAt': datetime.utcnow(),
    }})
    doc = rescue_requests.find_one({'_id': oid})
    return jsonify({
        'success': True,
        'alreadyLinked': False,
        'request': serialize_request(doc),
    }), 200


@app.route('/api/assistant/instant', methods=['POST'])
def assistant_instant():
    """Development-only instant assistant access.

    The app's Assistant > Instant tab previously called /api/mechanic/instant
    and then relabelled the response client-side, so it provisioned a record
    with `role: "mechanic"`. That put a rider into the mechanic pool and gave
    the account the wrong role everywhere roles are read (allocation, listings,
    and the Firestore rules that key off a `role` custom claim). This endpoint
    mirrors the mechanic flow but creates and looks up an `assistant`.

    Refused when DEV_MODE is off, exactly like /api/mechanic/instant — §7, §42.
    """
    data = request.get_json(silent=True) or {}
    log.info("/api/assistant/instant called")

    if not Config.DEV_MODE:
        return json_error(
            'Instant assistant access is a development-only feature '
            '(ROADRESQ_DEV_MODE=off)', 403
        )

    phone = data.get('phone', '').strip()
    name = data.get('name', '').strip() or 'Assistant'

    assistant = None
    if phone:
        # Role-scoped: never adopt a mechanic that happens to share the number.
        assistant = mechanics.find_one({"phone": phone, "role": "assistant"})

    if not assistant:
        doc = {
            "name": name,
            "email": "",
            "password": "",
            "phone": phone,
            "role": "assistant",
            "online": False,
            "available": True,
            "location": {},
            # Demo accounts are NOT verified and declare no services, so the
            # allocation engine cannot pick them up until an admin verifies.
            "verified": False,
            "verificationStatus": "pending",
            "services": [],
            "vehicleTypes": [],
            "rating": 0.0,
            "ratingCount": 0,
            "completedRescues": 0,
            "workload": 0,
            "isDemoAccount": True,
            "createdAt": datetime.utcnow(),
            "updatedAt": datetime.utcnow(),
        }
        try:
            result = mechanics.insert_one(doc)
        except PyMongoError as exc:
            return json_error(f'Database error: {exc}', 500)
        doc["_id"] = result.inserted_id
        assistant = doc

    response = {
        "success": True,
        "message": "Instant access granted",
        "devMode": True,
        "devNotice": (
            "Development-only instant access. This account is unverified and "
            "cannot be allocated rescues until an admin verifies it."
        ),
        "assistant": serialize_mechanic(assistant),
    }
    log.info('assistant instant access created: id=%s role=%s',
             assistant.get('_id'), assistant.get('role'))
    return jsonify(response), 200


@app.route('/api/assistant/<assistant_id>/jobs', methods=['GET'])
def fetch_assistant_jobs(assistant_id):
    docs = rescue_requests.find({
        # id_match tolerates assistantId being stored as a string or ObjectId.
        "assistantId": id_match(assistant_id)
    }).sort('createdAt', -1)

    return jsonify([serialize_request(d) for d in docs]), 200

@app.route('/api/assistant/<assistant_id>/online', methods=['PUT'])
def update_assistant_online(assistant_id):
    oid = safe_object_id(assistant_id)
    if not oid:
        return json_error('Invalid assistant ID', 400)

    data = request.get_json(silent=True) or {}
    online = bool(data.get('online', False))

    result = mechanics.update_one(
        {"_id": oid},
        {"$set": {"online": online}}
    )

    if result.matched_count == 0:
        # Assistant may not exist in mechanics collection yet — that's fine.
        return jsonify({
            "success": True,
            "message": "Assistant online status accepted",
            "assistantId": assistant_id,
            "online": online,
        }), 200

    assistant = mechanics.find_one({"_id": oid})
    payload = serialize_mechanic(assistant)

    socketio.emit('assistant_online_updated', {
        'success': True,
        'assistantId': assistant_id,
        'name': payload.get('name', ''),
        'online': online,
    })

    return jsonify({
        "success": True,
        "message": "Assistant online status updated",
        "assistant": payload,
    }), 200

@app.route('/api/assistant/<assistant_id>/location', methods=['PUT'])
def update_assistant_direct_location(assistant_id):
    oid = safe_object_id(assistant_id)
    if not oid:
        return json_error('Invalid assistant ID', 400)

    data = request.get_json(silent=True) or {}
    lat = data.get('lat')
    lng = data.get('lng')

    if lat is None or lng is None:
        return json_error('lat and lng are required', 400)

    mechanics.update_one(
        {"_id": oid},
        {"$set": {"location": {"lat": lat, "lng": lng}}}
    )

    socketio.emit('assistant_location_updated', {
        'success': True,
        'assistantId': assistant_id,
        'lat': lat,
        'lng': lng,
    })

    return jsonify({
        "success": True,
        "message": "Assistant location updated",
        "assistantId": assistant_id,
    }), 200

# =========================
# REQUEST APIs
# =========================
@app.route('/api/rescueRequests', methods=['GET'])
def get_requests():
    """List requests, optionally scoped to one customer.

    Without `phone` this returns everything, which is what the mechanic and
    admin views need. The customer's history screen passes the signed-in
    number; before it did, "My Requests" listed other people's rescues —
    complete with their location and phone number. §38
    """
    phone = (request.args.get('phone') or '').strip()
    limit = request.args.get('limit', type=int) or 200

    query = {}
    if phone:
        digits = ''.join(ch for ch in phone if ch.isdigit())[-10:]
        # Match either storage shape: the exact value typed, or the last 10
        # digits when one side carries a country code.
        query = {'$or': [
            {'phone': phone},
            {'phone': {'$regex': digits + '$'}} if digits else {'phone': phone},
        ]}

    docs = rescue_requests.find(query).sort('createdAt', -1).limit(min(limit, 500))
    return jsonify([serialize_request(d) for d in docs]), 200

@app.route('/api/rescueRequests/available', methods=['GET'])
def get_available_requests():
    docs = rescue_requests.find({
        "$or": [
            {"status": "Pending"},
            {"status": "pending"}
        ],
        # A job already claimed by a rider must not be offered to that rider
        # again: it appeared in "Active Pickups" and in "Available Nearby" at the
        # same time, which also let two riders accept the same request.
        "$and": [
            {"$or": [{"assistantId": {"$exists": False}},
                     {"assistantId": None},
                     {"assistantId": ""}]}
        ],
    }).sort('createdAt', -1)

    return jsonify([serialize_request(d) for d in docs]), 200

@app.route('/api/rescueRequests/<request_id>', methods=['GET'])
def get_request(request_id):
    oid = safe_object_id(request_id)
    if not oid:
        return json_error('Invalid request ID', 400)

    doc = rescue_requests.find_one({'_id': oid})
    if not doc:
        return json_error('Request not found', 404)

    return jsonify(serialize_request(doc)), 200

@app.route('/api/rescueRequests', methods=['POST'])
def create_request():
    data = request.get_json(silent=True) or {}

    # ── Validation (§38) ────────────────────────────────────────────────
    name = str(data.get('name', '')).strip()
    phone = str(data.get('phone', '')).strip()
    issue = str(data.get('issue', '')).strip()
    vehicle = str(data.get('vehicle', '')).strip()

    if not issue:
        return json_error('issue is required', 400)
    if not name and not phone:
        return json_error('A name or phone number is required', 400)

    location = data.get('location') or {}
    coords = allocation.coerce_coordinate(
        location.get('lat') if isinstance(location, dict) else None,
        location.get('lng') if isinstance(location, dict) else None,
    )
    if coords is None:
        return json_error(
            'A valid location with lat/lng is required '
            '(lat -90..90, lng -180..180)', 400
        )
    lat, lng = coords

    # ── Duplicate guard (§40) ───────────────────────────────────────────
    # Prevent a double-tap or a retry from creating two rescue requests.
    if phone:
        cutoff = datetime.utcnow() - timedelta(
            seconds=Config.DUPLICATE_REQUEST_WINDOW_SECONDS
        )
        open_states = [
            sm.CREATED, sm.SEARCHING, sm.MECHANIC_ASSIGNED, sm.MECHANIC_ACCEPTED,
            sm.MECHANIC_EN_ROUTE, sm.ARRIVED, sm.SERVICE_STARTED,
            'Pending', 'pending', 'Searching', 'Assigned', 'Accepted',
        ]
        existing = rescue_requests.find_one({
            'phone': phone,
            'issue': issue,
            'status': {'$in': open_states},
            'createdAt': {'$gte': cutoff},
        })
        if existing:
            payload = serialize_request(existing)
            return jsonify({
                'success': False,
                'message': (
                    'A rescue request for this issue was already created '
                    'moments ago. Use the existing request instead of '
                    'creating a duplicate.'
                ),
                'code': 'DUPLICATE_REQUEST',
                'request': payload,
                'requestId': str(existing['_id']),
            }), 409

    # ── Resolve the regional hub for this location (§16) ────────────────
    region = None
    try:
        region = allocation.resolve_region(
            list(rq_db.regions().find({})), lat, lng
        )
    except PyMongoError:
        log.warning('Region lookup failed; continuing without a region')

    doc = {
        'name': name,
        'phone': phone,
        'issue': issue,
        'vehicle': vehicle,
        'locationText': data.get('locationText', ''),
        'location': {'lat': lat, 'lng': lng},
        # Canonical lifecycle state. §14
        'status': sm.CREATED,
        'mechanicId': '',
        'mechanicName': '',
        'mechanicLocation': {},
        'distanceKm': 0,
        # 2-person crew (Milestone 1)
        'assistantId': '',
        'assistantName': '',
        'assistantLocation': {},
        'assistantStatus': 'pending',
        # Regional attribution
        'regionId': str(region.get('_id')) if region else None,
        'regionName': region.get('name') if region else None,
        'hubId': str(region.get('hubId')) if region and region.get('hubId') else None,
        # Service detail
        'vehicleDetails': data.get('vehicleDetails', ''),
        'issueDescription': data.get('issueDescription', ''),
        'imageUrl': data.get('imageUrl', ''),
        'userId': data.get('userId', ''),
        'createdAt': datetime.utcnow(),
        'updatedAt': datetime.utcnow(),
    }

    try:
        result = rescue_requests.insert_one(doc)
    except PyMongoError as exc:
        return json_error(f'Database error: {exc}', 500)

    doc['_id'] = result.inserted_id

    payload = serialize_request(doc)
    realtime.emit_event('new_request', payload)

    return jsonify({
        'success': True,
        'message': 'Rescue request created successfully',
        'request': payload
    }), 201

@app.route('/api/rescueRequests/<request_id>/assign', methods=['PUT'])
def assign_request(request_id):
    oid = safe_object_id(request_id)
    if not oid:
        return json_error('Invalid request ID', 400)

    data = request.get_json(silent=True) or {}
    mechanic_id = data.get('mechanicId', '').strip()
    mechanic_name = data.get('mechanicName', '').strip()

    if not mechanic_id:
        return json_error('mechanicId is required', 400)

    result = rescue_requests.update_one(
        {'_id': oid},
        {'$set': {
            'status': 'Assigned',
            'mechanicId': mechanic_id,
            'mechanicName': mechanic_name,
        }}
    )

    if result.matched_count == 0:
        return json_error('Request not found', 404)

    doc = rescue_requests.find_one({'_id': oid})
    payload = serialize_request(doc)

    socketio.emit('request_assigned', {
        'success': True,
        'requestId': request_id,
        'mechanicId': mechanic_id,
        'status': 'Assigned',
    })

    socketio.emit('status_updated', {
        'success': True,
        'requestId': request_id,
        'mechanicId': mechanic_id,
        'status': 'Assigned',
    })

    return jsonify({
        'success': True,
        'message': 'Mechanic assigned successfully',
        'request': payload
    }), 200

@app.route('/api/rescueRequests/<request_id>/status', methods=['PUT'])
def update_status(request_id):
    oid = safe_object_id(request_id)
    if not oid:
        return json_error('Invalid request ID', 400)

    data = request.get_json(silent=True) or {}
    status = data.get('status')

    if not status:
        return json_error('status is required', 400)

    existing = rescue_requests.find_one({'_id': oid})
    if not existing:
        return json_error('Request not found', 404)

    # Transition validation. The old handler stored whatever string it was
    # given, which allowed a request to jump backwards or into states that do
    # not exist. The lifecycle graph now decides. §14, §38
    verdict = sm.validate_transition(existing.get('status'), status)
    if not verdict['ok']:
        body = err_json(verdict['reason'], 409)
        body['from'] = verdict['from']
        body['allowedNextStates'] = verdict['allowed']
        return jsonify(body), 409

    updates = {
        # Persist the label the existing Flutter UI already renders, and store
        # the canonical state alongside it for the state machine and reports.
        'status': sm.storage_label(verdict['to']),
        'statusCanonical': verdict['to'],
        'updatedAt': datetime.utcnow(),
    }

    # Stamp lifecycle timestamps so the research export can compute real
    # durations instead of relying on the client. §44
    stamp_field = {
        sm.MECHANIC_ACCEPTED: 'acceptedAt',
        sm.MECHANIC_EN_ROUTE: 'enRouteAt',
        sm.ARRIVED: 'arrivedAt',
        sm.SERVICE_STARTED: 'serviceStartedAt',
        sm.SERVICE_COMPLETED: 'serviceCompletedAt',
        sm.CANCELLED: 'cancelledAt',
    }.get(verdict['to'])
    if stamp_field and not existing.get(stamp_field):
        updates[stamp_field] = datetime.utcnow()

    result = rescue_requests.update_one({'_id': oid}, {'$set': updates})

    if result.matched_count == 0:
        return json_error('Request not found', 404)

    doc = rescue_requests.find_one({'_id': oid})
    payload = serialize_request(doc)

    realtime.emit_event('status_updated', {
        'success': True,
        'requestId': request_id,
        'id': request_id,
        'status': verdict['to'],
        'progressPercent': sm.progress_percent(verdict['to']),
        'mechanicId': payload.get('mechanicId', '')
    })

    # The rider's own clients subscribe to `assistant_status_updated`; without
    # this emit that handler could never fire and the assistant list only
    # updated when the screen happened to be rebuilt.
    if payload.get('assistantId'):
        realtime.emit_event('assistant_status_updated', {
            'success': True,
            'requestId': request_id,
            'assistantId': payload.get('assistantId', ''),
            'status': verdict['to'],
        })

    return jsonify({
        'success': True,
        'message': 'Status updated successfully',
        'request': payload
    }), 200

@app.route('/api/rescueRequests/<request_id>/assign-assistant', methods=['PUT'])
def assign_assistant_http(request_id):
    oid = safe_object_id(request_id)
    if not oid:
        return json_error('Invalid request ID', 400)

    data = request.get_json(silent=True) or {}
    assistant_id = data.get('assistantId', '').strip()
    assistant_name = data.get('assistantName', '').strip()

    if not assistant_id:
        return json_error('assistantId is required', 400)

    current = rescue_requests.find_one({'_id': oid})
    if not current:
        return json_error('Request not found', 404)

    update = {
        'assistantId': assistant_id,
        'assistantName': assistant_name,
        'assistantStatus': 'assigned',
    }

    # Accepting a pickup is an acceptance, so the request has to leave CREATED.
    # Leaving it at CREATED/PENDING gave the rider no legal next step: the state
    # machine offers nothing after CREATED on the field path, so the job could
    # never start moving. Only lift untouched requests — never downgrade a job
    # the mechanic has already advanced.
    lift_to_accepted = sm.normalize(current.get('status', '')) in {
        sm.CREATED, sm.SEARCHING,
    }
    if lift_to_accepted:
        update['status'] = sm.storage_label(sm.MECHANIC_ACCEPTED)
        update['statusCanonical'] = sm.MECHANIC_ACCEPTED
        update['acceptedAt'] = datetime.utcnow()

    rescue_requests.update_one({'_id': oid}, {'$set': update})

    doc = rescue_requests.find_one({'_id': oid})
    payload = serialize_request(doc)

    if lift_to_accepted:
        socketio.emit('status_updated', {
            'success': True,
            'requestId': request_id,
            'id': request_id,
            'status': payload.get('status'),
            'progressPercent': sm.progress_percent(sm.MECHANIC_ACCEPTED),
            'mechanicId': payload.get('mechanicId', ''),
            'assistantId': assistant_id,
        })

    socketio.emit('assistant_assigned', {
        'success': True,
        'requestId': request_id,
        'assistantId': assistant_id,
        'assistantName': assistant_name,
    })

    return jsonify({
        'success': True,
        'message': 'Assistant assigned successfully',
        'request': payload,
    }), 200


@app.route('/api/rescueRequests/<request_id>/assistant-location', methods=['PUT'])
def assistant_location_http(request_id):
    oid = safe_object_id(request_id)
    if not oid:
        return json_error('Invalid request ID', 400)

    data = request.get_json(silent=True) or {}
    assistant_id = data.get('assistantId', '').strip()
    lat = data.get('lat')
    lng = data.get('lng')

    if not assistant_id:
        return json_error('assistantId is required', 400)
    if lat is None or lng is None:
        return json_error('lat and lng are required', 400)

    rescue_requests.update_one(
        {'_id': oid},
        {'$set': {
            'assistantLocation': {
                'lat': lat,
                'lng': lng
            },
            'assistantStatus': data.get('assistantStatus', 'active')
        }}
    )

    socketio.emit('assistant_location_updated', {
        'success': True,
        'assistantId': assistant_id,
        'requestId': request_id,
        'lat': lat,
        'lng': lng,
    })

    return jsonify({
        'success': True,
        'message': 'Assistant location updated'
    }), 200


@app.route('/api/rescueRequests/<request_id>/mechanic-location', methods=['PUT'])
def update_location(request_id):
    oid = safe_object_id(request_id)
    if not oid:
        return json_error('Invalid request ID', 400)

    data = request.get_json(silent=True) or {}
    lat = data.get('lat')
    lng = data.get('lng')

    if lat is None or lng is None:
        return json_error('lat and lng are required', 400)

    result = rescue_requests.update_one(
        {'_id': oid},
        {'$set': {
            'mechanicLocation': {
                'lat': lat,
                'lng': lng
            }
        }}
    )

    if result.matched_count == 0:
        return json_error('Request not found', 404)

    return jsonify({
        'success': True,
        'message': 'Mechanic location updated'
    }), 200

# =========================
# ADMIN - TOKEN MANAGEMENT
# =========================
@app.route('/api/admin/tokens', methods=['GET'])
def admin_get_tokens():
    # Serialized through the shared serializer so sensitive fields can never be
    # echoed back, and the two date fields are rendered consistently. §39
    try:
        docs = rq_db.tokens().find().sort('createdAt', -1).limit(500)
        return jsonify([serialize_token(d) for d in docs]), 200
    except PyMongoError as exc:
        return json_error(f'Database error: {exc}', 500)

@app.route('/api/admin/tokens', methods=['POST'])
def admin_create_token():
    data = request.get_json(silent=True) or {}
    tokens_collection = db["tokens"]
    doc = {
        "vehicleId": data.get("vehicleId", ""),
        "userId": data.get("userId", ""),
        "jobId": data.get("jobId", ""),
        "hubId": data.get("hubId", ""),
        "status": "created",
        "createdAt": datetime.utcnow(),
        "updatedAt": datetime.utcnow(),
    }
    result = tokens_collection.insert_one(doc)
    doc["_id"] = str(result.inserted_id)
    doc["id"] = str(result.inserted_id)
    doc["createdAt"] = doc["createdAt"].isoformat()
    doc["updatedAt"] = doc["updatedAt"].isoformat()
    return jsonify({"success": True, "token": doc}), 201

@app.route('/api/admin/tokens/<token_id>/status', methods=['PUT'])
def admin_update_token_status(token_id):
    tokens_collection = db["tokens"]
    try:
        oid = ObjectId(token_id)
    except:
        return json_error("Invalid token ID", 400)
    data = request.get_json(silent=True) or {}
    status = data.get("status", "")
    if not status:
        return json_error("Status is required", 400)
    tokens_collection.update_one(
        {"_id": oid},
        {"$set": {"status": status, "updatedAt": datetime.utcnow()}}
    )
    return jsonify({"success": True, "message": "Token status updated"}), 200

@app.route('/api/admin/tokens/<token_id>/release', methods=['PUT'])
def admin_release_token(token_id):
    tokens_collection = db["tokens"]
    try:
        oid = ObjectId(token_id)
    except:
        return json_error("Invalid token ID", 400)
    data = request.get_json(silent=True) or {}
    tokens_collection.update_one(
        {"_id": oid},
        {"$set": {
            "status": "released",
            "releasedBy": data.get("releasedBy", ""),
            "releasedAt": datetime.utcnow(),
            "updatedAt": datetime.utcnow()
        }}
    )
    return jsonify({"success": True, "message": "Token released"}), 200

# =========================
# ADMIN - ZONE MANAGEMENT
# =========================
@app.route('/api/zones', methods=['GET'])
def client_get_zones():
    """Read-only zone list for clients (urban/rural security geofences).

    The app used to read the Firestore `zones` collection here, which it cannot
    read at all: there is no Firebase Auth session (logins go through this
    backend), so every rule beginning with isAuthenticated() denies it, and
    ZoneSecurityService logged "PERMISSION_DENIED: Check Firestore Rules" on
    every SOS submission.

    Mirrors /api/admin/zones, which stays write-capable and admin-facing.
    Returns an empty list today — the Mongo `zones` collection has no documents
    — and `checkZone` falls back to the conservative 'rural' classification.
    """
    result = []
    for d in db["zones"].find().sort('name', 1):
        d["_id"] = str(d["_id"])
        d["id"] = str(d["_id"])
        result.append(d)

    return jsonify(result), 200


@app.route('/api/admin/zones', methods=['GET'])
def admin_get_zones():
    zones_collection = db["zones"]
    docs = zones_collection.find().sort('name', 1)
    result = []
    for d in docs:
        d["_id"] = str(d["_id"])
        d["id"] = str(d["_id"])
        result.append(d)
    return jsonify(result), 200

@app.route('/api/admin/zones', methods=['POST'])
def admin_create_zone():
    data = request.get_json(silent=True) or {}
    zones_collection = db["zones"]
    doc = {
        "name": data.get("name", ""),
        "latMin": data.get("latMin", 0),
        "latMax": data.get("latMax", 0),
        "lngMin": data.get("lngMin", 0),
        "lngMax": data.get("lngMax", 0),
        "createdAt": datetime.utcnow(),
    }
    result = zones_collection.insert_one(doc)
    doc["_id"] = str(result.inserted_id)
    doc["id"] = str(result.inserted_id)
    return jsonify({"success": True, "zone": doc}), 201

@app.route('/api/admin/zones/<zone_id>', methods=['DELETE'])
def admin_delete_zone(zone_id):
    zones_collection = db["zones"]
    try:
        oid = ObjectId(zone_id)
    except:
        return json_error("Invalid zone ID", 400)
    zones_collection.delete_one({"_id": oid})
    return jsonify({"success": True, "message": "Zone deleted"}), 200

# =========================
# ADMIN - USER MANAGEMENT
# =========================
@app.route('/api/admin/users', methods=['GET'])
def admin_get_users():
    docs = users.find().sort('createdAt', -1)
    result = []
    for d in docs:
        d["_id"] = str(d["_id"])
        d["id"] = str(d["_id"])
        if "password" in d:
            del d["password"]
        if "createdAt" in d and d["createdAt"]:
            d["createdAt"] = d["createdAt"].isoformat() if hasattr(d["createdAt"], 'isoformat') else str(d["createdAt"])
        result.append(d)
    return jsonify(result), 200

@app.route('/api/admin/users/<user_id>', methods=['DELETE'])
def admin_delete_user(user_id):
    oid = safe_object_id(user_id)
    if not oid:
        return json_error('Invalid user ID', 400)
    result = users.delete_one({"_id": oid})
    if result.deleted_count == 0:
        return json_error("User not found", 404)
    return jsonify({"success": True, "message": "User deleted"}), 200

@app.route('/api/admin/tokens/<token_id>', methods=['DELETE'])
def admin_delete_token(token_id):
    tokens_collection = db["tokens"]
    try:
        oid = ObjectId(token_id)
    except:
        return json_error("Invalid token ID", 400)
    result = tokens_collection.delete_one({"_id": oid})
    if result.deleted_count == 0:
        return json_error("Token not found", 404)
    return jsonify({"success": True, "message": "Token deleted"}), 200

# =========================
# ADMIN
# =========================
@app.route('/api/admin/requests', methods=['GET'])
def admin_requests():
    docs = rescue_requests.find().sort('createdAt', -1)
    return jsonify([serialize_request(d) for d in docs]), 200

@app.route('/api/admin/hubs', methods=['GET'])
def admin_hubs():
    docs = hubs.find().sort('createdAt', -1)
    return jsonify([serialize_hub(d) for d in docs]), 200

@app.route('/api/admin/mechanics', methods=['GET'])
def admin_mechanics():
    docs = mechanics.find().sort('createdAt', -1)
    return jsonify([serialize_mechanic(d) for d in docs]), 200

@app.route('/api/admin/assign-mechanic', methods=['PUT'])
def admin_assign_mechanic():
    data = request.get_json(silent=True) or {}
    request_id = data.get('requestId', '').strip()
    mechanic_id = data.get('mechanicId', '').strip()

    if not request_id or not mechanic_id:
        return json_error('requestId and mechanicId are required', 400)

    oid = safe_object_id(request_id)
    mid = safe_object_id(mechanic_id)

    if not oid:
        return json_error('Invalid requestId', 400)

    mechanic = mechanics.find_one({"_id": mid}) if mid else None
    mechanic_name = mechanic.get('name', '') if mechanic else ''

    result = rescue_requests.update_one(
        {'_id': oid},
        {'$set': {
            'status': 'Assigned',
            'mechanicId': mechanic_id,
            'mechanicName': mechanic_name,
        }}
    )

    if result.matched_count == 0:
        return json_error('Request not found', 404)

    doc = rescue_requests.find_one({'_id': oid})
    payload = serialize_request(doc)

    socketio.emit('request_assigned', {
        'success': True,
        'requestId': request_id,
        'mechanicId': mechanic_id,
        'status': 'Assigned',
    })

    socketio.emit('status_updated', {
        'success': True,
        'requestId': request_id,
        'mechanicId': mechanic_id,
        'status': 'Assigned',
    })

    return jsonify({
        'success': True,
        'message': 'Mechanic assigned by admin',
        'request': payload
    }), 200

@app.route('/api/rescueRequests/<request_id>/payment', methods=['PUT'])
def update_payment(request_id):
    oid = safe_object_id(request_id)
    if not oid:
        return json_error('Invalid request ID', 400)

    data = request.get_json(silent=True) or {}

    amount = data.get('amount', 0)
    payment_status = data.get('paymentStatus', '').strip()
    payment_id = data.get('paymentId', '').strip()
    payment_method = data.get('paymentMethod', '').strip()

    if not payment_status:
        return json_error('paymentStatus is required', 400)

    doc = rescue_requests.find_one({'_id': oid})
    if not doc:
        return json_error('Request not found', 404)

    # Money arriving IS the payment event, so it has to move the state machine.
    # This route used to write `amount` and `paymentStatus` and leave `status`
    # at SERVICE_COMPLETED, which dead-ended the whole workflow: /api/ratings
    # only accepts PAYMENT_COMPLETED, so the customer could pay and then never
    # rate, and the job never closed. Payment covers both PAYMENT_PENDING and
    # PAYMENT_COMPLETED because it is one atomic event from the payer's side.
    current = sm.normalize(doc.get('status'))
    patch = {
        'amount': amount,
        'paymentStatus': payment_status,
        'paymentId': payment_id,
        'paymentMethod': payment_method,
        'paidAt': datetime.utcnow() if payment_status == 'success' else None,
    }

    paid_tokens = {'success', 'paid', 'completed', 'captured'}
    failed_tokens = {'failed', 'failure', 'declined', 'cancelled'}

    advanced_to = None
    if payment_status.lower() in paid_tokens:
        if current in (sm.SERVICE_COMPLETED, sm.PAYMENT_PENDING):
            advanced_to = sm.PAYMENT_COMPLETED
    elif payment_status.lower() in failed_tokens:
        if current == sm.PAYMENT_PENDING:
            advanced_to = sm.PAYMENT_FAILED

    if advanced_to:
        patch['status'] = sm.storage_label(advanced_to)
        patch['statusCanonical'] = advanced_to

    result = rescue_requests.update_one({'_id': oid}, {'$set': patch})

    if result.matched_count == 0:
        return json_error('Request not found', 404)

    doc = rescue_requests.find_one({'_id': oid})
    payload = serialize_request(doc)

    if advanced_to:
        # Every role screen listens for this; without it the customer's tracker
        # kept showing "Service completed" after a successful payment.
        realtime.emit_event('status_updated', {
            'success': True,
            'requestId': request_id,
            'id': request_id,
            'status': advanced_to,
            'progressPercent': sm.progress_percent(advanced_to),
            'mechanicId': payload.get('mechanicId', ''),
        })

    socketio.emit('payment_updated', {
        'success': True,
        'requestId': request_id,
        'paymentStatus': payment_status,
        'paymentId': payment_id,
        'amount': amount,
    })

    return jsonify({
        'success': True,
        'message': 'Payment updated successfully',
        'request': payload,
    }), 200

# =========================
# SOCKET EVENTS
# =========================
@socketio.on('connect')
def socket_connect():
    # No emoji here on purpose: this handler is on the critical path, and a
    # non-encodable character used to abort it before the acknowledgement.
    log.info('socket: client connected')
    emit('connected', {'success': True})

@socketio.on('disconnect')
def socket_disconnect():
    log.info('socket: client disconnected')

@socketio.on('mechanic_online')
def mechanic_online(data):
    emit('mechanic_online_updated', {
        'success': True,
        'mechanicId': data.get('mechanicId', ''),
        'name': data.get('name', ''),
        'online': data.get('online', True),
        'isOnline': data.get('online', True),
    }, broadcast=True)

@socketio.on('mechanic_location_update')
def mechanic_location(data):
    payload = {
        'success': True,
        'mechanicId': data.get('mechanicId', ''),
        'requestId': data.get('requestId', ''),
        'lat': data.get('lat'),
        'lng': data.get('lng')
    }

    emit('mechanic_location_updated', payload, broadcast=True)
    emit('mechanic_location_global_updated', payload, broadcast=True)

@socketio.on('accept_request')
def accept_request_socket(data):
    emit('request_assigned', {
        'success': True,
        'requestId': data.get('requestId', ''),
        'mechanicId': data.get('mechanicId', ''),
        'status': 'Accepted'
    }, broadcast=True)

    emit('status_updated', {
        'success': True,
        'requestId': data.get('requestId', ''),
        'mechanicId': data.get('mechanicId', ''),
        'status': 'Accepted'
    }, broadcast=True)

@socketio.on('complete_request')
def complete_request_socket(data):
    emit('status_updated', {
        'success': True,
        'requestId': data.get('requestId', ''),
        'mechanicId': data.get('mechanicId', ''),
        'status': 'Completed'
    }, broadcast=True)

# =========================
# ASSISTANT SOCKET EVENTS (Milestone 1)
# =========================
@socketio.on('assign_assistant')
def assign_assistant_socket(data):
    emit('assistant_assigned', {
        'success': True,
        'requestId': data.get('requestId', ''),
        'assistantId': data.get('assistantId', ''),
        'status': 'Assistant Assigned',
    }, broadcast=True)

@socketio.on('assistant_location_update')
def assistant_location_update_socket(data):
    payload = {
        'success': True,
        'assistantId': data.get('assistantId', ''),
        'requestId': data.get('requestId', ''),
        'lat': data.get('lat'),
        'lng': data.get('lng'),
    }

    emit('assistant_location_updated', payload, broadcast=True)

@socketio.on('assistant_status_update')
def assistant_status_update_socket(data):
    emit('assistant_status_updated', {
        'success': True,
        'requestId': data.get('requestId', ''),
        'assistantId': data.get('assistantId', ''),
        'assistantStatus': data.get('assistantStatus', 'active'),
    }, broadcast=True)

@socketio.on('new_request_created')
def new_request_created_socket(data):
    emit('new_request', {
        'success': True,
        'requestId': data.get('requestId', ''),
        'name': data.get('name', ''),
        'phone': data.get('phone', ''),
        'vehicle': data.get('vehicle', ''),
        'issue': data.get('issue', ''),
        'locationText': data.get('locationText', ''),
        'location': data.get('location', {}),
        'status': 'Pending'
    }, broadcast=True)

# =========================
# FRONTEND-EMITTED SOCKET EVENTS (gap-fill)
# These events are emitted by the Flutter app but were previously not
# handled server-side, so the workflow never updated other clients.
# =========================
@socketio.on('new_request')
def frontend_new_request(data):
    print('📥 socket new_request:', data)
    emit('new_request', {
        'success': True,
        'requestId': data.get('requestId', data.get('id', '')),
        'id': data.get('requestId', data.get('id', '')),
        'name': data.get('userName', data.get('name', '')),
        'phone': data.get('userPhone', data.get('phone', '')),
        'vehicle': data.get('vehicle', ''),
        'issue': data.get('issue', ''),
        'locationText': data.get('address', data.get('locationText', '')),
        'lat': data.get('lat', 0),
        'lng': data.get('lng', 0),
        'status': 'Pending'
    }, broadcast=True)

@socketio.on('status_updated')
def frontend_status_updated(data):
    print('📥 socket status_updated:', data)
    payload = {
        'success': True,
        'requestId': data.get('requestId', ''),
        'id': data.get('requestId', ''),
        'mechanicId': data.get('mechanicId', ''),
        'assistantId': data.get('assistantId', ''),
        'status': data.get('status', ''),
        'jobId': data.get('jobId', ''),
    }
    emit('status_updated', payload, broadcast=True)
    emit('request_assigned', payload, broadcast=True)

@socketio.on('request_assigned')
def frontend_request_assigned(data):
    print('📥 socket request_assigned:', data)
    payload = {
        'success': True,
        'requestId': data.get('requestId', ''),
        'id': data.get('requestId', ''),
        'mechanicId': data.get('mechanicId', ''),
        'status': data.get('status', 'Assigned'),
    }
    emit('request_assigned', payload, broadcast=True)
    emit('status_updated', payload, broadcast=True)

@socketio.on('payment_updated')
def frontend_payment_updated(data):
    print('📥 socket payment_updated:', data)
    emit('payment_updated', {
        'success': True,
        'requestId': data.get('requestId', ''),
        'paymentStatus': data.get('paymentStatus', ''),
        'paymentId': data.get('paymentId', ''),
        'amount': data.get('amount', 0),
    }, broadcast=True)

@socketio.on('update_location')
def frontend_update_location(data):
    print('📥 socket update_location:', data)
    payload = {
        'success': True,
        'mechanicId': data.get('crewId', data.get('mechanicId', '')),
        'assistantId': data.get('assistantId', ''),
        'requestId': data.get('requestId', data.get('jobId', '')),
        'lat': data.get('lat'),
        'lng': data.get('lng'),
    }
    emit('mechanic_location_updated', payload, broadcast=True)
    emit('mechanic_location_global_updated', payload, broadcast=True)

@socketio.on('crew_online')
def frontend_crew_online(data):
    print('📥 socket crew_online:', data)
    emit('mechanic_online_updated', {
        'success': True,
        'mechanicId': data.get('crewId', ''),
        'name': data.get('name', ''),
        'online': data.get('online', True),
        'isOnline': data.get('online', True),
    }, broadcast=True)

@socketio.on('assistant_online')
def frontend_assistant_online(data):
    print('📥 socket assistant_online:', data)
    emit('assistant_online_updated', {
        'success': True,
        'assistantId': data.get('assistantId', ''),
        'name': data.get('name', ''),
        'online': data.get('online', True),
    }, broadcast=True)

@socketio.on('escalate_request')
def frontend_escalate_request(data):
    print('🚨 socket escalate_request:', data)
    emit('request_escalated', {
        'success': True,
        'requestId': data.get('requestId', ''),
        'reason': data.get('reason', ''),
    }, broadcast=True)

@socketio.on('backup_crew_notification')
def frontend_backup_crew(data):
    print('🆘 socket backup_crew_notification:', data)
    emit('backup_crew_notified', {
        'success': True,
        'requestId': data.get('requestId', ''),
        'crewId': data.get('crewId', ''),
    }, broadcast=True)

# =========================
# RUN
# =========================
# =========================
# API v2 — additive endpoints from the audit remediation
# =========================
# Registered last so every legacy route above keeps priority. api_v2 only
# declares paths that did not previously exist, so no existing URL changes
# behaviour. §37
try:
    from api_v2 import bp as api_v2_bp

    app.register_blueprint(api_v2_bp)
    log.info("API v2 registered (%d new routes)", len(list(api_v2_bp.deferred_functions)))
except Exception as exc:  # pragma: no cover
    log.exception("Failed to register API v2: %s", exc)


# =========================
# Completion modules (uploads, chat, arrival token, attendance, earnings,
# feedback, admin console, escalation watchdog)
# =========================
# Also purely additive: every route in modules_v3 is a new path, so the
# contract the existing screens use is untouched. §18, §30, §33, §38, §39,
# §41, §42, §48, §51, §52
try:
    import modules_v3

    modules_v3.init_app(app, socketio)
except Exception as exc:  # pragma: no cover
    log.exception("Failed to register completion modules: %s", exc)


# =========================
# RUN
# =========================
if __name__ == '__main__':
    log.info(
        "RoadResQ backend starting on %s:%s (debug=%s, dev_mode=%s)",
        Config.HOST, Config.PORT, Config.DEBUG, Config.DEV_MODE,
    )
    if not Config.DEV_MODE:
        log.info("Development OTP and instant access are DISABLED")
    if not Config.payments_enabled():
        log.warning(
            "Razorpay credentials absent — payment orders will be SIMULATED "
            "and clearly flagged as such"
        )

    # Server-side escalation (§52): a request nobody accepts is escalated by the
    # backend after the configured window, instead of relying on a client timer
    # that stops the moment the app is backgrounded.
    try:
        import modules_v3

        modules_v3.start_escalation_watchdog()
    except Exception as exc:  # pragma: no cover
        log.warning("Escalation watchdog not started: %s", exc)

    # Advertise this server on the LAN so the app can find it after the
    # machine's address changes. Without it the client has to be told an IP,
    # and that address dies with the next DHCP lease — which is the recurring
    # "SocketException: No route to host" the app used to loop on.
    # One live code per phone+purpose; also keeps a stale duplicate from
    # shadowing a fresh code.
    try:
        otp_service.ensure_indexes()
    except Exception as exc:  # boot must not fail on an index hiccup
        log.warning("OTP index setup skipped: %s", exc)

    if os.getenv("ROADRESQ_BEACON", "1").strip().lower() not in {"0", "false", "no", "off"}:
        try:
            from beacon import Beacon

            Beacon(Config.PORT).start()
        except Exception as exc:  # never let discovery break the server
            log.warning("LAN beacon not started: %s", exc)

    socketio.run(
        app,
        host=Config.HOST,
        port=Config.PORT,
        debug=Config.DEBUG,
        allow_unsafe_werkzeug=True,
    )