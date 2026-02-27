# Add field labels to distinguish Hooks Bearer Token vs Gateway Bearer Token (zaap-1ze)

## Changes

- **SettingsView.swift**: Added persistent `Text` labels above each token field in the Server section:
  - "Hooks Bearer Token" label with `.caption` font and `.secondary` style above the hooks auth token field
  - "Gateway Bearer Token" label with `.caption` font and `.secondary` style above the gateway token field
  - Changed placeholder text from full names to just "Token" since the labels now provide context
  - Wrapped each token field HStack in a VStack with the label

- **SettingsViewTests.swift** (new): Added test verifying label property values exist and match expected strings

- **project.pbxproj**: Added SettingsViewTests.swift to the test target

## Notes

- Pre-existing test compilation errors in VoiceChatCoordinatorTests.swift, ResponseSpeakerTests.swift, and TestDoubles.swift prevent running the full test suite. These are unrelated to this change.
- App build (`xcodebuild build`) succeeds, confirming the UI changes compile correctly.
