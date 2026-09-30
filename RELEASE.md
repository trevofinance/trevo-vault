# Trevo Vault — Release Runbook

How to build, bump and ship Trevo Vault to Google Play and the App Store.

Related docs:

- Metadata pipeline in depth → [`trevo_docs/WHAT_TO_KEEP.md`](trevo_docs/WHAT_TO_KEEP.md) and
  [`trevo_assets/update_metadata.md`](trevo_assets/update_metadata.md)
- iOS store-listing copy and App Review notes → [`trevo_docs/ios_appstore_release_roadmap.md`](trevo_docs/ios_appstore_release_roadmap.md)

---

## What makes this app different

Trevo Vault is an **air-gapped** signer. The phone is assumed to never touch the internet after
install. Two consequences dominate the release process:

1. **The app ships with a pre-built "cold" database** containing the Trevo Asset Hub chain spec and
   the current runtime metadata. The DB is a **build artifact, not committed to git** — it is
   generated from the hex metadata in
   [`rust/defaults/release_metadata/`](rust/defaults/release_metadata/). Ship a stale one and users
   cannot decode transactions.
2. **Metadata updates are distributed as signed QR codes**, generated separately and published
   outside the app. A release that bumps metadata must ship a matching QR.

So a release is really *three* artifacts that must agree on a runtime version: the Android build,
the iOS build, and the metadata QR PNG.

Current shipped metadata: **`trevo-asset-hub1011`** (runtime spec version 1011).

---

## 1. Open a release shell

```bash
cd /Users/victor/dev/trevo/wt-vault-app-release
export PATH="$HOME/.cargo/bin:$PATH"
```

Verify the toolchain:

```bash
java -version        # 17.x  (Zulu 17 — AGP 8.13 needs 17+; do NOT let Corretto 8 win)
ruby -v              # 3.3.6
cargo --version      # 1.97.x
xcodebuild -version  # Xcode 26.x

bundle install                   # installs into ./vendor/bundle (~1m first time)
bundle exec fastlane --version   # 2.229.1
```

There is no `.ruby-version` and no `.nvmrc`; iOS uses SPM, so no Node or CocoaPods.

> **Always `bundle exec fastlane`**, never bare `fastlane` — the pinned version is 2.229.1 and a
> globally-installed gem may differ. `bundle install` writes only to `./vendor/bundle`
> (`~/.bundle/config` sets `path: vendor/bundle`), so nothing on the Mac changes globally. If a
> future Bundler ever refuses the lockfile: `gem install bundler -v 2.4.22 && bundle _2.4.22_ install`.

---

## 2. First-time machine setup

Skip this on a machine that is already set up.

### Signing material

Everything sensitive lives **outside the repo**, in `~/dev/secure/trevo-wallet-signing/` — shared
with the Trevo Wallet app:

```text
my-upload-key.keystore     Android upload key (alias my-key-alias)
AuthKey_X2TZ9NDANA.p8      App Store Connect API key (iOS upload + signing)
Distribution.p12           Apple Distribution certificate
Development.p12
```

The current Sr25519 metadata-verifier keypair is stored separately at
`~/dev/secure/trevo-vault-metadata-verifier-staging/metadata_verifier.txt`. Keep this file at mode
`0600`, offline when it is not being used, and backed up independently. Its public key is the
`DEFAULT_VERIFIER_PUBLIC` value compiled into the app; its secret phrase must never enter git.

> Rotating `DEFAULT_VERIFIER_PUBLIC` changes the app's trust root. Existing initialized Vaults do
> not accept updates signed by a different verifier; users migrating from an older verifier must
> wipe/reset the Vault or remove the old general certificate and explicitly establish the new one.

> ⚠️ **Not in version control — back it up** (a password manager is fine). Losing any of it blocks
> releases for days. Apple will not re-issue a `.p8`; a lost upload key needs a Play Console
> upload-key reset (a couple of business days, existing users unaffected).

Android also needs `~/.gradle/gradle.properties` pointing Gradle at the keystore:

