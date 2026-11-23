# 3uTools Mobile

A native iPhone app (SwiftUI, iOS 17 or later) that shows device information, battery and storage monitoring, a photo manager, a map-based location tool, diagnostics and a toolbox of small utilities. It is a personal project inspired by the desktop 3uTools program and is not affiliated with it.

Every value in the app is a real reading from a public iOS API, is labelled as an estimate, or is replaced by an explanation of why iOS does not share it.

## What you need

- A GitHub account (the app is compiled on GitHub's Mac machines, so no Mac is needed).
- A Windows PC with [Sideloadly](https://sideloadly.io) and iTunes or the Apple Devices app installed.
- An iPhone on iOS 17 or later, a cable, and an Apple ID.

## Build the app in the cloud

1. Push this folder to a GitHub repository.
2. Open the repository on github.com and go to the **Actions** tab. The **Build** workflow starts on every push. You can also start it by hand with **Run workflow**.
3. When the run finishes, open it and download the artifact named **3uToolsMobile-ipa**. Unzip it to get `3uToolsMobile.ipa`.

The workflow also runs the unit tests. The `.ipa` is uploaded before the tests run, so you still get the app if a test fails. If the build itself fails, download the **logs** artifact and look for lines containing `error:` in `build.log`.

GitHub gives private repositories a limited number of free Mac build minutes each month (Mac minutes count ten times). Public repositories build for free.

## Install on your iPhone from Windows

1. Connect the iPhone by cable and tap **Trust** on the phone.
2. Open Sideloadly, drag `3uToolsMobile.ipa` into it, enter your Apple ID and press **Start**. Your password goes only to Sideloadly and Apple.
3. On the phone, open **Settings > General > VPN & Device Management**, tap your Apple ID and tap **Trust**.
4. On iOS 16 or later, turn on **Settings > Privacy & Security > Developer Mode** and restart when asked.
5. Open **3uTools Mobile** from the Home Screen.

With a free Apple ID the app stops opening after 7 days. Repeat step 2 to renew it; your data in the app is kept.

## Build on a Mac instead

```
brew install xcodegen
xcodegen generate
open ThreeUTools.xcodeproj
```

Select your iPhone, choose your team under **Signing & Capabilities**, and press **Run**.

## Checking the app by hand

The unit tests cover the logic. These need a real phone:

- **Home**: model, iOS version, battery ring and storage ring show values that match the Settings app.
- **Device > Battery**: plug the charger in and out; the state changes and a charging session appears.
- **Device > Storage**: "Analyse photo library" asks for photo access, then shows counts and an estimated size.
- **Photos**: grid loads, a photo zooms, a video plays, Select then delete asks twice and removes the item.
- **Location**: see "Testing Virtual Location on the phone" below.
- **Toolbox**: the speed test finishes with three numbers, the QR scanner reads a code, Files opens and previews a document, the device report can be shared.

## What the app cannot do, by design of iOS

| Feature | Why |
|---|---|
| Change the GPS location other apps receive | iOS has no public feature for this. The Location tab sets a virtual location for this app only. |
| Battery health, cycle count | Not shared with apps. See Settings > Battery > Battery Health. |
| List of all installed apps and their sizes | Not shared with apps. The Apps screen checks a fixed list of well-known apps. |
| Clearing other apps' caches or system files | Not possible. See Settings > General > iPhone Storage. |
| Wi-Fi network name | Needs a capability that free Apple ID signing does not include. |
| Screen Time and app usage | Needs the Family Controls capability, also unavailable with free signing. |
| Hardware tests (screen, speakers, sensors) | iOS has no such interface. Diagnostics shows whether each part is reported as present. |
| The name you gave the phone | Since iOS 16 apps receive the generic name "iPhone". |


## Virtual Location

The Location tab works on the iPhone alone. It needs no computer, cable, pairing file or other app.

What it does:

- Search by city, address or place, type a latitude and longitude, or tap the map to drop a pin. Drag the pin to adjust it.
- Shows the pin's coordinates, address and distance from your actual position (when location access is allowed).
- **Set virtual location** makes that place the location this app uses: the map reopens there, searches look around it, and the Home screen shows it. It is saved and is still set when you reopen the app.
- **Restore** returns the app to your actual location.
- Favourites, history and recent places are stored on the phone.
- Directions open in Apple Maps; Copy puts the coordinates on the clipboard; + and − zoom the map.

What it does not do: it does not change the GPS location that other apps receive. iOS has no public feature for that. Apple provides location simulation only as a developer testing tool driven from a computer, with the phone in Developer Mode. This app does not include or depend on that.

The code is split into five managers in `Features/Location/LocationManagers.swift`:

| Manager | Responsibility |
|---|---|
| `VirtualLocationManager` | Holds, validates, saves and restores the virtual location |
| `MapLocationManager` | Camera, selected pin, zooming, directions |
| `LocationSearchManager` | Place and address search, coordinate input, reverse lookup |
| `LocationHistoryManager` | History, recent places and favourites |
| `LocationPermissionManager` | Location permission and the phone's actual position |

### Testing Virtual Location on the phone

1. Install the app fresh, with nothing else set up and the phone not connected to a computer.
2. Open the Location tab. Allow location access when asked; the blue dot appears.
3. Search for a city. Pick a result; the map moves there and a pin appears.
4. Tap elsewhere on the map; the pin moves there and its address fills in. Drag the pin; it follows your finger and the address updates when you let go.
5. Tap "Enter latitude and longitude", type `19.0760` and `72.8777`, tap Go; the pin moves to Mumbai.
6. Tap the star; open the clock button (top right) and check the place is under Favourites.
7. Tap **Set virtual location**; the banner appears and the Home tab shows the place under "App location".
8. Close the app completely and reopen it; the virtual location is still set.
9. Tap **Restore**; the banner disappears and the map returns to the blue dot.
10. In Settings, turn location access off for the app; the tab still works, and it explains that only your actual position and distances are hidden.
11. Turn on Airplane Mode and search; the app says search needs the internet. Typing coordinates and tapping the map still work, though map tiles that were not loaded before stay blank.

## Project layout

```
project.yml            XcodeGen project description (the .xcodeproj is generated from it)
.github/workflows/     Cloud build
App/                   App entry point and the five-tab root view
Core/                  Design system, shared components, services, storage models, utilities
Features/              One folder per area: Home, Device, Photos, Location, Diagnostics, Toolbox
Resources/             App icon and colours
Tests/                 Unit tests
Tools/make-icon.ps1    Redraws the app icon
docs/                  Design document
```

The app follows MVVM: views are SwiftUI, view models are `@Observable` classes, and device access sits in services behind protocols so view models can be tested with fakes.

To add an app to the Apps screen, add it to `KnownApp.catalog` in `Features/Device/AppsView.swift` and add its URL scheme to `LSApplicationQueriesSchemes` in `project.yml`.

## If you ever want TestFlight or the App Store

This project is set up for personal use. A public release would need, at minimum:

- A paid Apple Developer Program membership and a Mac (or a cloud signing service) to sign and upload builds.
- A different name and icon. "3uTools" belongs to another company and Apple rejects look-alike branding.
- Removing the undocumented photo file-size reading in `PhotoStatsService`, and the fixed-list app detection, which App Review may question.
- A privacy manifest (`PrivacyInfo.xcprivacy`) declaring the use of disk space, system boot time and file timestamp APIs, plus a hosted privacy policy.
- Screenshots and App Store listing text.
