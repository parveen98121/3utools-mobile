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
- **Location**: the blue dot appears after allowing location, tapping the map drops a pin with an address, the star saves a favourite, Restore removes the pin.
- **Toolbox**: the speed test finishes with three numbers, the QR scanner reads a code, Files opens and previews a document, the device report can be shared.

## What the app cannot do, by design of iOS

| Feature | Why |
|---|---|
| Change the GPS location for other apps | Not possible for an App Store-style app. A map pin is only a marker inside this app. |
| Battery health, cycle count | Not shared with apps. See Settings > Battery > Battery Health. |
| List of all installed apps and their sizes | Not shared with apps. The Apps screen checks a fixed list of well-known apps. |
| Clearing other apps' caches or system files | Not possible. See Settings > General > iPhone Storage. |
| Wi-Fi network name | Needs a capability that free Apple ID signing does not include. |
| Screen Time and app usage | Needs the Family Controls capability, also unavailable with free signing. |
| Hardware tests (screen, speakers, sensors) | iOS has no such interface. Diagnostics shows whether each part is reported as present. |
| The name you gave the phone | Since iOS 16 apps receive the generic name "iPhone". |

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