```properties
MYAPP_UPLOAD_STORE_FILE=/Users/<you>/dev/secure/trevo-wallet-signing/my-upload-key.keystore
MYAPP_UPLOAD_KEY_ALIAS=my-key-alias
MYAPP_UPLOAD_STORE_PASSWORD=<password>
MYAPP_UPLOAD_KEY_PASSWORD=<password>
```

and the Play service-account JSON at `~/.gradle/google-play-credentials.json` (override with
`PLAY_JSON_KEY`).

Import the `.p12`s into the **login Keychain** (double-click). Confirm:

```bash
security find-identity -v -p codesigning
# must list: Apple Distribution: TRAIT TECH PTE LTD (9NMWDV6M74)
```

### Toolchain

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
export PATH="$HOME/.cargo/bin:$PATH"

# Android + iOS cross-compilation targets
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios

# UniFFI — version MUST match `uniffi = "0.22.0"` in rust/signer/Cargo.toml
cargo install uniffi_bindgen --version 0.22.0
```

Also required: Android SDK with **NDK 28.2.13676358** (the `ndkVersion` in `android/build.gradle`),
and `subkey` on PATH if you will generate metadata QRs (§4).

> Rust is **unpinned** (no `rust-toolchain.toml`). This is a 2022-era Substrate fork, so a future
> stable could break compilation. If a build stops compiling after `rustup update`, pin it:
> `rustup toolchain install 1.97.1 && rustup override set 1.97.1`.

### Android Studio and PATH

Gradle shells out to `cargo` and `uniffi-bindgen`. Android Studio launched from the Dock inherits a
minimal environment without them and fails with "no such file or directory". Launch it from a
terminal instead:

```bash
./launch_android_studio.sh
```

(Or set absolute `rust.cargoCommand` / `rust.uniffiBindgenCommand` in `android/local.properties` —
see [`trevo_docs/ANDROID_BUILD_TROUBLESHOOTING.md`](trevo_docs/ANDROID_BUILD_TROUBLESHOOTING.md).)

---

## 3. Start from a clean tree

```bash
git checkout trevo && git pull
git status --short     # must print nothing
```

The working branch is **`trevo`** (not `master`, which mirrors upstream). Remote is
`git@github.com:trevo-finance/trevo-vault.git`.

### Rust sanity check

This is a **compile check**, not a pass/fail gate. Run the whole workspace, minus the one desktop
crate that needs OpenCV:

```bash
cd rust
export DYLD_FALLBACK_LIBRARY_PATH="$(xcode-select --print-path)/Toolchains/XcodeDefault.xctoolchain/usr/lib/"
cargo test --locked --workspace --exclude qr_reader_pc --no-fail-fast
cd ..
```

Expected: **158 passed, 118 failed**. Every failure is the same cause — the fork dropped
Polkadot/Kusama/Westend from the network list but the inherited upstream tests/fixtures still
reference them, so any test that loads `defaults::test_metadata()` panics with `OrphanMetadata` (103)
/ `NetworkSpecsNotFound` (3), with 9 downstream assertion failures on top. None involve Trevo code.
The count is deterministic and independent of `rust/database` (these tests build in-memory DBs). The
test that matters — `defaults::can_get_release_metadata`, which parses Trevo's actual shipped
metadata — **passes**.

The 12 failing test targets, and their counts:

| Target | pass / fail |
|---|---|
| `db_handling --test tests` | 15 / 35 |
| `defaults --lib` | 2 / 2 |
| `generate_message` integration (`add_specs`, `load_metadata`, `load_types`, `make`, `remove`, `show`, `unwasm`) | 0 / 10 |
| `navigator --lib` | 1 / 8 |
| `transaction_parsing --lib` | 9 / 42 |
| `transaction_signing --lib` | 9 / 21 |

**Stop only if the failure count climbs above 118**, or one of the all-passing crates starts
failing: `constants`, `definitions`, `generate_message --lib`, `parser`, `printing_balance`,
`qr_reader_phone`, `signer`, `qrcode_rtx`, `qrcode_static` (and all doc-tests).

> `qr_reader_pc` is excluded because it depends on `opencv`/`libclang` and is not part of either
> mobile app. Do **not** test a single crate with `-p` — `resolver = "1"` drops feature unification
> and floods you with unrelated `sp-io` errors (`cannot find wasm32 in arch`). Always test the whole
> workspace.

---

## 4. Refresh chain metadata (only if the runtime changed)

**Skip this whole section unless the Trevo Asset Hub runtime was upgraded.** Compare the on-chain
`spec_version` against the filename in `rust/defaults/release_metadata/` (currently
`trevo-asset-hub1011`).

This is the **only online step** — it talks to `wss://rpc.api.trevo.finance`. Everything after is
offline.

