# Contributing

Subnet Scout is MIT licensed. Contributions stay inside the clean-room rule in [AGENTS.md](AGENTS.md): no copied scanner source, strings, icons, or branding, and no "Angry" name.

## Spec first

New behavior starts as a Kiro spec, not as a drive-by change to the scanner.

```text
.kiro/specs/<feature-name>/
  requirements.md
  design.md
  tasks.md
```

`<feature-name>` is a kebab-case slug. One feature or one bug per folder. A bugfix uses `bugfix.md` instead of `requirements.md` and is not converted in place into a feature spec.

Follow [kiro-sdd-skills](https://github.com/sohampatwardhan/kiro-sdd-skills):

- Requirements are user stories with numbered EARS acceptance criteria.
- Design keeps the six sections Overview, Architecture, Components and Interfaces, Data Models, Error Handling, and Testing Strategy.
- Tasks are checkboxes. A task that does work ends with `_Requirements: 1.2, 3.1_`.
- `tasks.md` includes a Mermaid DAG. Flowcharts and state diagrams use the ELK layout front matter.
- Do not renumber ids that later tasks already cite.

Steering files in `.kiro/steering/` describe the product, stack, and tree. Update them when a change moves one of those, and do not paste secrets into them.

## Code

- Put scan rules in `Sources/ScannerCore` with Swift Testing coverage in `Tests/ScannerCoreTests`.
- Keep `Network.framework` behind the probe protocols so `swift test` still passes on Linux.
- Document new public API with DocC (`- Parameters`, `- Returns`, `- Throws` when they apply).
- The SwiftUI app calls the package. It does not reimplement parsing, the public-range gate, or export.
- Keep `BonjourServiceTypes.defaults` and `NSBonjourServices` in `App/SubnetScout/Info.plist` identical.
- Do not add a MAC address on iOS. Do not invent one when the system does not provide it.
- Default targets stay inside private and local ranges. Public ranges still require acknowledgement.

## Checks before a pull request

```bash
swift test
brew install xcodegen   # once
cd App && xcodegen generate
xcodebuild -project SubnetScout.xcodeproj -scheme SubnetScout \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
xcodebuild -project SubnetScout.xcodeproj -scheme SubnetScout \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Do not commit `App/SubnetScout.xcodeproj`, `.build`, or an MCP config file.

The generated Xcode project is local. CI generates it the same way.
