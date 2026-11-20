# Turning on real SMS for login codes

The app no longer accepts a fixed `1234`. Every login now issues a random
6-digit code that expires in 5 minutes, allows 5 attempts and cannot be reused
(`backend/otp.py`). What is still missing is **delivery**: with no provider
configured, the backend says so (`"smsSent": false`) and returns the code in the
`devOtp` field so development keeps working.

Fill in **one** provider below, restart the backend, and codes go out by SMS.
No new Python package is needed.

## 1. Choose a provider

| Provider | Best for | What you need |
|---|---|---|
| MSG91 | India, cheapest per OTP | Auth key + DLT-approved OTP template |
| Fast2SMS | India, quick setup | API key (and DLT registration for production) |
| Twilio | Any country, easiest trial | Account SID, auth token, a sender number |

India requires DLT registration for transactional SMS. MSG91 and Fast2SMS both
walk you through it; without it, messages to Indian numbers are filtered by the
operators, not by this app.

## 2. Set the variables

Create `backend/.env` (or set them in the environment) using
[backend/.env.example](backend/.env.example) as the template:

```ini
# MSG91
SMS_PROVIDER=msg91
MSG91_AUTH_KEY=xxxxxxxxxxxxxxxxxxxx
MSG91_TEMPLATE_ID=xxxxxxxxxxxxxxxxxxxx
```

```ini
# Twilio
SMS_PROVIDER=twilio
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=xxxxxxxxxxxxxxxx
TWILIO_FROM=+1xxxxxxxxxx
```

```ini
# Fast2SMS
SMS_PROVIDER=fast2sms
FAST2SMS_API_KEY=xxxxxxxxxxxxxxxx
```

Then restart:

```powershell
.\start_backend.ps1 -Restart
```

## 3. Confirm it is live

```powershell
Invoke-RestMethod http://127.0.0.1:5050/api/system/sms-status | ConvertTo-Json -Depth 4
```

`configured: true` with your provider name means the next login will attempt a
real send. A send that the provider rejects comes back as `smsSent: false` with
the provider's error in `detail`; the app then shows the code only if
`ROADRESQ_DEV_MODE` is on.

## 4. Turn off the development fallback

Once SMS works, set:

```ini
ROADRESQ_DEV_MODE=off
```

Now a failed send returns HTTP 502 instead of leaking the code to the client,
and the code exists only in the SMS. Do not set this before delivery works, or
nobody can log in.

## Abuse limits (already enforced)

| Limit | Default | Where |
|---|---|---|
| Code lifetime | 300 s | `ROADRESQ_OTP_TTL_SECONDS` |
| Wrong attempts per code | 5, then the code is destroyed | `ROADRESQ_OTP_MAX_ATTEMPTS` |
| Resend cooldown | 30 s | `ROADRESQ_OTP_RESEND_SECONDS` |
| Codes per number per hour | 8, shared across all four login forms | `ROADRESQ_OTP_MAX_PER_HOUR` |

Exceeding the hourly cap returns HTTP 429 with the minutes remaining, and the
counter is **not** reset by a successful login — otherwise a resolved code would
refill the budget. `/api/system/sms-status` reports the active value as
`otp.maxPerHour`. `0` disables the cap; do not do that on a public deployment.

## What is still not production-grade

- No delivery receipts: `smsSent` means the provider's API accepted the message.
- Single provider per deployment (no automatic failover between providers).
- The cap is per phone number, not per IP or per device, so a determined
  attacker can still send one code to many numbers.
