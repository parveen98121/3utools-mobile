# 3uTools Mobile: design

Date: 2026-11-22

## Intent

A native iPhone app, for the owner's own phone, that gathers device information, battery and storage monitoring, photo management, a map-based location tool, diagnostics and small utilities into one place. Its feature organisation and visual identity are inspired by the desktop 3uTools program. It is a personal tool, not an App Store product.

The owner works on a Windows PC and has no Mac. The app is compiled on GitHub's macOS runners and installed on the phone from Windows with Sideloadly, using a free Apple ID.

## Goals

- A real native SwiftUI app with five tabs: Home, Device, Photos, Location, Toolbox.
- Every value shown is a real reading from a public iOS API, or is clearly labelled as an estimate, or is replaced by an explanation of why iOS does not expose it.
- A polished look: blue-to-purple gradient branding, rounded cards, charts, smooth animation, light and dark mode.
- A project that builds in the cloud with no Mac, and that also opens as a normal Xcode project if a Mac becomes available.
- Unit tests for the logic that can be tested without a device.

## Non-goals

- App Store or TestFlight release. A short appendix in the README explains what would have to change; nothing more.
- A backend. The app has no server and no account.
- Background battery logging. Samples are recorded only while the app is open.
- iPad-specific layouts. The app runs on iPhone only.

## Anti-goals

These would make the app a failure even if it compiled:

- Showing invented or placeholder values as if they were device data.
- Claiming to do something iOS does not allow: changing the system GPS location, listing all installed apps, clearing other apps' caches, reading battery health, running hardware tests.
- Anything touching Activation Lock, passcodes, IMEI or serial numbers.
- Collecting or sending personal data anywhere.

## Constraints

- **No local compiler.** Code is written on Windows and first compiled on a GitHub Actions macOS runner. The build is staged so errors surface early (see Build stages).
- **Free Apple ID signing.** The installed app expires after 7 days and is re-installed with Sideloadly. Free signing cannot use restricted capabilities, so the app declares no entitlements. This rules out Wi-Fi network name (Access Wi-Fi Information), Screen Time usage statistics (Family Controls), NFC and iCloud. Those features show an explanation instead.
- **iOS 17 minimum**, iPhone only, portrait and landscape.
- **Public APIs only**, with the two flagged exceptions under "Calls made by the designer".

## Approaches

Three ways to set the project up were considered.

1. **XcodeGen spec, generated at build time (chosen).** The repository holds Swift source and a `project.yml`. XcodeGen produces the `.xcodeproj` on the runner, which then tests, builds and packages an unsigned `.ipa`. Trade-off: no `.xcodeproj` is committed. Chosen by the owner because it is the only route that can be kept correct without a Mac.
2. **Hand-written `.xcodeproj`.** Opens directly in Xcode, but the project file format is fragile and cannot be validated on Windows.
3. **Swift Playgrounds app package.** Buildable on an iPad, but needs an iPad, has no unit tests and handles permissions awkwardly.

## Technology

| Area | Choice |
|---|---|
| Language | Swift, Swift 5 language mode (avoids strict-concurrency errors that cannot be checked locally) |
| UI | SwiftUI, `TabView` plus one `NavigationStack` per tab |
| Architecture | MVVM. View models are `@Observable` classes. Device access sits in services behind protocols so view models can be tested with fakes |
| Persistence | SwiftData |
| Charts | Swift Charts |
| Maps | MapKit for SwiftUI, Core Location, `MKLocalSearch`, `CLGeocoder` |
| Photos | PhotoKit (`PHPhotoLibrary`, `PHCachingImageManager`) |
| Scanner | VisionKit `DataScannerViewController` |
| Network | Network framework (`NWPathMonitor`), `URLSession` |
| Secure storage | Keychain, through a small wrapper |
| Project | XcodeGen `project.yml`, Xcode 16 on `macos-15` runners |
| Third-party code | None |

## Folder structure

