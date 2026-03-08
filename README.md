# RideMetricX

[![Flutter CI](https://github.com/azizbahri/RideMetricX/actions/workflows/flutter.yml/badge.svg)](https://github.com/azizbahri/RideMetricX/actions/workflows/flutter.yml)
[![Build Windows](https://github.com/azizbahri/RideMetricX/actions/workflows/flutter.yml/badge.svg?job=build-windows)](https://github.com/azizbahri/RideMetricX/actions/workflows/flutter.yml)
[![Build Android](https://github.com/azizbahri/RideMetricX/actions/workflows/flutter.yml/badge.svg?job=build-android)](https://github.com/azizbahri/RideMetricX/actions/workflows/flutter.yml)
[![Build iOS](https://github.com/azizbahri/RideMetricX/actions/workflows/flutter.yml/badge.svg?job=build-ios)](https://github.com/azizbahri/RideMetricX/actions/workflows/flutter.yml)

Cross-platform (X) motorcycle suspension tuning simulator built with Flutter,
targeting Windows, Android, and iOS.

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.22 (stable channel)
- Dart ≥ 3.3

### Run the app

```bash
# Install dependencies
flutter pub get

# Run on connected device / emulator
flutter run

# Run on a specific platform
flutter run -d windows
flutter run -d android
flutter run -d ios
```

### Test

```bash
# Run all widget and unit tests
flutter test

# Analyze code for issues
flutter analyze
```

### Build

```bash
# Android APK
flutter build apk

# iOS (requires macOS + Xcode)
flutter build ios

# Windows
flutter build windows
```

## Project Structure

```
RideMetricX/
├── lib/
│   └── main.dart          # App entry point & home screen
├── test/
│   └── widget_test.dart   # Smoke tests
├── android/               # Android platform config
├── ios/                   # iOS platform config
├── windows/               # Windows platform config
├── docs/                  # Architecture & requirements docs
├── pubspec.yaml
└── README.md
```

## CI

A GitHub Actions workflow (`.github/workflows/flutter.yml`) runs on every push
and pull request. It:

1. Sets up Flutter (stable channel)
2. Runs `flutter pub get`
3. Checks formatting with `dart format`
4. Runs `flutter analyze`
5. Runs `flutter test`
6. Builds for **Windows** (`windows-latest` runner)
7. Builds for **Android** APK (`ubuntu-latest` runner)
8. Builds for **iOS** without code signing (`macos-latest` runner)

