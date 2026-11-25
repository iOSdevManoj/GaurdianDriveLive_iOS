# India Launch & Battery Fixes — Implementation Plan

Status: **implemented on branch `claude/india-battery-fixes`, NOT yet built or tested on a device.**
The work environment has no Xcode, so every change was checked by reading the code only. Build and run the device checklist at the end before merging.
Backend questions: `docs/BACKEND_NOTES_INDIA.md`.

| # | Item | Commit | Result |
|---|---|---|---|
| 1 | Phone country default | `3eaa370` | Done |
| 2 | Drive-mode trigger (kept 15 mph) | `f357c8f` | Done, no behaviour change |
| 3 | Local App Store prices | `30d675a` | Done |
| 4 | Dates / time zone | — | No code change needed (see item 4) |
| 5 | Permission text + parent GPS + logout | `202b578`, `cc45d49` | Done |
| 6 | Battery (parked low power, geofence) | `fb80a74` | Done |
Estimate shared with client: 8.5 working days (`docs/Guardian_Drive_India_iOS_Estimate.docx`).
Code reviewed at commit `4dad5eb` (main).

## Ground rules (apply to every item)

1. **App blocking is the core feature and must not change behaviour.** The speed → shield pipeline is:
   `LocationPermissionManager.didUpdateLocations` → `.speedDidUpdate` → `AppBlockerManager.subscribeToSpeedUpdates` → `reEvaluateSpeed()` → `ManagedSettingsStore` shields (child) / `evaluateAndApplyShieldsForParent()` (parent self-drive).
   - Shields are **cleared only when a new location update reports speed ≤ limit.** Anything that stops location updates while shields are ON leaves the child's apps locked. Never stop updates or add a distance filter while shields are on.
   - Must keep working after background relaunch (`launchOptions[.location]` in `AppDelegate`), after app kill (significant-change + geofence wake), with No-Drive schedules (`checkNoDriveSchedule()`), with No-Location-Tracking approvals (stops upload only), and with approved-app exceptions.
2. One item per commit, so each can be tested and reverted on its own.
3. Don't touch: signing/team/bundle id in `project.pbxproj`, `Cerificates/`, the vendored Alamofire, `FeatureFlag` values, the app-name resolution code, the `"<base64>___<name>"` token format.
4. Screen Time (shields, picker, reports) does not work on the Simulator. Items 2, 5 and 6 must be verified on real iPhones (one parent, one child).
5. The project has no automated tests. Every item needs the manual checks listed below.

---

## 1. Phone country defaults & +91 flow — 0.25 day

**Already done (keep as is):**
- Indian number validation exists: `+91` requires the first digit to be 6–9 (`LoginRegisterVC.swift:484`, same in `BasicInfoVC.swift:300/370`).
- Editing a child already keeps the child's saved country (`AddChildVC.setChildDataForEdit`, lines 77–92).
- `BasicInfoVC` already uses the country passed from the previous screen, falling back to US only if it's empty or +1.

**To change:**
- `LoginRegisterVC.swift:142-145`, `InvitationLinkVC.swift:55-57`, `AddChildVC.swift:70-72`: replace the hardcoded `"US"` with one shared default.
- `BasicInfoVC.swift:105`: the empty-value fallback uses the same shared default (keep the `+1` → US rule, because `+1` is shared by US and Canada).
- The storyboard labels default to `"+1"` (Main.storyboard ×3, Home.storyboard ×1). Set the label from code, so the flag and the code always match.
- Add one helper, e.g. `defaultPhoneCountryCode()`: the device region (`Locale.current.region`) if CountryPickerView knows it, otherwise `"US"`. Indian devices get +91 and existing US users still get +1.
- Small safety fix: `BasicInfoVC.swift:113` force-unwraps `countryCode!`, which crashes if the code is unknown. Fall back to the default instead.

**Not changing (note for client):** `EditProfileVC` has no country picker. A social-login user with no saved phone gets an empty country code when adding a phone in Edit Profile. This existed before; it's out of scope unless the client asks.

**Backend to confirm:** +91 OTP SMS delivery, resend limits, and the expected `countryCode` format (`"+91"`, as the app already sends it).

**Test:** register, log in, invite and add a child with a +91 number. Edit a US child and an Indian child: the flag and code stay correct. Run on a device with region India and on one with region US.

---

## 2. Speed unit (km/h) & drive-mode threshold — 0.5 day