### 4a. Verify the genesis hash

The genesis hash is baked into `rust/defaults/src/lib.rs` and changes if the chain is reset. A wrong
one bricks signing.

```bash
# expected: 6d32fee54448c79868e083fc2179f662edc8a348c8b3c92407056f2ef286ea31
grep -n "genesis_hash\|base58prefix\|wss://" rust/defaults/src/lib.rs
```

Cross-check against the live chain (`chain_getBlockHash(0)`). If it differs, fix `lib.rs` first.
`rust/defaults/src/lib.rs` is the source of truth.

### 4b. Fetch and install the new metadata

`NNNN` = the new spec version. There is an automated wrapper
[`trevo_assets/update_metadata.sh`](trevo_assets/update_metadata.sh); the manual equivalent:

```bash
cd rust/generate_message
cargo run --locked load-metadata -d -u wss://rpc.api.trevo.finance
ls ../files/in_progress/sign_me_load_metadata_trevo-asset-hubV*
cd ../..

xxd -p rust/files/in_progress/sign_me_load_metadata_trevo-asset-hubVNNNN | tr -d '\n' > /tmp/meta.hex
sed -E 's/^.{8}/0x/' /tmp/meta.hex > rust/defaults/release_metadata/trevo-asset-hubNNNN
rm /tmp/meta.hex

rm -f rust/defaults/release_metadata/trevo-asset-hub1011   # keep exactly ONE metadata file
```

> The payload carries a 4-byte SCALE compact-length header; strip it and replace it with `0x`.
> `update_metadata.sh` handles this automatically.
> Keep **exactly one file** in `release_metadata/`; the cold DB loads every file in that directory.

### 4c. Generate the signed metadata QR

Requires `subkey` on PATH and a `trevo_assets/.env` (see `trevo_assets/env.example`) with:

- `SIGNER_URI` — the **secret seed** of the metadata verifier key. Not in the repo. This is the most
  important secret in the project: it is the key the installed apps trust for metadata updates. Make
  sure it is backed up.
- `VERIFIER_HEX` — `0x7e177b85cefefb6e46b1fc007726ee428fe443906e94f77e4a3ae622dc135642`
  (must match `DEFAULT_VERIFIER_PUBLIC` in `rust/defaults/src/lib.rs`)

```bash
# the runtime version is a hardcoded literal at the bottom of the script — bump it by hand
sed -i '' 's/"1011"/"NNNN"/' trevo_assets/generate_qr.sh
cd trevo_assets && ./generate_qr.sh && cd ..
# => trevo_assets/load_metadata_trevo-asset-hubVNNNN.png
```

Commit the new metadata hex **and** the new QR PNG together.

If `subkey` is not on PATH, set `SUBKEY_BIN` to its executable before running the script. On the
current release machine it is
`/Users/victor/dev/trevo/polkadot-sdk-fork/target/release/subkey`.

---

## 5. Bump the version

The two platforms version independently.

| Platform | File | Fields |
|---|---|---|
| Android | `android/build.gradle` (near line 20) | `versionCode`, `versionName` |
| iOS | `ios/PolkadotVault.xcodeproj/project.pbxproj` | `CURRENT_PROJECT_VERSION` ×3, `MARKETING_VERSION` ×3 |

Store rules that decide the numbers:

- **Play rejects a `versionCode` it has already accepted.** It must exceed the highest already
  uploaded to **any** track — list them with the API check in §6d and increment.
- **App Store Connect rejects a build number it has already seen.** It must exceed the latest on
  TestFlight — check with `cd ios && bundle exec fastlane asc_status`.

The `sed` examples below use `13 → 14` and build `5 → 6`; substitute the actual current values.

