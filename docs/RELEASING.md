# Releasing TintLink

## Versioning

Use a minor version for new features (1.1.0), a patch for fixes (1.1.1), and a major version for incompatible changes. Edit `config/release.env`. Always increase `TINTLINK_BUILD_NUMBER`; Sparkle compares this build number, not just the display version. Never replace an already published ZIP with a different build using the same version.

## Signing key

The update signing key is stored in the releasing Mac's login Keychain under Sparkle's service and the `tintlink` account. Only its public key is checked into `config/release.env`. This key is separate from an Apple Developer ID certificate.

Keep the private key safe. If moving to a different Mac, use Sparkle's `generate_keys` export/import procedure and keep any export in a secure place outside this repository. Do not generate a replacement key for an existing release line: installed apps trust the original public key.

## Prepare

1. Bump the version and build number in `config/release.env`.
2. Write concise English notes in `docs/releases/v<VERSION>.md`.
3. Run:

```sh
bash tests/test-native.sh
bash src/AccentBar/build.sh
bash scripts/prepare-update.sh
```

The last command packages the app, checks that the Keychain key matches the app, signs the ZIP, and generates a signed `updates/appcast.xml` with embedded notes. It needs access to the signing key and Sparkle's local cache. Keep the exact generated ZIP; rebuilding or repackaging changes its signature.

The app verifies both the feed and the archive before extracting an update. Never edit a generated signed feed by hand.

## Publish

1. Commit the source and release notes; tag that commit as `v<VERSION>`.
2. Publish a GitHub Release with the exact `outputs/TintLink-<VERSION>-macos-arm64.zip`. Link the app ZIP prominently; the checksum file is optional and is not an installer.
3. Only after the ZIP URL works, commit and push the generated `updates/appcast.xml` to `main`. The app reads this file through its HTTPS raw GitHub URL. Publishing the feed first would offer a download that does not exist yet.
4. Check for updates from an older installed build and verify installation/relaunch and saved preferences.

GitHub Releases stores the download. The appcast announces which download Sparkle should offer. Publishing a release alone does not update the appcast.

## Local validation

`tests/prepare-updater-test.sh` creates isolated test bundles and a signed local feed using the same framework and signing key. The test bundle has a separate identifier, so it does not overwrite the installed TintLink app or its preferences. It allows HTTP only for local testing; the shipping app uses HTTPS.

The test folder includes instructions for running a local server and using the test app's Check for Updates menu. Feed/archive verification also checks that modified bytes are rejected, using only the public key.

For a windowless integration test, run `TINTLINK_TEST_PORT=8124 bash tests/prepare-updater-test.sh --headless`, serve the resulting `server/` folder on that port, and execute the test bundle's `Contents/MacOS/TintLink`. Check `result.log` in the test folder: it must end in `PASS` after download, installation, relaunch, preference preservation, and a latest-version check. Any `FAIL` line is a test failure. The host uses Sparkle's real installer with an in-memory test driver instead of clicking dialogs.

## Current distribution limits

TintLink is ad-hoc signed and not notarized. Sparkle signatures verify update authenticity; they do not remove macOS's first-launch warning. Chrome's Accessibility permission may need reconnecting after an update. Apple Developer ID signing and notarization can be added later.
