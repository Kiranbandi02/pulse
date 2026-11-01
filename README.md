# Pulse

A friendlier Activity Monitor for macOS: live CPU, memory, disk and network speed in plain English, a menu bar speed readout, and desktop widgets. Read-only — it never quits or changes any process.

## Install

```
curl -fsSL https://raw.githubusercontent.com/Kiranbandi02/pulse/main/install.sh | bash
```

Uninstall: `curl -fsSL https://raw.githubusercontent.com/Kiranbandi02/pulse/main/install.sh | bash -s -- --uninstall`

Add the widget: right-click the desktop → Edit Widgets → System Pulse (small, medium, large).

## Build from source

Needs only the Xcode Command Line Tools (`xcode-select --install`), macOS 14+.

```
./build.sh install   # build, copy to /Applications, launch
./build.sh package   # build/Pulse.zip for a GitHub release
```

## Notes

- Ad-hoc signed, not notarized. Installing with the `curl` command above avoids Gatekeeper prompts; a zip downloaded in a browser needs right-click → Open.
- Not sandboxed (it reads other processes' stats), so it isn't App Store compatible.
- Widgets are refreshed on macOS's schedule; the app nudges a refresh every minute while it is open.
