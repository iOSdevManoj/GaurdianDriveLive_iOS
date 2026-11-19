# Guardian Drive: India Launch and Child Battery Review

**Review date:** 5 November 2026  
**Scope:** iOS source/configuration in this checkout; App Store and India requirements checked against current official sources. No source code was changed and no build/device energy test was run.

## Executive summary

The app is not fully India-ready as currently configured. There is no obvious need to replace the API hostname solely because the market is changing, but the app has US defaults in phone entry, USD prices in the subscription UI, and a fixed 15 mph driving/shield trigger. These should be resolved before an India release. App Store availability, territory pricing, product-page localization, privacy declarations, and Family Controls distribution entitlement status are primarily App Store Connect/account tasks rather than code edits.

The strongest code-level explanation for the child battery complaint is continuous, navigation-grade GPS with no distance filter and automatic pausing disabled. This runs as soon as the logged-in app starts location updates, including while stationary and potentially for the parent role. The child location callback also rebuilds a 30 m geofence on every fix and can upload location at a five-second interval. These choices create sustained GPS and radio activity. The code supports a likely cause, but actual attribution and battery impact must be confirmed on the affected iPhone with Xcode Energy Log/Instruments and iOS Battery settings.

## India readiness findings

### Code changes to plan

| Priority | Finding | Evidence and impact | Suggested change |
|---|---|---|---|
| High | US is the default country in phone entry | `LoginRegisterVC.swift` line 142; `InvitationLinkVC.swift` line 55; `BasicInfoVC.swift` lines 105–109; `AddChildVC.swift` lines 70 and 84–87. This is five US default/fallback call sites across four screens. Indian users can choose India, but the initial country/flag/code can be wrong. | Use the user's selected/account country or a sensible region default (e.g. `Locale.current.region`) consistently. Preserve an explicit saved country code during edits; do not infer it from the phone number alone. Test OTP, invite and child edit flows with `+91`. |
| High | Subscription cards display static USD amounts | `SubscriptionListVC.swift` lines 77–83 builds plans with hardcoded `$6.99`–`$104.99` strings; the card view uses those strings at lines 910–911. StoreKit products are fetched elsewhere, but the displayed plan price here comes from the static strings. India storefront customers may see USD or a value inconsistent with the actual charge. | Configure INR territory prices in App Store Connect and render the fetched StoreKit `Product.displayPrice` for the selected product. Keep plan names/child counts separate from price formatting. Confirm renewal period and terms are visible. |
| High | Driving/shield trigger is fixed at 15 mph | `AppBlockerManager.swift` lines 674–684 sets 15 mph for all users. The location manager also falls back to 15 at lines 303–305. The app's speed-unit preference (`Helper.swift`, `SpeedUnit`) changes display, not the internal threshold. Thus India's km/h UI does not make the trigger India-appropriate; 15 mph is about 24.1 km/h. | Have the backend return an account/market policy threshold, define its unit explicitly, convert once to the app's internal unit, and use that same source for child shielding, parent UI and location payload. Choose the threshold from the product/safety requirement, not from locale alone. |
| Medium | No app-owned localization resources were found | The project has storyboard resources but no app `Localizable.strings`/language bundles in the inspected file list. Much of the UI is English literals. | Confirm the intended India language scope. At minimum review English-for-India wording, number/date formats and Hindi support if required. Add localization resources and test long/transliterated strings if languages are in scope. |

### Backend/API work to confirm

The app centralizes its REST and socket URLs at `WebAPIUrl.swift` lines 14–16 and currently uses `https://api.guardiandrive.net/` and its matching WebSocket host. The client sends a phone number plus country code in the OTP requests and child creation requests, so the API contract already carries an international calling code. No region-specific API switching is visible in this iOS code.

Before launch, the backend owner should confirm:

1. `+91` phone normalization, duplicate-account rules, OTP delivery and verification, resend/rate limits, and any SMS provider/template registration needed for Indian delivery.
2. INR subscription catalog/price display fields, StoreKit product identifiers, receipt verification, tax/renewal handling, refunds and subscription entitlements. The app posts Apple transactions to the same API (`parent/apple/transaction/verify`).
3. Date/time semantics: the app sends a timezone offset during registration and displays dates in the device's local timezone in inspected helpers. The API should store timestamps consistently (typically UTC) and return unambiguous timestamps; schedules must be tested with Asia/Kolkata (UTC+05:30), including daylight-saving assumptions (India has none).
4. Service availability/latency from Indian networks, push delivery, maps/Places quota/key restrictions, monitoring, and support/contact channels.
5. Where location and account data are stored, which Firebase/Google/backend processors receive it, retention/deletion behavior, and whether the customer or any applicable rule imposes an India-region hosting requirement. The iOS source cannot establish deployment region or data residency.

