# JelPoskupilo Mobile Wrappers

Native wrapper apps for `https://jelposkupilo.eu`:
- `ios/`: Xcode project (`UIKit` + `WKWebView`)
- `android/`: Android Studio project (`Kotlin` + `WebView`)

## URL configuration
- iOS Debug: `http://localhost:3000`
- iOS Release: `https://jelposkupilo.eu`
- Android Debug: `http://10.0.2.2:3000` (Android emulator host mapping to your Mac)
- Android Release: `https://jelposkupilo.eu`

## iOS
- Open project: `open ios/App/App.xcodeproj`
- Run Debug from Xcode (`App` scheme).
- Base URL is configured through `ios/debug.xcconfig` and Release build settings.

## Android
- Open in Android Studio: `android/`
- CLI debug build:
  - `cd android`
  - `./gradlew :app:assembleDebug`

## Notes
- Both apps are host-allowlisted to `jelposkupilo.eu` (and localhost variants in Debug).
- External or unsupported URLs open outside the app via system handlers.
