fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios asc_status

```sh
[bundle exec] fastlane ios asc_status
```

Verify the App Store Connect API key and show the latest TestFlight build number

Usage: fastlane asc_status

### ios provisioning_profiles

```sh
[bundle exec] fastlane ios provisioning_profiles
```

Fetch or create an App Store provisioning profile for an installed signing identity

Usage: fastlane provisioning_profiles

### ios build_testflight

```sh
[bundle exec] fastlane ios build_testflight
```

Archive and export the App Store IPA (no upload)

Usage: fastlane build_testflight [clean:true]

### ios upload_testflight

```sh
[bundle exec] fastlane ios upload_testflight
```

Upload the built IPA to TestFlight

Usage: fastlane upload_testflight

### ios release_testflight

```sh
[bundle exec] fastlane ios release_testflight
```

Build and upload to TestFlight

Usage: fastlane release_testflight [clean:true]

### ios build_simulator

```sh
[bundle exec] fastlane ios build_simulator
```

Build debug for the iOS Simulator (no code signing)

Usage: fastlane build_simulator [device:'iPhone 16']

### ios unit_tests

```sh
[bundle exec] fastlane ios unit_tests
```

Run unit tests on the simulator

Usage: fastlane unit_tests [device:'iPhone 16']

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
