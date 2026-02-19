# zaap-7xm: Xcode Project Scaffolding

## Deliverable

Created a complete Xcode project at `Zaap/` with:

- **Bundle ID:** `com.openclaw.zaap`
- **Deployment target:** iOS 17.0
- **Framework:** SwiftUI only, no third-party dependencies
- **Info.plist entries:**
  - `NSLocationWhenInUseUsageDescription`
  - `NSLocationAlwaysAndWhenInUseUsageDescription`
  - `UIBackgroundModes` → `location`

### Project Structure

```
Zaap/
├── Zaap.xcodeproj/
│   └── project.pbxproj
└── Zaap/
    ├── ZaapApp.swift          # @main entry point
    ├── ContentView.swift      # Placeholder root view
    ├── Info.plist              # Location permissions + background modes
    ├── Assets.xcassets/        # App icon, accent color
    └── Preview Content/
        └── Preview Assets.xcassets/
```

### Notes

- `xcodebuild` not available on this machine (no full Xcode install), but `plutil -lint` confirms the project file is valid
- Background location mode enabled in Info.plist for future significant location change monitoring
- Automatic code signing configured
