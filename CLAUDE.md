# Location Spoofer - iOS Location Spoofing Tool

## Project Overview
Fork of acheong08/ios-location-spoofer, backported from Joy-cwz/ios-location-spoofer with fixes and feature improvements
while reverting the rebranding back to "Location Spoofer" with English UI.

## Tech Stack
- Swift / SwiftUI / iOS native
- MapKit + CoreLocation
- Network Extension (VPN)
- XcodeGen (project.yml)
- GitHub Actions cloud build + TestFlight distribution

## Key Files
- App/ContentView.swift — Entry point (routes to FirstSetupView or MapHomeView)
- App/MapHomeView.swift — Main map interface (location spoofing + status + favorites)
- App/FirstSetupView.swift — First-time setup flow (VPN auth + certificate install + trust)
- App/CoordinateInputView.swift — Location picker (map selection + search + favorites)
- App/CoordinateConverter.swift — GCJ-02/WGS-84 coordinate conversion
- App/LocationConfiguration.swift — Coordinate storage config
- App/SpoofingState.swift — Spoofing state machine (off/pending/on/failed)
- App/DiagLog.swift — Diagnostics log collector
- App/SettingsView.swift — Settings + diagnostics panel
- App/CertificateInstaller.swift — Certificate install via Safari intercept
- Resources/Info.plist — App display name "Location Spoofer", ATS exception
- project.yml — XcodeGen config (bundle id: dev.duti.location-spoofer)
- .github/workflows/build.yml — CI build + TestFlight upload

## Editing Rules
- This is a Swift project, prefer sed for text replacement to avoid Edit tool issues
- For large changes, use Write tool to overwrite entire files
- All user-visible text is in English
- Do not modify Tunnel/ and GoSpoofer/ core logic unless necessary
- Commit then push together to reduce build count