```bash
# Android — edit by hand: versionCode 13 -> 14, versionName "1.0.9" -> "1.0.10"

# iOS — rewrite all three configs at once (example: 1.0.4 build 5 -> 1.0.5 build 6)
PBX=ios/PolkadotVault.xcodeproj/project.pbxproj
sed -i '' 's/MARKETING_VERSION = 1\.0\.4;/MARKETING_VERSION = 1.0.5;/g'   "$PBX"
sed -i '' 's/CURRENT_PROJECT_VERSION = 5;/CURRENT_PROJECT_VERSION = 6;/g' "$PBX"
grep -c "MARKETING_VERSION = 1.0.5;\|CURRENT_PROJECT_VERSION = 6;" "$PBX"   # expect 6
```

> `xcrun agvtool` does **not** work here — the project has no `VERSIONING_SYSTEM = "apple-generic"`.
> Use `sed`. Never run `trevo_scripts/reset_ios_version.py`; it force-writes `1.0.0 (1)` and clobbers
> the real version.

Commit and **tag every release** — it is how you later find which commit shipped as a given build:

```bash
git add android/build.gradle ios/PolkadotVault.xcodeproj/project.pbxproj
git commit -m "chore(release): Android 1.0.10 (14), iOS 1.0.5 (6)"
git tag -a v1.0.10-android-14 -m "Android 1.0.10 (14)"
git tag -a v1.0.5-ios-6       -m "iOS 1.0.5 (6)"
git push origin trevo --follow-tags
```

---

## 6. Android → Google Play

The Gradle module is `:android` (not `:app`); `gradlew` is at the **repo root**. Fastlane lanes are
in [`android/fastlane/`](android/fastlane/Fastfile) and are the supported path — **run them from
`android/`**.

```bash
cd android
bundle exec fastlane release_internal                     # build + verify + upload as a draft
```

Variants:

```bash
bundle exec fastlane release_internal validate_only:true  # full dry run — publishes NOTHING
bundle exec fastlane release_internal clean:true          # force a clean build
bundle exec fastlane build_release                        # build + verify, no upload
bundle exec fastlane upload_internal                      # upload an already-built AAB
bundle exec fastlane verify_aab                           # all local Play-safety checks
bundle exec fastlane play_status                          # check Play credentials
```

`release_internal` runs three steps; you can also do them by hand as below.

### 6a. Cold database

`build_release` regenerates it automatically. To do it manually:

```bash
cd android && ./generate_database.sh && cd ..
ls -la android/src/main/assets/Database    # blobs/, conf, db (~512 KB), snap.*
```

> ⚠️ **Never ship without this.** The DB is gitignored and the `buildDB` Gradle task is not a
> dependency of `bundle`, so a build without it carries missing or stale chain metadata — the most
> likely way to break an air-gapped release. `build_release` and `verify_aab` both guard against it.

### 6b. Build the AAB

Trevo Vault ships **App Bundles, not APKs**.

```bash
./gradlew clean :android:bundleRelease
# => android/build/outputs/bundle/release/android-release.aab
```

A clean build is ~4 min (the Rust core cross-compiles for three targets and R8 optimizes the DEX);
incremental builds are usually 1–2 min.
Signing is automatic via the `signingConfigs.release` block in `android/build.gradle`, which reads
the `MYAPP_UPLOAD_*` properties and **fails loudly** if they are missing rather than emitting an
unsigned or debug-signed bundle.

> Ignore the APK-oriented `scripts/sign_android.sh` and the `assembleRelease` step in
> `android-manual-gplay.yml` — both are inherited upstream cruft and do not reflect how this app
> ships.

### 6c. Verify the AAB

`verify_aab` hard-fails on: an unsigned bundle, a bundle signed with the **wrong key**, an ABI set
that disagrees with the cargo targets, any ABI missing `libsigner.so`, a 64-bit native library that
is not 16 KB-aligned, missing/disabled R8 optimization, a DEX obfuscation/optimization/shrinking
score below Google Play's 25% threshold, or a missing cold database. It runs automatically before
every upload. To check by hand:

