# Vidarr (macOS AppKit Browser Prototype)

## Purpose
Vidarr is a macOS AppKit-based browser prototype exploring gesture-driven navigation on top of WKWebView. The project focuses on a minimal, clean architecture (TabManager, BrowserSession, ActionCenter) and a transparent overlay to capture Magic Mouse gestures.

## How to Run
1. Open the Xcode project in Xcode 15+.
2. Select the "Vidarr" scheme and a My Mac (macOS) destination.
3. Press Run. The app will open a window and load https://www.google.com in the first tab.

## Planned Gesture List (prototype)
- Horizontal swipe (Left/Right): switch tabs
- "L" shape: close tab
- "U" shape: reopen last closed tab
- Circle (O): reload current tab
- Double circle (OO): reload all tabs
- Up-Right / Up-Left: back / forward navigation
- "S": focus search/address field

Note: The gesture recognizer is experimental and under active iteration.

## Branch Workflow
- main: protected (no direct pushes). Use PRs only.
- feature/*: create a feature branch per task (e.g., `feature/overlay-gesture`), push commits, and open a PR into main.

## Security & Secrets
- Do NOT commit signing certificates, provisioning profiles, or any secrets.
- The repository includes a .gitignore that excludes DerivedData, build products, xcuserdata, and common macOS/Xcode artifacts.
