# Turnaround — Flutter project

Airport ground-operations game built with Flutter and Flame. Source handoff: 2 October 2026.

## Included

- Complete Dart source and original graphics.
- Six missions across three airports, road traffic, aircraft towing and service animations.
- English and German UI, editable player profile, avatar import, local campaign progress and latest 50 shift results.
- iOS Xcode project, web target, tests, design and implementation notes.
- `pubspec.lock` with the resolved dependency versions.

## Run

Verified toolchain: Flutter 3.29.1 / Dart 3.7.0. Flame 1.30.1.
Install Flutter and add its `bin` directory to PATH, then run from this folder:

```sh
flutter pub get
flutter run -d chrome
```

For a web release:

```sh
flutter build web --release
python3 -m http.server 8643 --bind 127.0.0.1 --directory build/web
```

Open http://127.0.0.1:8643.

## iOS

Requires macOS, Xcode, an iOS simulator and CocoaPods. Run `flutter pub get` first.

```sh
flutter devices
flutter run -d <ios-device-id>
```

For a physical device or distribution, open `ios/Runner.xcworkspace` in Xcode and configure your own Apple Developer team, signing and bundle identifier. Certificates and provisioning profiles are not included. App Store release preparation is not complete.

The Android platform folder is not included in this handoff; Google Play preparation is a separate planned step. Shared game code is in `lib/`.

## Verify

```sh
flutter analyze
flutter test
```

The full suite passed 50 tests during the profile update; the subsequent service-card proportions fix passed the eight relevant UI tests and static analysis. The web release was built successfully.

## Project map

- `lib/main.dart`: game UI and service cards.
- `lib/game/`: simulation, missions, roads, graphics, campaign and local player data.
- `lib/profile_screen.dart`: player profile and avatar import.
- `lib/l10n/`: English/German display copy.
- `assets/`: game graphics and original concept.
- `test/`: simulation, routing, localization, persistence and UI checks.
- `docs/`: design history and implementation notes; older plans may describe earlier versions.

Progress and profile data are local to each device/browser. There is no account backend or cloud synchronization. Build output, caches, Git history, IDE settings and hosting account configuration are intentionally omitted. Flutter regenerates platform-specific temporary files after dependency installation.