```bash
AAB=android/build/outputs/bundle/release/android-release.aab

jarsigner -verify "$AAB"                                          # "jar verified." (signed at all)
keytool -printcert -jarfile "$AAB" | grep SHA256                 # must equal the upload-key SHA-256
unzip -l "$AAB" | grep 'base/lib/.*libsigner.so'                 # all THREE ABIs
unzip -l "$AAB" | grep 'base/lib/' | awk '{print $NF}' | cut -d/ -f3 | sort -u   # arm64-v8a, armeabi-v7a, x86_64
unzip -l "$AAB" | grep 'base/assets/Database/db'                 # ~524287 bytes
android/scripts/check_16kb_alignment.sh "$AAB"
android/scripts/check_dex_optimization.rb "$AAB"                # all three scores >= 25%
```

> `jarsigner -verify` only proves a bundle is self-consistently signed — a wrong or debug key passes
> it. `verify_aab` additionally asserts the signer SHA-256 equals the known upload key
> (`EXPECTED_UPLOAD_SHA256` in the Fastfile), so a bundle Play would reject is caught locally.

Confirm Gradle resolved the intended key:

```bash
./gradlew :android:signingReport --console=plain | grep -A6 "Variant: release"
# SHA1: 8C:C9:07:5B:E9:9A:65:34:E8:14:54:13:52:E1:74:02:D5:37:32:EB
```

That SHA-1 must match Play Console → App integrity → **App signing** → upload certificate.

> **`abiFilters` and `cargo { targets }` must stay in sync.** They currently list
> `armeabi-v7a, arm64-v8a, x86_64`. If an ABI appears in one but not the other, that ABI ships
> **without `libsigner.so`** and crashes on launch with `UnsatisfiedLinkError` — silently, with no
> build error. 32-bit `x86` is intentionally excluded (obsolete; Play requires 64-bit).
>
> `signingReport` also prints `Variant: debug → Missing keystore` — harmless; the debug keystore is
> auto-created on the first debug build.

### 6d. Upload

`release_internal` / `upload_internal` upload to the **internal** track as a **draft**
(`release_status: "draft"`) — the build lands but is not rolled out until a human publishes it. Pass
`rollout:true` to distribute immediately (avoid for a wallet). All store-listing uploads are skipped,
so `supply` never overwrites the live listing.

`validate_only:true` is the safe rehearsal — it uploads, validates against Google, then discards the
edit:

```text
Updating track 'internal'...
Validating all changes with Google Play...
Successfully validated the upload to Google Play
```

Then publish: **Play Console → Testing → Internal testing → review and roll out.**

Track state is a moving target — read the live values with the API (`play_status` verifies the
credentials; the JWT snippet in §6d lists tracks). A recent snapshot: production **13 (1.0.9)** is
live, with a **14 (1.0.10)** draft sitting on the internal track.

---

## 7. iOS → TestFlight

Fastlane lanes are in [`ios/fastlane/`](ios/fastlane/Fastfile) — **run them from `ios/`**.

```bash
cd ios
bundle exec fastlane asc_status          # check the API key + latest TestFlight build number
bundle exec fastlane release_testflight  # archive + export + upload   <-- the usual one
```

Individual steps:

```bash
bundle exec fastlane build_testflight       # archive + export IPA, no upload
bundle exec fastlane upload_testflight      # upload an already-built IPA
bundle exec fastlane provisioning_profiles  # refresh the AppStore profile
bundle exec fastlane build_simulator        # local sanity build, no signing
```

### 7a. Authentication

Everything authenticates with the **App Store Connect API key**
`~/dev/secure/trevo-wallet-signing/AuthKey_X2TZ9NDANA.p8` (key `X2TZ9NDANA`, issuer
`9ece21cf-d6e0-413a-89fb-84f5b3acaa0b`) — shared with Trevo Wallet, same Apple team. No Apple ID, no
2FA prompt. Confirm before doing anything expensive:

```bash
bundle exec fastlane asc_status
# => App Store Connect API key works (key X2TZ9NDANA).
# => Latest TestFlight build number for finance.trevo.vault: N
```