```
project.yml
README.md
.github/workflows/build.yml
App/
  ThreeUToolsApp.swift          app entry, model container
  RootTabView.swift
  Info.plist values are set in project.yml
Core/
  DesignSystem/                 colours, gradients, typography, spacing
  Components/                   reusable views (see below)
  Services/                     one file per service protocol + implementation
  Persistence/                  SwiftData models
  Utilities/                    formatters, model-name table, Keychain wrapper
Features/
  Home/         Views/ ViewModels/
  Device/       Views/ ViewModels/      (device info, battery, storage, apps)
  Photos/       Views/ ViewModels/
  Location/     Views/ ViewModels/
  Diagnostics/  Views/ ViewModels/ Models/
  Toolbox/      Views/ ViewModels/      (network, speed test, QR, files, shortcuts, export, about)
Resources/
  Assets.xcassets               app icon, accent colour
  (the identifier-to-name table lives in Core/Utilities/DeviceModelCatalog.swift)
Tests/
```

## Visual design

No reference screenshots were supplied, so the look is built from the written brief.

- Brand gradient from blue (#2F6BFF) to purple (#8A4DFF), used on the Home header, primary buttons, chart fills and the app icon.
- Backgrounds use the system grouped background colours, so light and dark mode both work without custom palettes.
- Cards have a 20-point continuous corner radius, the secondary grouped background and a soft shadow in light mode.
- SF Symbols for all icons. SF Pro with rounded design for large numbers.
- Animation: ring gauges animate on appear, numbers use numeric content transitions, cards use a spring on tap.

Reusable components: `GradientHeader`, `InfoCard`, `StatTile`, `RingGauge`, `InfoRow`, `StatusBadge` (Passed, Warning, Not Available), `SourceBadge` (Live, Estimated, Not available), `EmptyStateView`, `LoadingView`, `PermissionPromptView`, `RestrictedFeatureView`, `DeviceIllustration` (an iPhone outline drawn with SwiftUI shapes, showing the real device name and iOS version, never a fake screenshot).

## Screens

### Home tab

```
┌──────────────────────────────┐
│ ░░ gradient header ░░░░░░░░░ │
│  ┌────┐  Parveen's iPhone    │
│  │    │  iPhone 15 Pro       │
│  │    │  iOS 18.1            │
│  └────┘                      │
├──────────────────────────────┤
│ ┌ Battery ─────┐┌ Storage ──┐│
│ │  ◔ 82%       ││  ◔ 61%    ││
│ │  Charging    ││ 98 GB free││
│ └──────────────┘└───────────┘│
│ ┌ Diagnostics ──────────────┐│
│ │ 9 passed · 1 warning · 3 n/a│
│ └───────────────────────────┘│
│ ┌ Device information ───── >┐│
│ └───────────────────────────┘│
│ Quick actions: Speed test, QR│
└──────────────────────────────┘
```

Battery, Storage, Diagnostics and Device information cards each navigate to their detail screen. Battery health appears as a row reading "Not available to apps", with the path Settings > Battery > Battery Health.

### Device tab

A list with four entries, each opening a detail screen.

- **Device Information.** Sections: Identity (name, model name, model identifier, device type), Software (iOS version, build), Storage (capacity, available), Battery (level, state, Low Power Mode), Hardware (processor cores, physical memory, screen size, scale, refresh rate, thermal state, time since boot), Network (connection type, local IP address, carrier-independent details only), Identifier (the vendor identifier, hidden behind a "Reveal" tap, with copy). Any value iOS does not return shows "Not available".
- **Battery.** A large ring with level and state. A line chart of recorded levels with selectable ranges (24 hours, 7 days, 30 days) and a draggable selection that shows the reading under the finger. A list of charging sessions derived from recorded state changes. A banner states that history covers only the times the app was open. Battery health shows the "Not available to apps" explanation.
- **Storage.** A donut chart of used against available. Rows for total, used, available. A "Photos and videos" row with an estimated size (see Calls) and counts. A "This app's documents" row with the real size of the app's own folder. Recommendations generated from real numbers, for example "Under 10% free" or "You have N videos longer than 5 minutes". A panel explaining that per-app sizes and cache clearing are only available in Settings > General > iPhone Storage, with a button that opens the Settings app.
- **Apps.** An explanation that iOS does not let an app list installed apps. Below it, a list of well-known apps the phone reports as installed, detected with `canOpenURL` against a bundled list of at most 50 URL schemes. Each row shows the name, an icon and details fetched from Apple's public iTunes lookup service, an Open button and an App Store button. Per-app storage shows "Not available".

### Photos tab

- Segmented control: Photos, Videos, Albums.
- A lazy grid of thumbnails, with counts in the title area.
- Search over album titles, and filters for favourites, screenshots, Live Photos, and date range.
- Tapping opens a full-screen preview with zoom for photos and playback for videos, and an info sheet (date, dimensions, duration, location if present, file type).
- A Select mode with multi-select and Delete. Deletion goes through PhotoKit, which shows Apple's own confirmation dialog; the app shows its own confirmation first.
- Permission is requested the first time the tab is opened. Limited access is supported and labelled. Denied access shows a prompt with a button to Settings.

### Location tab

```
┌──────────────────────────────┐
│ [ Search place or address  ] │
│                              │
│          map                 │
│      ● current   📍 selected │
│                              │
│ ┌──────────────────────────┐ │
│ │ Lat 28.6139   Lon 77.2090│ │
│ │ Address line             │ │
│ │ ☆ Save  Open in Maps  ⟲  │ │
│ └──────────────────────────┘ │
│  History · Favourites        │
└──────────────────────────────┘
```

- Search by place or address, or type latitude and longitude directly.
- Tapping the map drops the selected pin and reverse-geocodes it.
- The bottom panel shows coordinates, address, distance from the current location, and buttons to save as favourite, open in Apple Maps for directions, copy coordinates, and "Restore actual location", which clears the selected pin and recentres on the real GPS position.
- History and Favourites are stored in SwiftData.
- A permanent, dismissible-per-session notice states: "This pin is a marker inside this app only. iOS does not allow an app to change the phone's GPS location for other apps."

### Toolbox tab

A grid of tools.

- **Diagnostics.** A dashboard of checks, each with Passed, Warning or Not Available and a one-line reason. Checks: battery level and state, Low Power Mode, free storage, network reachability, connection type, thermal state, memory, camera permission, microphone permission, location permission, photos permission, and hardware availability (cameras, torch, Face ID or Touch ID, accelerometer, gyroscope, barometer, haptics). A footer states that iOS does not expose hardware tests such as screen, speaker or sensor calibration to apps.
- **Network diagnostics.** Connection type, whether the path is expensive or constrained, IPv4 and IPv6 support, local IP address, DNS lookup time and HTTPS round-trip time to a chosen host.
- **Speed test.** Download and upload measured against Cloudflare's public speed-test endpoints, with a live gauge and a stored history. Labelled as an estimate. A note says the test contacts Cloudflare, which sees the phone's IP address.
- **QR scanner.** Live scanning of QR codes and barcodes. Results can be copied, shared or opened if they are links. Camera permission is requested on first use.
- **Files.** Apple's document picker to open files and folders, with Quick Look preview and file details. Recently opened items are remembered with security-scoped bookmarks.
- **Wi-Fi information.** Shows what is available (connected over Wi-Fi or not, local IP). The network name shows "Not available: requires a capability that free Apple ID signing does not include".
- **Settings shortcuts.** A button that opens the Settings app, and a list of written paths to the common pages (Battery, iPhone Storage, Privacy, Wi-Fi).
- **Backup and export.** An explanation that iOS does not let apps read iCloud backup status, with the path to it in Settings. An "Export device report" action that shares a JSON or text file of the device information and diagnostic results, and an export of battery history as CSV.
- **Usage statistics.** An explanation that Screen Time data needs a capability unavailable with free signing, with the path to Screen Time in Settings. Shows time since boot, which is real.
- **About and privacy.** A short privacy page: no data leaves the phone except the iTunes lookup and the speed test, both started by the user's action.

## Data and services

Services, each a protocol with a live implementation:

| Service | Source |
|---|---|
| `DeviceInfoService` | `UIDevice`, `ProcessInfo`, `utsname`, `UIScreen`, the model table in `DeviceModelCatalog.swift` |
| `BatteryService` | `UIDevice` battery monitoring and its notifications |
| `StorageService` | Volume resource values on the home directory URL, file enumeration of the app's own folders |
| `NetworkService` | `NWPathMonitor`, `getifaddrs`, timed `URLSession` requests |
| `SpeedTestService` | `URLSession` against Cloudflare endpoints |
| `PhotoLibraryService` | PhotoKit |
| `LocationService` | `CLLocationManager`, `CLGeocoder`, `MKLocalSearch` |
| `PermissionService` | Status and request for camera, microphone, photos, location |
| `HardwareCapabilityService` | `AVCaptureDevice`, `LAContext`, Core Motion, Core Haptics |
| `InstalledAppService` | `canOpenURL`, iTunes lookup |
| `KeychainStore` | Security framework |

SwiftData models: `BatterySample` (date, level, state), `SavedLocation` (name, address, latitude, longitude, favourite flag, date), `SpeedTestResult` (date, download, upload, latency, connection type), `RecentFile` (name, bookmark data, date).

Battery samples are recorded when the app becomes active and on each battery level or state change while it is open. Charging sessions are derived from consecutive samples.

The Keychain holds one item: a random per-install identifier used in exported reports, so reports do not need the vendor identifier.

Every displayed value carries one of three sources, shown with `SourceBadge` where it is not obvious: Live (read from the device now), Estimated, or Not available (with the reason).

## Permissions

Requested only at the point of use, each with a plain usage description: Photos (read and write, needed for delete), Camera (QR scanner), Location when in use (Location tab), Microphone (only when the Diagnostics microphone check is run by the user). Each has four handled states: not asked, granted, limited where it applies, denied with a route to Settings.

## Error handling

- Services throw typed errors; view models turn them into a `ViewState` of loading, loaded, empty or failed with a message and a retry action.
- Network tools time out after 10 seconds and report the failure in the result, not as an alert.
- No `fatalError` or force unwraps on device data.

## Testing

Unit tests cover: byte and percentage formatting, model identifier to name mapping including unknown identifiers, storage maths and recommendation rules, charging-session derivation from samples, chart range filtering, diagnostic status rules for each check, coordinate text parsing and validation, speed calculation from bytes and time, and each view model against fake services. UI and device behaviour are checked by hand on the phone; the README has a checklist.

## Build and install

- `.github/workflows/build.yml` runs on every push: install XcodeGen, generate the project, run unit tests on an iPhone simulator, archive for device with code signing disabled, zip `Payload/` into `3uToolsMobile.ipa`, upload it as a workflow artifact.
- The README explains: downloading the artifact, installing with Sideloadly on Windows, trusting the developer profile on the phone, re-installing after 7 days, and the one-command route on a Mac.
- App icon: a single 1024-pixel PNG, gradient background with a white device glyph, generated by a script kept in `Tools/`. Launch screen: gradient background colour with the app name, defined through the Info.plist launch screen keys.
- Display name "3uTools Mobile". Bundle identifier `com.personal.threeutoolsmobile` (Sideloadly rewrites it at install time).

## Build stages

Each stage ends with a green cloud build before the next begins.

1. Project spec, workflow, design system, components, app shell with five tabs, Home, Device Information, Battery, Storage, their services, models and tests.
2. Photos and Location.
3. Diagnostics, Apps, Toolbox tools, export, README, icon.

## Calls made by the designer

The owner did not decide these. They are the designer's choices and can be overturned.

1. **Photo and video size uses an undocumented value.** PhotoKit has no public way to read an asset's file size. The Storage screen reads the widely used but undocumented `fileSize` key on `PHAssetResource`, computes it in the background, labels the result "Estimated", and shows "Not available" if the key returns nothing. The alternative is to show counts only.
2. **No deep links into Settings pages.** Only the public link that opens the Settings app is used, with written paths to each page. The undocumented `App-prefs:` links would jump straight to pages such as iPhone Storage but break between iOS versions.
3. **Speed test uses Cloudflare's endpoints**, since the app has no backend.
4. **Apps screen detects a bundled list of known apps** instead of showing only an explanation.
5. **Battery history is foreground-only**, with no background refresh task.
6. **Diagnostics lives in the Toolbox tab** with a summary card on Home; Battery, Storage and Apps live under the Device tab.
7. **Swift 5 language mode and no third-party packages**, to keep cloud builds predictable.
8. **The repository would be private** on the owner's GitHub account, created only after the owner agrees.

## Left to the builder

- Exact spacing, font sizes and animation timings within the design system described above.
- The contents of the bundled URL-scheme list and the device model table.
- The internal shape of each view model and the split of views into subviews.
- The wording of explanations, provided they stay accurate and plain.