**Already done (keep as is):**
- Displaying km/h vs mph is fully built: `SpeedUnit` (`Helper.swift:584+`), set by the parent in Settings (`profile/speed-unit`), used on the child home, parent self-drive and parent screens.
- Internal units and the API are MPH everywhere (`apiValue(fromMph:)`). Don't change this.

**Current behaviour (deliberate):** the drive-mode trigger is fixed at **15 mph ≈ 24 km/h** for everyone (`AppBlockerManager.swift:675-685`). The comment says the server's `speedAlertThreshold` is **for alert notifications only** and must not drive blocking. The older server-driven version is commented out below it.

**To change:**
- Put the trigger in one constant (e.g. `AppBlockerManager.driveModeTriggerMph`) and use it in:
  - `AppBlockerManager.fetchSpeedLimit()` (line 679)
  - `LocationManager.swift:303-304`: this currently reads a UserDefaults key that `fetchSpeedLimit` always deletes, so it always falls back to 15. Read the constant instead, so the `driveMode` string sent to the server always matches the shield decision.
  - the hardcoded "15 mph" log text and comments (`AppBlockerManager.swift:449`, `ParentSelfControlDriveVC.swift:125`).
- Set the value the client chooses for India. If the client keeps 15 mph, behaviour is unchanged and only the display already shows "24 kmph".

**Client decision needed:** the India trigger speed, and whether it is one global value or per country/per child.
**Backend dependency:** only if the client wants it per child or server-driven. That needs a separate backend field for the drive-mode trigger. Don't reuse `speedAlertThreshold`, which has a different meaning today.

**Test:** GPX replay (`FastDriveSimulation.gpx`) for the label and driveMode text. On a real device, shields go on above the threshold and come off when stopped, for both the child and parent self-drive.

---

## 3. Local App Store prices on the subscription screen — 0.5 day

**Already done:** StoreKit 2 products are already fetched for all 8 product ids (`SubscriptionListVC.swift:133-146`, `IAPManager.fetchProducts`). Purchase, verification (`parent/apple/transaction/verify`) and entitlement are not affected.

**To change:**
- After products load, replace each plan card's `price` / `yearly` string with `Product.displayPrice` for the matching product id (monthly and yearly). Then refresh `viewState` and reload the cards.
- Keep the current USD strings **only as a fallback** if products fail to load, so the screen is never empty.
- Card rendering (`SubscriptionListVC.swift:910-947`) stays as is. Check that long ₹ values (e.g. "₹1,099.00") fit the card.

**App Store Connect (item 7):** INR prices must be set for all 8 products. No new product ids are needed.

**Test:** Sandbox account with an India storefront and a US storefront. Prices match the purchase sheet. Purchase, restore and upgrade still work.

---

## 4. India date, time & language formatting — 0.25 day

**Already done (keep as is):**
- No-Drive schedule times are sent as ISO-8601 UTC (`ChildHomeVC.swift:2829-2833`) and parsed back as ISO (`checkNoDriveSchedule`, `ChildRequestedApp`). This is time-zone safe, and No-Drive suppression of blocking works in India time.
- Most display formatters use the device time zone.

**Found:**
- Report times use `formatServerDate(localTime)` (`Helper.swift:384`). The **server** converts to the user's local time using `timeZoneOffset`, which the app sends at login/registration (`getTimeZoneOffsetMinutes()`). India is **+330 minutes (half hour)**.
- Fixed-format `DateFormatter`s without `en_US_POSIX` (e.g. `ViewForNoDriveRequest.swift:217/320/326`, `ChildRequestedApp.swift:209`) are display-only, so they're low risk.

**Result:** no code change was needed. Every parser of server strings already uses `en_US_POSIX` or `ISO8601DateFormatter`, and schedule times go out in UTC. No language/Hindi work (not in scope; there are no `Localizable.strings`).

**Backend to confirm:** that the server handles a +330-minute offset correctly in reports and `localTime` (half-hour offsets are a common backend bug).

**Test:** device set to Asia/Kolkata. Check report times, request times, No-Drive start/end, and that the schedule turns blocking off at the right local time.

---

## 5. Background-location disclosure & role-based tracking — 0.5 day

**Current:**
- The permission text is one generic sentence for all three keys (`project.pbxproj:1462-1464` and `1591-1593`).
- Continuous high-accuracy GPS starts for **every** logged-in user, parent included (`AppDelegate.swift:168`, `LocationManager.setup()` / `checkPermission()`).
- On the parent, location is used **only** for parent self-drive blocking (`evaluateAndApplyShieldsForParent`, `ParentSelfControlDriveVC`). Parents don't upload location or use the geofence.

