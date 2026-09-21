# TintLink

A native macOS menu bar app that changes accent colors across macOS, VS Code, Codex, and Chrome.

**[Download the latest release](https://github.com/youngchan2/tintlink/releases/latest)**

## What you can configure

- Choose from seven colors: blue, lavender, pink, red, orange, yellow, and green.
- Select which apps receive the color change.
- Match selected apps to your current macOS accent color.
- Change VS Code's Dark Modern accent and text selection colors.
- Change Codex's light and dark theme accents.
- Apply a matching Chrome hue to one or more profiles, shown by their custom names. Select all profiles with one click.
- Keep Chrome's existing theme sync settings. Chrome handles account synchronization.

## Install

Requires **Apple Silicon and macOS 13 or later**. No Python or Homebrew required.

Download the release ZIP, move `TintLink.app` to Applications, and open it. Use the palette icon in the menu bar. Allow Accessibility access for TintLink to control Chrome.

VS Code needs Dark Modern and an existing `workbench.colorCustomizations` entry. Codex needs configured light/dark accent settings. Chrome uses the closest supported hue, so colors may differ slightly.

The current build is ad-hoc signed and not notarized by Apple. macOS may show an opening warning, and app updates may require reconnecting Accessibility access.

## Build

With Apple's Swift command-line tools installed:

```sh
bash tests/test-native.sh
bash src/AccentBar/build.sh
bash scripts/package-release.sh
```

Builds `outputs/TintLink.app` and a versioned ZIP with a SHA-256 checksum.
