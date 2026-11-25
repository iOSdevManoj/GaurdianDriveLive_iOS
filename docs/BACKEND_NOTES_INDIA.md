# Backend notes — India launch (for the backend developer)

The iOS changes are on branch `claude/india-battery-fixes`. **No API contract was changed**: same endpoints, same fields, same units (speed is still MPH). Please confirm or handle the points below.

## 1. Phone numbers (+91)
- Phone screens now preselect the phone's own country (India → `+91`), falling back to the US (`+1`). The app sends `countryCode` as before, e.g. `"+91"`, and `mobileNo` as 10 digits.
- Please confirm:
  - OTP SMS delivery to Indian numbers works (SMS provider, DLT/sender ID registration for India if your provider needs it).
  - Resend and rate limits.
  - Login with an existing account matches on `countryCode` + `mobileNo`.
- **Behaviour change to be aware of:** on Basic Info (email or social sign-up), the country code used to be sent as an **empty string** when the user typed a phone number. It now sends the selected code (`"+1"` or `"+91"`). Please make sure the API accepts this and stores it.

## 2. Subscriptions (INR)
- The app now shows the App Store's local price (₹ in India). Product ids are **unchanged** (the 8 existing monthly/yearly products).
- Please confirm `parent/apple/transaction/verify` and renewal/refund handling work for India storefront transactions (currency `INR`, storefront `IND`). Don't hardcode USD amounts in verification or entitlement logic.

## 3. Time zone (+05:30)
- The app sends `timeZoneOffset` in minutes at login/registration. India is **+330** (a half-hour offset).
- The server builds `localTime` / `localAaddedTime` for reports and the parent's "last updated" label from this offset. Please confirm half-hour offsets are handled (not rounded to whole hours).
- No-Drive schedule start/end times are sent and expected as ISO-8601 **UTC** — no change.

## 4. Location uploads (battery fix) — please answer
- While a child's phone has been **parked for more than 5 minutes**, it now goes into low-power location and **sends no location uploads until it moves** (about 50 m). Before, it uploaded about every 5 seconds even when parked. While moving, uploads are every 5 seconds, unchanged.
- **Question:** does the backend raise any alert, a "tampered" or "offline" status, or a notification when no location arrives from a child for some time? If yes, tell us the timeout. Long parked periods without uploads must not trigger it.
- The parent's "last updated" time will show when the child last moved (the location shown is still correct).
- `driveMode` values sent are unchanged: `"Normal"`, `"Drive mode active"`, `"No-Drive mode active"`.

## 5. Drive-mode speed
- The drive-mode trigger stays **15 mph (≈ 24 km/h)** for all countries. It is not read from the server.
- `speedAlertThreshold` is still only used for alert notifications. No change is needed.

## 6. Data / privacy (for the release checklist)
- Please document where location, account and child data are stored (region), retention, and that account deletion also removes child and location records.
