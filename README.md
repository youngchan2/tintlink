# TintLink

A native macOS menu bar app that changes accent colors across macOS, VS Code, Codex, and Chrome.

**[Download TintLink for Apple Silicon](https://github.com/youngchan2/tintlink/releases/download/v1.0.1/TintLink-1.0.1-macos-arm64.zip)** · [Release notes](https://github.com/youngchan2/tintlink/releases/latest)

## What you can configure

- Choose from seven colors: blue, lavender, pink, red, orange, yellow, and green.
- Select which apps receive the color change.
- Change VS Code's Dark Modern accent and text selection colors.
- Change Codex's light and dark theme accents.
- Apply a matching Chrome hue to one or more profiles, shown by their custom names. Select all profiles with one click.
- Keep Chrome's existing theme sync settings. Chrome handles account synchronization.

## Install

Requires **Apple Silicon and macOS 13 or later**. No Python or Homebrew required.

1. Download **TintLink-1.0.1-macos-arm64.zip** using the link above.
2. Open the ZIP, move **TintLink.app** to **Applications**, and open it.
3. Use the palette icon in the menu bar. Allow Accessibility access for TintLink to control Chrome.

Download the app ZIP, not GitHub's **Source code** archives. A `.sha256` file is an optional checksum for checking a download; it is not an app and does not need to be opened.

### First launch

This release is **ad-hoc signed and not notarized by Apple**. macOS may say that Apple cannot check TintLink for malicious software. The warning will also appear with version 1.0.1.

If you trust this project and downloaded the app from this repository:

1. Click **Done** in the warning.
2. Open **System Settings → Privacy & Security** and find the TintLink warning.
3. Click **Open Anyway**, authenticate if asked, and confirm **Open**.

See [Apple's first-launch instructions](https://support.apple.com/102445). Updates may require reconnecting TintLink in **Privacy & Security → Accessibility**.

VS Code needs Dark Modern and an existing `workbench.colorCustomizations` entry. Codex needs configured light/dark accent settings. Chrome uses the closest supported hue, so colors may differ slightly.

Chrome UI automation may occasionally need another attempt after Chrome finishes starting.

## Build

With Apple's Swift command-line tools installed:

```sh
bash tests/test-native.sh
bash src/AccentBar/build.sh
bash scripts/package-release.sh
```

Builds `outputs/TintLink.app` and a versioned ZIP with a SHA-256 checksum.
