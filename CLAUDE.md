# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

GaurdianDrive (product name "Guardian Drive") is a native iOS parent/child driving-safety app. A parent account monitors one or more child accounts: it tracks the child's live location/speed and can block distracting apps on the child's device while they are driving (via Apple's Screen Time / FamilyControls APIs), with real-time sync between parent and child over a WebSocket + REST API backend.

- Xcode project: `GaurdianDrive.xcodeproj` / workspace: `GaurdianDrive.xcworkspace` (open the **workspace**, not the project — CocoaPods).
- Language: Swift 5 (UIKit storyboards + some SwiftUI for the parental-control screens).
- Deployment target: iOS 17.6 on both targets (the project-level default is 18.5; `podfile` says `platform :ios, '16.0'`, but that only governs the pods). SwiftData requires iOS 17, so don't add iOS 16 fallbacks. Bundle id: `org.app.GaurdianDrive1` in the current local signing setup — the committed `project.pbxproj` has `org.app.GaurdianDrive` under a different `DEVELOPMENT_TEAM`. Signing/team/version edits get swapped locally, so don't commit them along with an unrelated pbxproj change.
- Dependency manager: CocoaPods (see `podfile`, `Podfile.lock`).

## Build & Run

Dependencies are managed with CocoaPods. After cloning or when `podfile`/pods change:

```bash
pod install
```

Always open `GaurdianDrive.xcworkspace` (not the `.xcodeproj`) in Xcode after that. Building from the CLI:

```bash
xcodebuild -workspace GaurdianDrive.xcworkspace -scheme GaurdianDrive -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

`xcodebuild -list` prints ~50 schemes; the only non-CocoaPods ones are `GaurdianDrive` and `ReportExtension`. Build `GaurdianDrive`, which embeds `ReportExtension`.

There is no SwiftLint/SwiftFormat config in the repo — no lint step to run.

There is no test target in this project (no `*Tests` target/scheme exists) — there are no unit/UI tests to run. Manual verification of the speed→shield pipeline is done by replaying the GPX traces at the repo root (`FastDriveSimulation.gpx`, `SimulateDrive.gpx`, `Thaltej_*.gpx`) via Xcode's **Debug ▸ Simulate Location**; `TESTING_GUIDE.md` describes that flow.

### Targets

The project has exactly two native targets:

- **GaurdianDrive** — the main app.
- **ReportExtension** — a `DeviceActivityReport` extension (Screen Time framework); it is how real app *names* are obtained from opaque tokens (see "App-name resolution" below).

The `NotificationServiceExtension/` folder at the repo root (`NotificationService.swift`, `Info.plist`, entitlements) is **not part of the Xcode project**: it isn't referenced in `project.pbxproj` and nothing builds or embeds it. Push notifications are handled entirely in the main app. Editing those files has no effect unless you also add a target for them.

Both targets carry the `com.apple.developer.family-controls` entitlement (Screen Time / FamilyControls). **There is no App Group entitlement**, so the app and its extensions cannot share `UserDefaults`, files, or the SwiftData store — the only cross-process channels are `ManagedSettingsStore` and the `DeviceActivityReport` SwiftUI surface. Don't write code that assumes a shared suite/container.

## Architecture

### Parent/Child model & core flow

The app has two roles sharing one codebase and one backend: **Parent** and **Child**. A parent registers/logs in, adds a child, and the child installs the same app and logs in as "child." Role-specific screens live under `GaurdianDrive/View Controllers/` (e.g. `Home Tab` has parent flows, `Child Module` has the child's home/onboarding). The logged-in user object lives on `AppState.sharedInstance` (`AppState.sharedInstance.user?.userId`), but **the role itself is a UserDefaults flag, not an AppState field**: `UserDefaults.Main.bool(forKey: .isParent)` (child == `!isParent`), because it must survive background relaunch before `AppState` is repopulated.

The core safety loop, in order:

1. **`LocationPermissionManager`** (`GaurdianDrive/OtherClasses/Location Manager/LocationManager.swift`) — a `CLLocationManager` singleton tuned for automotive-grade background tracking (`kCLLocationAccuracyBestForNavigation`, `.automotiveNavigation`, significant-location relaunch handling). It computes current speed (MPH), throttles/uploads location to the backend over a **background `URLSession`** (`com.guardiandrive.locationupload`) so uploads survive app suspension, and broadcasts speed changes via `NotificationCenter` (`.speedDidUpdate`, `userInfo["speedMPH"]`).

   **Units: MPH everywhere except on screen.** CoreLocation gives m/s, kept internally as `currentSpeed`; `getSpeedMPH()` feeds everything local (the `.speedDidUpdate` broadcast, the drive-mode limit, shielding). Speeds under 1.5 m/s (~3.3 mph) are clamped to 0 to kill GPS jitter. The server also stores and returns MPH (current speed, reports, `speedAlertThreshold`). The *display* unit is the parent's choice in Settings (`POST profile/speed-unit/{MPH|KMPH}`), returned as `speedUnit` on both the parent's and the child's `GET /profile`. `SpeedUnit` (bottom of `OtherClasses/Helper/Helper.swift`) caches it in `UserDefaults.Main` `.speedUnit` (default mph), refreshes it via `SpeedUnit.refreshFromProfile()` on the Home/Settings screens, and posts `SpeedUnit.didChangeNotification` when it changes. Convert only for display: `format(mph:)` / `format(serverSpeed:)` (both convert from MPH). The threshold slider works in the display unit, so convert its value back with `mph(fromDisplayValue:)` before sending. Server-generated notification text (e.g. "crossed speed limit 20.0") is formatted by the backend, not the app.

   **The drive-mode threshold is hardcoded to 15 mph in the app**, not server-driven: `AppBlockerManager.fetchSpeedLimit()` ignores the backend, sets `speedLimitMph = 15.0`, and deletes the persisted `SpeedBlock_SpeedLimitMph` key (the server-driven implementation is commented out directly below it). The parent's slider still writes `speedAlertThreshold` to the backend and the parent's home screen displays that value, but it no longer drives blocking — so the parent can see one number while the child is shielded at 15.
2. **`AppBlockerManager`** (`GaurdianDrive/ParentControl/AppBlockerManager.swift`, `@MainActor` singleton) — subscribes to `.speedDidUpdate`, compares against `speedLimitMph` (currently the fixed 15 mph above), and when the child is speeding, applies a Screen Time "shield" via `ManagedSettingsStore` to the apps selected for blocking. Blocked-app selections are persisted with **SwiftData** (`BlockingSelection` model — see `ParentControl/BlockingSelection.swift`); large selections spill into numbered chunk stores (`Store_Chunk_0…4`) to work around `ManagedSettingsStore` size limits. Only one `ModelContainer` may exist per on-disk store — always go through `AppBlockerManager.shared.ensureModelContainer()` rather than constructing a new `ModelContainer` for the same schema (see comments in `ParentControlPasscodeVC.swift` / `ParentSelfControlDriveVC.swift`).
3. **`ChildPermissionSyncManager`** (`GaurdianDrive/OtherClasses/Permissions/ChildPermissionSyncManager.swift`) — reports the child device's Location/Screen Time authorization state to the backend (`PUT /child/{childId}/app/custom-data`) so the parent can see if the child revoked a permission ("app tampered"); the parent side reads it back via `GET` of the same endpoint.
4. **`GuardianSocketManager`** (`GaurdianDrive/OtherClasses/Socket Manager/GuardianSocketManager.swift`) — `URLSessionWebSocketTask` client (bearer token in the `Authorization` header, auto-reconnect timer) against `WebURL.socketUrl` = `wss://api.guardiandrive.net/web-socket/location`, for real-time push of location/state between parent and child. Guarded by `FeatureFlag.isSocketFeatureEnabled`, which is currently **false** — the live app is 100% REST polling, so don't assume socket paths are exercised.
5. **`PermissionsManager`** — centralizes requesting/checking the OS permissions the app depends on (location always/when-in-use, notifications, Screen Time authorization via `AuthorizationCenter`), invoked post-login rather than at cold launch.

`FeatureFlag` (`GaurdianDrive/Config/FeatureFlag.swift`) is the single place toggling in-progress/optional behavior (`showManualBlockButtons`, `isChildUserCanRemoveApp`, `isSocketFeatureEnabled`) — check it before assuming a code path is live.

### App-name resolution (why there are so many `APP_NAME_*` docs)

A Screen Time `ApplicationToken` is opaque: there is no API that maps it to a display name. The only way to render one is SwiftUI `Label(token)`, drawn out-of-process by FamilyControlsAgent. The codebase therefore extracts names two ways, and both are load-bearing:

- `ParentControl/AppNameResolutionViews.swift` — renders `Label(token)` and **scrapes the resulting text out of the UIKit view hierarchy** (`NameExtractorView`, handles the iOS 16+ `_UITextLayoutView`/accessibility path), scoped per row to avoid cross-row contamination.
- `ReportExtension/TotalActivityReport.swift` — a custom `DeviceActivityReport.Context("AppNameReport")` that walks `DeviceActivityResults` and yields `SharedAppInfo(name:token:)` (token base64-encoded from `JSONEncoder`, which is also the wire format used with the backend and in `AppCommand` in `ParentControl/BlockingCommand.swift`).

Resolved names are normalized and cached by `AppNameResolution` / `AppNameResolutionCache` (bottom of `ParentControl/ParentControlViewModel.swift`, ~line 1137+) — `isResolved(_:)` is the guard that decides whether a name is real or a placeholder/bundle id. Names arrive asynchronously and may never arrive, so every consumer must tolerate a token with no name yet.

### Parent↔child sync: app list, requests, and commands

With `isSocketFeatureEnabled == false`, the two live channels between parent and child are **REST polling** and **FCM data pushes**.

- **App list sync.** The child owns the list. It pushes its selection to `POST child/{childId}/apps/sync` (`ChildHomeViewModel`, `ChildHomeVC`, and `ParentControlViewModel`), and both sides read it back via `child/{childId}/apps` (blocked set) or `child/{childId}/apps/all` (everything, incl. requests). Endpoints are the `WebURL.childAppsSync/getChildApps/getAllChildApps` helpers.
- **Wire format for a token** is the base64 of `JSONEncoder().encode(token)`. The child may append a display name as `"<base64>___<App_Name>"` (`ChildHomeVC` ~line 2732) because the server has no other way to learn the name — so **every consumer must split on `"___"` and take `.first` before base64-decoding**. That split is repeated in ~17 places (`ChildRequestedApp.displayToken`, `AppBlockerManager`, `ParentControlViewModel`, …); reuse the existing helpers rather than decoding a raw token string.
- **`ChildRequestedApp`** (`View Controllers/Child Module/Model/ChildRequestedApp.swift`) is the shared row model for all three request flows. It is deliberately permissive: the backend returns the same logical field under several names and types (`name`/`appName`/`userName`, `id`/`_id`/`token`, `a` as Int *or* String), so it has a hand-written `init(from:)` and `display*` computed properties that pick the best value. Render via `displayAppName`/`displayToken`/`displayStatus`/`displayDate` — don't read the raw fields.
- **Three approval workflows**, all parent-approves-child, each with its own endpoints in `WebURL`:
  - *App unblock requests* — `child/{id}/app/{requestId}/approve|reject|cancel`
  - *No-Drive Mode* (scheduled window) — `child/{id}/none-drive-mode/request` + `/{requestId}/approve|reject|cancel`. `AppBlockerManager.checkNoDriveSchedule()` makes an approved window suppress shielding even while speeding.
  - *No-Location-Tracking (NLT)* — `child/{id}/no-location-tracking-mode/request|approve|reject|cancel`. Note these take **no requestId and an empty body** (single per-child state), unlike the other two. An approved NLT stops *uploading* location but leaves local speed tracking and the speed→shield pipeline running. State lives in `OtherClasses/Helper/NoLocationTrackingRequestStore.swift`, keyed by childId. There is **no GET endpoint** for NLT state: the store picks it out of the `/child/{id}/apps/all` response with a permissive key parser, and uses optimistic local state until the real key is confirmed.
- **Parent → child commands travel as FCM data pushes**, handled by `PushNotificationManager` → `AppBlockerManager.handlePushNotification(userInfo:)`. The payload carries either `blockingToken` (a base64 `FamilyActivitySelection`, a single `ApplicationToken`, or the literal `"UNBLOCK"`) or `blockingCommands` (a JSON array of `AppCommand` — `{token, action: Block|Unblock, appName, type}`, see `ParentControl/BlockingCommand.swift`). `data` may arrive as a JSON *string* or an already-parsed dict, so both are handled.

### Subscriptions

StoreKit 2, in `View Controllers/Setting Tab/IAP Manager/IAPManager.swift` — note the **top ~145 lines are a commented-out StoreKit 1 (`SKPaymentQueue`) predecessor; the live `@MainActor final class IAPManager: ObservableObject` starts below it**. It fetches `Product`s, purchases, listens for transaction updates, and reports back through closures; `SubscriptionListVC` then posts the receipt to `WebURL.subscriptionVerify` (`parent/apple/transaction/verify`) so the backend is the source of truth for entitlement (`profile/subscription`).

### Networking layer

- **Alamofire 4.x is vendored into the app source** at `GaurdianDrive/OtherClasses/Alamofire/` — the `pod 'Alamofire'` line in `podfile` is commented out and it is *not* in `Pods/`. That is why call sites use the global `request(...)` / `DataResponse` with no `import Alamofire`. Don't add the pod (it would collide); changing HTTP behavior means editing the vendored files.
- `GaurdianDrive/OtherClasses/WebServiceCall/WebAPIUrl.swift` (`WebURL`) — every backend endpoint as a `static let`, built from `WebURL.baseURL` (`https://api.guardiandrive.net/`). Add new endpoints here rather than inlining URLs.
- `GaurdianDrive/OtherClasses/WebServiceCall/APIManager.swift` — get/post/put/delete helpers over the vendored `request(...)`, auto-attaching the bearer token from `UserDefaults.Main.string(forKey: .userToken)` and checking reachability first. Note it has both `…WithToken` and `…WithoutToken` variants, and large blocks of commented-out predecessors — match the live (`isConnectedToNetwork1`-wrapped) shape when adding a method.
- `GaurdianDrive/OtherClasses/WebServiceCall/ApiCallViewModel.swift` — higher-level call site used by view models/managers (used by `ChildPermissionSyncManager`, etc.) — prefer this over calling `APIManager` directly from new code that already has a view-model layer.

### UI layer

Predominantly storyboard-based UIKit, organized per feature under `GaurdianDrive/View Controllers/<Feature>/{Controller,ViewModel,Model,Views}`, e.g. `Home Tab`, `Child Module`, `Report Tab`, `Setting Tab`, `Profile`, `Auth Screens`. Storyboards are split per area under `GaurdianDrive/Storyboards/` (`Home`, `Child`, `Reports`, `Settings`, `Tabbar`, plus `Main` in `Storyboards/Base.lproj`); `GaurdianDrive/Base.lproj` holds only `LaunchScreen.storyboard`. The parental-control screen set (`GaurdianDrive/ParentControl/`) is SwiftUI (`ParentControlView.swift` + `ParentControlViewModel.swift`) hosted from UIKit, since it uses the `FamilyActivityPicker`/Screen Time SwiftUI APIs directly.

The two biggest files by far are `View Controllers/Child Module/Controller/ChildHomeVC.swift` (~3.1k lines) and `View Controllers/Home Tab/Controller/HomeVC.swift` (~1.5k lines) — most child- and parent-side behavior funnels through them.

Shared UI/utility helpers live in `GaurdianDrive/OtherClasses/`:
- `Extension/` — UIKit/Foundation extensions (colors, fonts, gradients, dates, strings, etc.) used app-wide instead of ad-hoc helpers.
- `Helper/Helper.swift` — misc shared utilities plus app-wide constants/keys (e.g. `GoogleKey`) as file-scope globals.
- `UserDefault/STUserDefault.swift` + `Extension/UserDefaultExtension.swift` — typed `UserDefaults` access via `UserDefaults.Main` with per-type key enums (keys are namespaced as `Main.<key>`); look here before adding a raw `UserDefaults.standard` key.

### Third-party integrations

Firebase (Messaging + Crashlytics), Google Sign-In, Google Maps/Places, Apple Sign In, plus CocoaPods UI libs (`IQKeyboardManagerSwift`, `SVProgressHUD`, `Toast-Swift`, `SDWebImage`, `FSPagerView`, `CountryPickerView`, `SwiftQRScanner`). SDK bootstrapping is all in `AppDelegate.swift` `didFinishLaunchingWithOptions`; Firebase config is `GaurdianDrive/GoogleService-Info.plist`.

## Notes for making changes

- **The repo has no `.gitignore`, and `Pods/` (~2.3k files) and `BuildDerived/` (~10.5k files, a full DerivedData tree including a built `.app`) are committed.** When searching, exclude both — `BuildDerived/.../GaurdianDrive.app/` contains copies of bundled resources that produce duplicate/misleading grep hits. Likewise don't "clean up" by deleting them unless asked.
- **`README.md` and `CONTRIBUTING.md` are leftover GitLab-template boilerplate** (they describe a "Food Tracker" sample app and GitLab's CLA). They have nothing to do with Guardian Drive — ignore them, and don't cite them as project docs.
- This repo has accumulated many standalone `*_FIX*.md` / `*_SUMMARY.md` files at the repo root documenting past debugging sessions (app-name sync, notification/authorization fixes, etc.) — they're historical notes, not living docs; don't treat them as current specs, but they're useful context if touching app-name resolution or the shield/authorization flow.
- `Cerificates/` (sic) holds signing material — Dev/Dist certificates, a CSR, and a backend JWT key. Don't read, move, or copy its contents into code or docs.
- Xcode user-state files (`xcuserdata/`, `*.xcuserstate`, `.DS_Store`) show up as modified in `git status` routinely — this is normal Xcode churn, not a code change.
- When touching the speed→shield pipeline, remember it must keep working across background relaunch (`launchOptions[.location]` in `AppDelegate`) and app kill — state that needs to survive is deliberately kept in `UserDefaults`/SwiftData rather than in-memory-only singleton fields.
- Screen Time behavior (shields, `FamilyActivityPicker`, name resolution, `DeviceActivityReport`) does **not** work on the Simulator — those paths need a real device with Screen Time authorization.
