# jelposkupilo-mobile Agent Guide

## Scope
- This file applies to everything under `jelposkupilo-mobile/`.
- Keep changes limited to this repo unless explicitly requested.

## Project Layout
- `android/`: native Android app (Kotlin + WebView).
- `ios/JelPoskupilo/`: native iOS app (`JelPoskupilo.xcodeproj`, Swift + WKWebView).

## Default Run Targets
- iOS simulator default: `iPhone 17 Pro` unless explicitly requested otherwise.
- iOS project/scheme:
  - Project: `ios/JelPoskupilo/JelPoskupilo.xcodeproj`
  - Scheme: `JelPoskupilo`

## Build Commands
- Android debug: `cd android && ./gradlew :app:assembleDebug`
- Android release bundle: `cd android && ./gradlew :app:bundleRelease`
- iOS build (simulator):  
  `xcodebuild -project ios/JelPoskupilo/JelPoskupilo.xcodeproj -scheme JelPoskupilo -configuration Debug -destination 'id=<SIM_UDID>' build`

## URL Configuration
- iOS Debug URL comes from `ios/debug.xcconfig` (currently localhost).
- iOS Release URL is set in `project.pbxproj` (`BASE_URL = "https://jelposkupilo.eu"`).
- Android Debug URL is `http://10.0.2.2:3000`.
- Android Release URL is `https://jelposkupilo.eu`.

## Versioning Preference
- When user says `increment version`, only increment:
  - Android `versionCode` in `android/app/build.gradle`
  - iOS `CURRENT_PROJECT_VERSION` in `ios/JelPoskupilo/JelPoskupilo.xcodeproj/project.pbxproj`
- Do not change:
  - Android `versionName`
  - iOS `MARKETING_VERSION`
- unless explicitly requested.

## Android Signing and Deobfuscation
- Local signing config file: `android/keystore.properties` (ignored by git).
- Template: `android/keystore.properties.example`.
- Release minification is enabled (R8).
- Mapping outputs:
  - `android/app/build/outputs/mapping/release/mapping.txt`
  - `android/app/build/outputs/mapping/release/mapping-v<versionCode>.txt`

## Secrets and Generated Files
- Never commit keystore credentials/files:
  - `android/keystore.properties`
  - `android/keystore/`
  - `*.jks`, `*.keystore`

## Brand Colors
- Primary/brand red: `#C21A0F`

