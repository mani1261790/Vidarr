# Vidarr — macOS Browser Prototype

Vidarr is a lightweight, experimental macOS web browser prototype. The goal is to explore fast tab management, clean navigation, and gesture-driven interactions inspired by Sleipnir.

## Project Purpose
- Prototype a modern, minimal macOS browser architecture
- Experiment with responsive tab/session management
- Validate Sleipnir-style gesture navigation for power users

## Build & Run (Xcode)
1. Open the project in Xcode (Xcode 15+ recommended).
2. Select the macOS app target.
3. Choose a My Mac destination.
4. Build (⌘B) to verify.
5. Run (⌘R) to launch the app.

If you encounter missing dependencies, resolve Swift Package Manager packages via File > Packages > Resolve Package Versions.

## Planned Sleipnir-Style Gestures
- Back/Forward: Two-finger swipe left/right across the web content view
- Switch Tabs: Two-finger swipe on the tab bar area (left/right)
- Close Tab: Pinch-in gesture over the tab to close
- Reopen Closed Tab: Pinch-out gesture on the tab bar
- Reload: Double-tap with two fingers on the page

These gestures are subject to iteration as we refine ergonomics and platform conventions.

## Repository Hygiene
- Standard Xcode .gitignore is included to avoid build outputs and user-specific files.
- Please avoid committing DerivedData, build artifacts, or personal Xcode settings.

## License
TBD
