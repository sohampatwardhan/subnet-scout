# Subnet Scout

Subnet Scout is a clean-room IPv4 host scanner for iOS, iPadOS, and macOS. You give it an address, an inclusive range, a CIDR prefix, or the current local subnet. It probes hosts concurrently, records latency, resolves reverse DNS and Bonjour names, and lists open TCP ports.

The working name collides with an existing App Store app and sits near the NETSCOUT trademark. It stays on this repository until a human picks a new title. See the name check in [`.kiro/specs/local-network-scan/requirements.md`](.kiro/specs/local-network-scan/requirements.md). Preferred alternative: **Lantern Sweep**.

This project does not copy Angry IP Scanner or any other scanner's code, text, icons, or branding.

## Features in v0.1

- Single IPv4 address, `start-end` range, last-octet shorthand (`192.168.1.10-20`), and CIDR
- Current subnet from the preferred local interface
- Concurrent host scans with a configurable limit and per-probe timeout
- ICMP echo on macOS when `ping` can run, and TCP connect probes everywhere else
- A TCP refusal counts as alive. A completed handshake is an open port
- Reverse DNS, with a Bonjour instance name preferred when one is learned
- Pause, resume, and cancel
- Sort and filter the result table
- Saved favorite ranges
- Export CSV, JSON, and TXT
- Public addresses, including CGNAT, wait for an explicit acknowledgement

Not in v0.1: IPv6, MAC addresses, UDP, banners, and scan history.

## Screenshots

Screenshots are not in the tree yet. The placeholder list is [docs/screenshots/README.md](docs/screenshots/README.md).

## Build

Requirements: Swift 6, and Xcode 16 or newer with XcodeGen for the app.

```bash
swift test
brew install xcodegen
cd App && xcodegen generate
```

Open `App/SubnetScout.xcodeproj`, or build without signing:

```bash
cd App
xcodebuild -project SubnetScout.xcodeproj -scheme SubnetScout \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
xcodebuild -project SubnetScout.xcodeproj -scheme SubnetScout \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

`ScannerCore` is the Swift package at the repository root. Its tests run on Linux because `Network.framework` sits behind protocols. GitHub Actions runs those tests in `swift:6.2` and builds the app on `macos-latest`.

The app icon is an original mark. Regenerate it with `python3 scripts/generate-app-icon.py`. Interface icons are SF Symbols. This repo does not vendor an MCP client config.

## Privacy

Subnet Scout sends packets only to the range you start. It does not ship an account, analytics, or a cloud API. Favorites and the last target text stay in Application Support and UserDefaults on the device.

iOS and iPadOS show the system Local Network prompt because the app includes `NSLocalNetworkUsageDescription` and the Bonjour service types it browses. Raw ICMP is not available there, so discovery uses TCP connect probes. The app does not invent a MAC address.

macOS builds enable App Sandbox with the network client entitlement (and the network server entitlement used for Bonjour). `ping` may be unavailable inside the sandbox. The scan continues with TCP.

Scanning networks you do not administer can violate policy or law. Ranges outside private and local space ask before the first probe.

## Specs

Behavior, design, and the task list live in [`.kiro/specs/local-network-scan/`](.kiro/specs/local-network-scan/). The workflow is described in [AGENTS.md](AGENTS.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). Copyright (c) 2026 Soham Patwardhan.