**To change:**
- Rewrite the three `NS…UsageDescription` strings: why background location is used (drive detection and app blocking for the child, live location for the parent), and who can see it. Edit only these 6 lines in `project.pbxproj`, not the signing lines.
- Parent: run continuous GPS **only when parent self-drive has at least one restricted app** (the `BlockingSelection` on the parent device has blocked apps). Start it when the parent adds apps and stop it when the list becomes empty. The parent's manual block doesn't need GPS (it isn't speed based).
- Child: no change; tracking stays always on.
- Logout (`AppDelegate.logoutUser`, line 206): also stop significant-location monitoring and remove the geofence. Today only `stopUpdatingLocation()` runs, so a logged-out phone can still be woken by iOS.

**Risk:** if the parent detection is wrong, parent self-drive stops locking apps. Test a parent with and without self-drive apps, including after an app kill.

**Test:** fresh install as parent and as child. Check the permission prompts and text. Parent with no self-drive apps: no blue location bar or constant GPS. Parent with self-drive apps: shields work while driving. Logout stops all location.

---

## 6. Battery optimization — 3 days (highest risk)

**Cause (confirmed in code, `LocationManager.swift`):**
- `kCLLocationAccuracyBestForNavigation` + `kCLDistanceFilterNone` + `pausesLocationUpdatesAutomatically = false`, always on, even when parked (lines 69-70, 94).
- Geofence removed and re-created on **every** location update on the child (lines 325-366).
- Upload every 5 s whenever there is an update (throttle, line 48), even when the phone hasn't moved.

**Keep as is (deliberate, don't "fix"):**
- `pausesLocationUpdatesAutomatically = false`. If iOS pauses updates it doesn't reliably resume them in the background, and shields could stay on.
- `distanceFilter = none` **while moving or while shields are on.** The comment on line 70 explains this: updates must keep arriving when the car stops so shields clear.
- Uploads use `URLSession.shared` on purpose (comment, lines 496-498: the background session delays uploads by minutes). The review doc's "use the background session" suggestion is **not** applied.
- Significant-change monitoring and the geofence wake (killed-mode survival) stay.

**To change (adaptive location power):**
- **Active mode** (current settings): used when speed > 0, shields are ON, or there was movement in the last ~5 minutes.
- **Parked mode**: entered only when speed has been 0 for ~5 minutes **and shields are OFF**. Use lower accuracy (e.g. 100 m) with a distance filter (e.g. 50 m). Movement brings updates back, and the first update switches back to active mode before the car can reach the drive-mode speed.
- **Geofence**: re-create only when the phone is more than ~100 m from the current region's centre, or when no region exists. Not on every update.
- **Uploads (as built):** the 5 s throttle is unchanged. In parked low-power mode there are no location callbacks, so there are **no uploads until the phone moves** (about 50 m). A timed heartbeat was not added: background timers don't run, and it would need GPS on again. If the backend needs a heartbeat, see `BACKEND_NOTES_INDIA.md` §4.
- **Geofence (as built):** only re-created once the phone is outside the current region (30 m radius kept).
- **False-lock guard (as built):** the coarse fix that ends low power is never used to calculate speed. For 20 s afterwards the manual speed fallback only uses fixes with accuracy ≤ 50 m.
- **Trade-off:** after a stop of more than 5 minutes, drive mode can start a few seconds later than before, because the phone must move about 50 m before full GPS is back. It still starts well before 15 mph is sustained. Leaving the geofence (30 m) and opening the app also end low power.
- The mode switch lives in `LocationPermissionManager`. `AppBlockerManager` only exposes "shields on?" (read-only); the blocking logic itself is not changed.

**Backend / client to confirm:**
- Does the backend or parent app mark a child "offline", "location off" or "tampered" if no upload arrives for N seconds? If yes, the parked heartbeat (60 s) must be below N.
- What location freshness does the parent need while the child is parked? (The parent screen polls every 5 s, but a parked child's position doesn't change.)

**Test (real iPhones):** drive → stop at a light → drive (shields must clear at stop and come back). Park 10+ minutes, then drive away (shields must come on in time). Locked screen, app killed, phone restarted. No-Drive window active. No-Location-Tracking approved. Battery: same phone and same route, before vs after, parked 2 h and driving 30 min. Record battery %, Xcode Energy Log, uploads per hour.

---

## 7. App Store Connect India setup — 1.5 days (no code)

India availability; INR prices for all 8 subscription products; store listing; privacy labels (precise location, contact info, linked child data); App Review notes with parent and child test accounts and the invite/QR steps; check the Family Controls distribution entitlement on both targets' profiles.

## 8. Device testing & battery verification — 2 days

Full regression on real iPhones, parent + child: login/registration (+91 and +1), add/edit child, invite/QR, subscriptions (purchase/restore), app blocking (speed, approved apps, select-all, chunked stores), app unblock / No-Drive / NLT requests, push commands (block/unblock), reports, logout. Plus the battery comparison from item 6.

---

## Decisions needed from the client before starting

1. Drive-mode trigger speed for India (keep 15 mph ≈ 24 km/h, or another value).
2. Phone default: device region (recommended) or always +91.
3. Parked-child location freshness, and the backend "offline/tampered" timeout (item 6).
4. Backend confirmation: +91 OTP delivery, +330-minute time zone handling, INR receipt verification.

## Found but out of scope (not changed)

- `EditProfileVC` has no country picker (item 1 note).
- `NotificationServiceExtension/` is not part of the Xcode project (not built).
- Hindi / other languages: no localization files exist; this would be a separate estimate.

---

## Device test checklist (run before merging `claude/india-battery-fixes`)

Two real iPhones: one parent, one child, both with Screen Time approved. Use one build for everything.

**Build**
- [ ] `pod install`, open the `.xcworkspace`, build the `GaurdianDrive` scheme with no errors or new warnings.

**1. Phone country**
- [ ] Device region India: Login/Register, Invitation, Add Child show the 🇮🇳 flag and `+91`. Register and log in with a +91 number (OTP arrives).
- [ ] Device region United States: same screens show 🇺🇸 `+1` (unchanged for current users). Existing +1 account logs in.
- [ ] Pick another country manually: the flag and code follow the pick, and the API receives that code.
- [ ] Edit an existing US child and an Indian child: the saved country is shown.
- [ ] Email or social sign-up → Basic Info: shows the device country. Adding a phone sends that code.

**2. Drive-mode trigger (15 mph)**
- [ ] Child: shields go on above 15 mph (24 km/h when km/h is selected) and come off when stopped. The label shows "24 kmph" or "15 mph".
- [ ] Parent self-drive: same.
- [ ] Parent map shows "Drive mode active" while the child drives, and "Normal" after.

**3. Prices**
- [ ] Sandbox tester on the India storefront: cards show ₹ prices that match the purchase sheet, monthly and yearly ("or ₹X /year").
- [ ] Sandbox tester on the US storefront: $ prices as before.
- [ ] Purchase, restore and upgrade still work, and the subscription is active on the server.
- [ ] Airplane mode on the subscription screen: USD fallback prices are shown and nothing crashes.

**5. Permissions and parent GPS**
- [ ] Fresh install: the permission prompts show the new text.
- [ ] Parent with **no** self-drive apps: no constant location use (Settings › Privacy › Location Services: no recent "arrow" while idle).
- [ ] Parent adds self-drive apps → returns to the self-drive screen → speed updates and shields work while driving, including after killing the app.
- [ ] Parent removes all self-drive apps → GPS stops. Parent manual block still works.
- [ ] Logout (parent and child): location stops, the app is no longer woken in the background, and logging in again restarts tracking for the child.

**6. Battery and app blocking (most important)**
- [ ] Drive → stop at a light (< 5 min) → drive: shields clear at the stop and come back.
- [ ] Park 10 min (low power starts after 5 min, see the log `low-power location`) → drive away: drive mode and shields start within seconds of reaching 15 mph. The log shows `Leaving low-power location`.
- [ ] While parked in low power: shields stay **off**, with no false lock.
- [ ] Same with the screen locked, the app in the background, and the app killed (geofence or significant-change wake).
- [ ] No-Drive window active while driving: no shields. No-Location-Tracking approved: no uploads, but shields still work.
- [ ] Approved apps, "select all" and a large app list (chunked stores) still behave as before.
- [ ] Battery: same phone and same route, old build vs new build. Parked 2 h, then driving 30 min. Record battery %, Xcode Energy Log and uploads per hour.

**Regression**
- [ ] App unblock / No-Drive / No-Location-Tracking requests and approvals, push block/unblock commands, reports, notifications, profile edit.