> **Do not add `apple_id` to the Appfile.** An Apple ID login reintroduces an interactive 2FA prompt
> on an account nobody controls. The issuer ID is a UUID — not the Team ID `9NMWDV6M74`; confusing
> the two is the usual cause of `Invalid API Key`.

### 7b. Signing

`build_testflight` calls `provisioning_profiles` first, which fetches and installs
`TrevoVault_AppStore` through the API key — no manual `.mobileprovision` handling. It then pins
manual signing (profile, identity `Apple Distribution`, bundle ID `finance.trevo.vault`) on the
Release configuration.

> ⚠️ The profile in `ios/sign/` **expires 2026-08-14**. `provisioning_profiles` renews it when it
> can; if signing fails, check the expiry first. (The profiles installed system-wide are for
> `finance.trevo.wallet` — harmless; the lane installs the Vault's own.)
>
> `build_testflight` writes signing settings into `project.pbxproj`. That is intentional — it keeps
> archives reproducible — but leaves `git status` dirty. Review and commit that diff once; it then
> stays stable.

### 7c. Build

The cold database and `libsigner.a` are produced by Xcode run-script build phases
(`ios/scripts/generate_database.sh`, `ios/scripts/build_libsigner.sh`), so there is no separate DB
step. Rebuilding the Rust core takes **10–20 minutes**; if `libsigner.a` is unchanged it is skipped
(~8 min). Artifacts land in `ios/build/` (`TrevoVault.xcarchive`, `TrevoVault.ipa`).

> A clean checkout resolves ~10 Swift Package Manager dependencies over the network on the first
> build. The app is air-gapped; the build is not.
>
> **Every iOS build reformats Swift sources.** A *Run Code Formatter* (SwiftFormat) build phase
> rewrites files in place, so `git status` shows modified `.swift` files after any build — cosmetic
> only. Discard before committing a release:
> `git checkout -- ios/PolkadotVault ios/PolkadotVaultTests ios/Packages`.

### 7d. Upload

`upload_testflight` uses the API key and does **not** wait for Apple's processing or auto-distribute
to testers.

```text
Ready to upload new build to TestFlight (App: 6759246669)...
Successfully uploaded the new binary to App Store Connect
```

Then: **App Store Connect → Trevo Vault → TestFlight** — wait for processing (a few minutes to ~an
hour; `asc_status` only shows a build once processed), then add it to a tester group.

> **The app is iPhone-only** (`TARGETED_DEVICE_FAMILY = 1`). Keep it that way: it is portrait-only,
> and an iPad-targeted (`"1,2"`) build is rejected with **error 90474** unless it declares all four
> orientations, which the portrait SwiftUI layouts do not support.

---

## 8. Smoke test before promoting

Install from **Play internal testing / TestFlight** — not from Android Studio or Xcode. Uninstall any
local dev build first. Test on at least one **real device** per platform; the simulator cannot scan
QR codes.

```text
- Cold start, no crash
- Airplane Mode ON (the production scheme enforces the air-gap check)
- Create / import a key set; verify the derived address matches a known-good address
- Chain metadata present at the expected spec version (Settings -> Networks -> Trevo)
- Sign a transaction: scan payload QR -> review decoded call -> produce signature QR
- Decoded call renders correct method names, amounts, TREVO decimals (12)
- Scan the new load_metadata QR from trevo_assets/ and confirm it is accepted
- UPGRADE from the current production version (not just a fresh install): existing DB migrates,
  existing keys survive
```

The metadata check matters most: a wrong or stale cold DB shows up as garbled transaction details —
exactly when a user signs something they cannot verify. **This is a self-custodial wallet; a bad
release can lose user funds.**

---

## 9. Production release

### Android — staged rollout

```text
Play Console -> Production -> Create new release -> Add from library
-> pick the AAB already tested on internal -> roll out to 5%
```

Ramp 5% → 20% → 50% → 100%, watching **Android vitals → Crashes and ANRs**. Halt via
**Production → Releases → Manage rollout → Halt rollout**. Always promote the artifact you
smoke-tested; rebuilding produces a different binary.

### iOS

**App Store Connect → Trevo Vault → App Store**: select the processed build, fill "What's New",
confirm export compliance, submit for review, and use **Manual release** after approval.

Export compliance is pre-declared (`ITSAppUsesNonExemptEncryption = false`); App Privacy answer is
**"Data Not Collected"**. Reuse the air-gapped App Review notes drafted in
`trevo_docs/ios_appstore_release_roadmap.md` — reviewers routinely flag air-gapped wallets.

### Publish the metadata QR

If §4 produced a new QR, publish `trevo_assets/load_metadata_trevo-asset-hubVNNNN.png` at the same
time as the store release. Users on the old version need it to decode transactions against the new
runtime.

---

## CI

The workflows in `.github/workflows/` are inherited from upstream and are **not** wired for Trevo
(wrong package names, no tags, secrets absent, actor gates for Novasama staff). Releases are cut
locally with the fastlane lanes above. Wiring CI for Trevo is a worthwhile follow-up.

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Gradle: `cargo` / `uniffi-bindgen` not found | Android Studio launched from the Dock has no shell `PATH`. Use `./launch_android_studio.sh`, or set `rust.cargoCommand` in `android/local.properties`. |
| `cargoBuild*`: `linker-wrapper.sh: python: command not found` | The rust-android-gradle wrapper defaults to `python` (absent on macOS 12+). Handled by `pythonCommand = "python3"` in the `cargo { }` block of `android/build.gradle`; if you see this, that line was removed. |
| Gradle: `Release signing is not configured. Missing: MYAPP_UPLOAD_*` | `~/.gradle/gradle.properties` is absent/incomplete. Deliberate hard failure — see §2. |
| Gradle: `Release keystore not found at ...` | `MYAPP_UPLOAD_STORE_FILE` points at a missing file. Restore `~/dev/secure/trevo-wallet-signing/`. |
| `signingReport`: `Variant: debug → Missing keystore` | Harmless; the debug keystore is auto-created on the first debug build. |
| `apksigner` fails on the `.aab` | `apksigner` is APK-only. AABs are signed by Gradle; to sign by hand use `jarsigner`. |
| App crashes on launch on some ABI (`UnsatisfiedLinkError`) | An ABI in `abiFilters` is missing from `cargo { targets }`, so `libsigner.so` was not built for it. Keep the two in sync (§6c). |
| Play: `DEX code optimization is below our threshold` | Release R8 was disabled or constrained by broad keep rules. `verify_aab` now reads Play's `r8.json` metrics and rejects any category below 25%; do not bypass it. |
| Play: `Version code N has already been used` | Bump `versionCode` (§5). Play never accepts a repeated code. |
| `supply` changed the store listing | The `skip_upload_*` flags were removed from `upload_internal`. Restore them — this repo does not manage listing copy via fastlane. |
| fastlane: `Could not find gradlew` | Run Android lanes from `android/`, not from `android/fastlane/`. |
| App shows no networks / cannot decode transactions | Cold DB not regenerated. Run `cd android && ./generate_database.sh` and confirm `android/src/main/assets/Database` is non-empty (iOS does this in a build phase). |
| iOS: `Invalid API Key` | The issuer ID is set to the Team ID. Issuer is a UUID (`9ece21cf-…`); `9NMWDV6M74` is the Team ID. |
| iOS upload rejected, error `90474` | The app targets iPad (`TARGETED_DEVICE_FAMILY "1,2"`) but is portrait-only. Keep it `1` (iPhone-only), or add `UISupportedInterfaceOrientations~ipad` with all four orientations. See §7d. |
| iOS: `No such module 'signerFFI'` | Regenerate bindings: `uniffi-bindgen generate rust/signer/src/signer.udl --language swift --out-dir ios/PolkadotVault/Generated/` (version 0.22.0). |
| iOS: `ld: library 'signer' not found` | `libsigner.a` missing/wrong arch. Check `lipo -info ios/PolkadotVault/libsigner.a`; rebuild `ios/scripts/build_libsigner.sh device\|simulator`. |
| `cargo test` fails on `opencv` / `libclang.dylib` | Expected. Use `--workspace --exclude qr_reader_pc` (§3). |
| `cargo test -p <crate>` floods `wasm32` / `panic_impl` errors | Expected with `resolver = "1"`. Test the whole workspace, never one crate (§3). |
| 55 Rust tests fail | Expected — upstream fixtures for networks the fork drops (§3). Worry only if the count grows. |
| Metadata hex has a weird prefix after `sed` | The 4-byte header varies (`920d1900`/`52531100`/`ea4c1900`); `update_metadata.sh` strips only the first. |
| Bundler platform error | `bundle lock --add-platform arm64-darwin-25`. |

---

## Reference

| Thing | Value |
|---|---|
| Repo / branch | `git@github.com:trevo-finance/trevo-vault.git` — branch **`trevo`** |
| Android applicationId | `finance.trevo.vault` (Kotlin namespace `io.parity.signer` is cosmetic) |
| Android artifact | **AAB**; `android/build/outputs/bundle/release/android-release.aab` (~48 MB) |
| Android upload key | `my-upload-key.keystore`, alias `my-key-alias`, SHA-1 `8C:C9:07:…:32:EB` — shared with Trevo Wallet |
| Android signing props | `~/.gradle/gradle.properties` (`MYAPP_UPLOAD_*`) → read by `signingConfigs.release` |
| Play service account | `~/.gradle/google-play-credentials.json` — access to both `finance.trevo.vault` and `finance.trevo.wallet`; override with `PLAY_JSON_KEY` |
| Android live | production **versionCode 13 (1.0.9)** |
| iOS bundle ID | `finance.trevo.vault` · iPhone-only (`TARGETED_DEVICE_FAMILY = 1`) |
| Apple Team | `9NMWDV6M74` — TRAIT TECH PTE LTD |
| App Store Connect | app ID `6759246669` · portal App ID `Y6TFBP5MRW` · SKU `trevo-vault-ios` |
| ASC API key | `AuthKey_X2TZ9NDANA.p8` — key `X2TZ9NDANA`, issuer `9ece21cf-d6e0-413a-89fb-84f5b3acaa0b` |
| iOS profile | `ios/sign/TrevoVault_AppStore.mobileprovision` — **expires 2026-08-14** |
| Xcode project | `ios/PolkadotVault.xcodeproj` (no workspace; SPM, no CocoaPods) |
| Schemes | `PolkadotVault` (Release) · `PolkadotVault-Dev` (Debug) · `PolkadotVault-QA` (QA) |
| iOS deployment target | 15.8.1 |
| Chain RPC | `wss://rpc.api.trevo.finance` |
| Genesis hash | `6d32fee54448c79868e083fc2179f662edc8a348c8b3c92407056f2ef286ea31` |
| Chain params | base58 prefix `5335` · decimals `12` · unit `TREVO` · Sr25519 |
| Metadata verifier pubkey | `0x7e177b85cefefb6e46b1fc007726ee428fe443906e94f77e4a3ae622dc135642` |
| Current metadata / QR | `rust/defaults/release_metadata/trevo-asset-hub1011` · `trevo_assets/load_metadata_trevo-asset-hubV1011.png` |
| Gradle / AGP / Kotlin | 8.14.3 / 8.13.1 / 1.9.22 |
| SDK / NDK | compileSdk 36 · targetSdk 36 · minSdk 23 · NDK 28.2.13676358 |
| Java | Zulu JDK 17 |
| Rust / UniFFI | rustc 1.97.1 (unpinned) / uniffi-bindgen 0.22.0 |
| fastlane | 2.229.1 via `bundle exec` |
| Signing material | `~/dev/secure/trevo-wallet-signing/` — outside the repo, not in git, **back it up** |

### Open follow-ups

- **The Apple account `dmitry.zakharov@trevo.finance`** (a departed developer) still owns the App
  Store Connect record. Transfer ownership. Releases do not depend on it — the `.p8` API key handles
  auth — but account recovery would.
- **Wire CI for Trevo** (see the CI section).
- **Cleanup, non-blocking:** delete `ios/PolkadotVault.xcodeproj/project.pbxproj.backup`,
  `create_db_1004.sh` (dead), and `trevo_scripts/reset_ios_version.py` (dangerous near a release);
  `RELEASE_TESTING_GUIDELINES.md` describes a React-Native era that no longer exists.