### App Store and legal launch checks

- **Territory availability:** India is selected in App Store Connect's App Availability. This is not a code change; Apple allows availability to be managed by country/region. Set a release date if required and confirm the India storefront can download the app. [Apple: Manage app availability](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store)
- **Prices:** Set India storefront prices for the app/IAPs/subscriptions in App Store Connect. StoreKit provides a localized product price string, but the current plan cards bypass it with hardcoded USD strings. [Apple: Set a price](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price), [StoreKit `Product.displayPrice`](https://developer.apple.com/documentation/storekit/product/displayprice)
- **Privacy disclosures:** App Store Connect requires an accurate privacy policy and app privacy declaration including third-party SDK practices. This app processes account/contact data and precise location linked to parent/child accounts; verify Firebase Crashlytics/Messaging, Google Sign-In/Maps/Places, server logs, retention and sharing in the policy and privacy label. Account deletion UI/API appears present in `ProfileVC.swift` and `WebAPIUrl.deleteAccount`; verify server deletion includes child/location records and processors. [Apple: App privacy details](https://developer.apple.com/app-store/app-privacy-details/), [Apple: Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- **Location and background use:** `Info.plist` declares `location`, `remote-notification` and `fetch` background modes. The generated location usage text in `project.pbxproj` says only “get children location tracking by parent,” which should clearly explain ongoing/background collection, purpose, who sees it and how to stop it. Ensure consent is explicit and role-appropriate. Apple's review rules limit background services to their intended purpose and require notice/consent for location collection/use. [Apple App Review Guidelines, 2.5.4, 5.1.1, 5.1.5](https://developer.apple.com/app-store/review/guidelines/)
- **Family Controls:** The app and ReportExtension carry the Family Controls entitlement. Apple's distribution entitlement requires approval by the developer account holder for the app and relevant Screen Time extensions. The source tree cannot confirm that approval is assigned to the current signing account/provisioning profiles. Check Certificates, Identifiers & Profiles before an India release. [Apple: Requesting the Family Controls entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)
- **Age rating/metadata:** Choose the actual audience and age rating in App Store Connect. Do not label it “For Kids/Children” unless it is submitted in Apple's Kids Category; Apple's current guideline reserves such metadata. Provide App Review with a working parent/child test account, QR/invite details and explanation of background location and Screen Time features.
- **India child-data law timeline:** India's DPDP Act and 2025 Rules have phased commencement. The official commencement notification sets Sections 3–17 (including child-data Section 9) for 18 months after Gazette publication; the Rules similarly phase Rules 3 and 5–16. The Gazette issue is dated 13 November 2025, so this group is scheduled for **13 May 2027**, subject to checking for later amendments or notifications before launch. Section 9 includes verifiable parental consent and restrictions on tracking/behavioural monitoring of children; the Rules specify limited exemptions. This app's child location monitoring makes a focused legal assessment of applicability, consent evidence and exemptions a launch gate, rather than assuming that a parent-created account automatically satisfies it. Get Indian privacy counsel to assess the exact service and applicable exemptions before the effective date. [Official commencement notification](https://egazette.gov.in/WriteReadData/2025/267647.pdf), [Official DPDP Rules, 2025](https://www.meity.gov.in/static/uploads/2025/11/53450e6e5dc0bfa85ebd78686cadad39.pdf), [DPDP Act, Section 9](https://www.meity.gov.in/static/uploads/2024/02/Digital-Personal-Data-Protection-Act-2023.pdf)

The DPDP timeline above is a compliance-planning summary, not legal advice. It is based on the Gazette dates; re-check for later amendments or notifications before launch.

## Child battery-drain review

### Primary likely cause (high confidence from code; not yet measured on device)

`LocationManager.swift`:

- Lines 64–71 set `desiredAccuracy = kCLLocationAccuracyBestForNavigation` and `distanceFilter = kCLDistanceFilterNone`.
- Lines 90–99 set `allowsBackgroundLocationUpdates = true` and `pausesLocationUpdatesAutomatically = false`.
- Lines 150–175 start continuous location updates for either role once authorized. `AppDelegate.checkLogin()` also calls `startUpdating()` for both parent and child at line 168.

This asks iOS to keep high-accuracy location active continuously, including when stationary, and explicitly prevents automatic pausing. GPS is expected to dominate energy use; Indian network conditions do not explain this by themselves. A child using the device all day or leaving the app logged in overnight is the likely scenario for sustained drain.

### Secondary contributors and code defects

1. **Repeated geofence churn:** each child location update calls `setupNextRegion` (`LocationManager.swift` lines 323–326), which stops every monitored region and recreates a 30 m circular region (`lines 350–365`). This adds region-monitoring work and does not make force-quit resurrection dependable. iOS may relaunch after system termination for location events, but user force-quit behavior is not a supported keep-alive mechanism.
2. **Frequent location uploads:** the child callback uploads at most once per five seconds (`LocationManager.swift` lines 414–438), i.e. a theoretical ceiling of 17,280 requests per uninterrupted 24 hours if fixes keep arriving. Actual callback/upload frequency depends on iOS and movement. Frequent radio wakeups add energy and server load.
3. **Background upload implementation mismatch:** a background `URLSession` is configured at lines 53–61, but the live request uses `URLSession.shared.uploadTask` with a completion closure at lines 496–510. That does not use the configured background session, so the comments promising OS-managed background transfer do not match the implementation. This is more a background-delivery reliability issue than the root GPS drain, but retry/refresh behavior can create extra work.
4. **Permission scope and wording:** the app enables background location generally and its location purpose string is broad/generic. If parents do not need continuous tracking outside the explicit self-drive feature, the same setup can waste energy on the parent phone too. Restrict always-on tracking to the child safety feature (and parent self-drive only while active).
5. **Parent-side polling is separate:** `HomeVC.swift` and `MapViewVC.swift` poll a child's last location every five seconds while those parent screens are foregrounded. This can increase parent network use but does not explain the reported child-side background GPS drain.

### Recommended fix sequence

1. **Define the tracking state machine:** only the child safety mode (or an explicitly active parent self-drive mode) starts continuous tracking. Pause/stop when the mode ends or the account logs out. Avoid enabling this for all authenticated roles by default.
2. **Use adaptive location power:** use lower-power significant-change/region monitoring while idle; switch to high-accuracy standard updates only while tracking a real drive. After a confirmed parked/stationary interval, reduce or pause GPS. Do not treat a single zero-speed fix as “parked”—traffic stops need to retain correct shield behavior.
3. **Remove per-fix region recreation:** update a region only after meaningful movement or replace the mechanism with a supported relaunch/wake strategy. Do not promise continued operation after a user force-quits the app.
4. **Reduce network wakeups:** upload on meaningful location/speed changes with a longer adaptive interval, or batch points if the product can tolerate it. Keep the safety shield decision local on device. Use the configured background URLSession correctly only where a background transfer is needed; avoid one tiny transfer per location fix.
5. **Measure before/after:** use a physical iPhone on a repeatable parked/drive route with identical brightness, signal and app state. Capture Xcode Energy Log/Instruments, Core Location callback rate, API requests per hour, CPU/network energy and iOS Battery usage. Compare child and parent roles and test background, locked, low-signal and stopped-in-traffic states.

### Likely implementation touch points / estimate

For the battery fix, start with **3 source files plus configuration/API coordination**:

- `GaurdianDrive/OtherClasses/Location Manager/LocationManager.swift` — accuracy, pausing, adaptive mode, region churn and upload cadence (primary file).
- `GaurdianDrive/AppDelegate/AppDelegate.swift` — do not start continuous updates for every logged-in role; restore the right state on launch.
- `GaurdianDrive/ParentControl/AppBlockerManager.swift` and/or the child view-model — provide explicit driving/parent-self-drive state and a consistent threshold source. Add another file only if a dedicated tracking-state manager is introduced.
- `GaurdianDrive/Info.plist` / Xcode-generated permission strings — clear background-location disclosure and purpose text.
- Backend/API — if cadence or batching changes, agree on freshness/retention behavior and avoid treating lower frequency as tampering.

The India-specific client changes are separate: **4 Swift screens** for country defaults, **1 subscription screen** for localized prices, and **at least 2 speed-policy locations** (`AppBlockerManager` and `LocationManager`) plus the shared unit/profile policy. The exact implementation count depends on whether country, price and drive policy are centralized rather than patched in place.

## Limits of this review

This was a source/configuration inspection, not a complete backend, App Store Connect, privacy-policy, signing-account or physical-device audit. The production API's region, OTP provider, data retention, India legal basis, StoreKit territory configuration and Family Controls entitlement approval must be confirmed by their owners. Battery root cause is strongly suggested by the source but needs device measurements to quantify.
