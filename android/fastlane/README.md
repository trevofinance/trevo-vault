fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Android

### android prepare_database

```sh
[bundle exec] fastlane android prepare_database
```

Regenerate the cold chain database baked into the app

Usage: fastlane prepare_database

### android verify_aab

```sh
[bundle exec] fastlane android verify_aab
```

Verify the built AAB: signature, ABI coverage, 16 KB alignment, native lib, embedded database

Usage: fastlane verify_aab

### android build_release

```sh
[bundle exec] fastlane android build_release
```

Build the signed release AAB (regenerates the database first, then verifies)

Usage: fastlane build_release [clean:true]

### android upload_internal

```sh
[bundle exec] fastlane android upload_internal
```

Upload an already-built AAB to the Play internal testing track

Usage: fastlane upload_internal [validate_only:true] [rollout:true]

### android release_internal

```sh
[bundle exec] fastlane android release_internal
```

Build, verify and upload to Play internal testing

Usage: fastlane release_internal [clean:true] [validate_only:true] [rollout:true]

### android play_status

```sh
[bundle exec] fastlane android play_status
```

Check the Play service-account credentials and show current track state

Usage: fastlane play_status

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
