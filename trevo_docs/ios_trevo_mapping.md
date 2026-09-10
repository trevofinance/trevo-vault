# Android → iOS Trevo Mapping

| Category | Android files | iOS files | Notes |
| --- | --- | --- | --- |
| Branding/Identity | `android/build.gradle`, `android/src/main/res/values/strings.xml` | `ios/PolkadotVault/Info.plist`, `ios/PolkadotVault/Configuration/*.xcconfig`, `ios/PolkadotVault/Resources/en.lproj/Localizable.strings`, `ios/PolkadotVault/Stubs/Stubs+Signer.swift`, `ios/PolkadotVault/Previews/Stubs+Signer.swift` | Renamed app and updated bundle ID and user-facing strings |
| Network/Metadata | `android/src/main/res/drawable/network_trevo.png`, `rust/defaults/release_metadata/trevo-asset-hub1011` | `ios/PolkadotVault/Resources/ChainIcons.xcassets/trevo-asset-hub.imageset` | Added Trevo network icon |
| Texts (EULA/Privacy) | `android/src/main/java/io/parity/signer/components/documents/PP.kt`, `android/src/main/java/io/parity/signer/components/documents/TOS.kt` | `ios/PolkadotVault/Resources/Docs/privacy-policy.txt`, `ios/PolkadotVault/Resources/Docs/terms-and-conditions.txt` | Copied Trevo legal texts |
| Styles/Palette | `android/src/main/java/io/parity/signer/ui/theme/Color.kt` | `ios/PolkadotVault/Resources/Assets.xcassets/*accent_pink*.colorset`, `ios/PolkadotVault/Resources/Assets.xcassets/network_colors/pink*.colorset` | Recolored accent palette to black |
| Strings/Links | `android/src/main/res/values/strings.xml` | `ios/PolkadotVault/Resources/en.lproj/Localizable.strings` | Updated links to Trevo resources |

*App icons for Trevo were not available in the repository and remain unchanged.*
