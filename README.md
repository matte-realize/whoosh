# Whoosh

Whoosh is an iOS cycling-safety app built for the Hackachusetts hackathon. It records a
cycling ride with GPS, shows the route on a map, and keeps ride history on-device — no
account and no network required for the core flow. It's built with a modular architecture
(service protocols + state machines) so camera-based hazard detection and haptic alerts can
be added later without rework.

- **Platform:** iOS 17+, SwiftUI, MapKit, Core Location, SwiftData
- **Toolchain:** Swift 6 / Xcode 26.5 (MainActor default isolation, Approachable Concurrency)
- **Units:** US customary (miles, mph, feet); SI internally

See `.kiro/steering/product.md` for the full product overview and MVP scope.

## Open the project

The committed `Whoosh.xcodeproj` is the source of truth — just open it:

```sh
open Whoosh.xcodeproj
```

### About the project file (XcodeGen)

`Whoosh.xcodeproj` is committed and can be opened directly. It was generated once from
[`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen), which
documents the build settings in one place. Sources use Xcode's **file-system-synchronized
groups**, so any new `.swift` file dropped under `Whoosh/` or `WhooshTests/` is compiled
automatically — you do **not** need to regenerate the project to add files.

Regenerate only if you change settings in `project.yml`:

```sh
xcodegen generate
```

## Run the tests

```sh
scripts/test.sh
```

This runs `xcodebuild test` for the `Whoosh` scheme. Override the simulator with
`WHOOSH_TEST_DESTINATION` if needed, e.g.:

```sh
WHOOSH_TEST_DESTINATION='platform=iOS Simulator,name=iPhone 15' scripts/test.sh
```

## Secrets

Opt-in Supabase sync (a stretch feature; the demo works fully offline) reads a Supabase URL
and anon key from a **gitignored** `Config/Secrets.xcconfig`. Copy the committed example and
fill in real values:

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Only the public anon key ships in the app. The `service_role` key must never appear in the
app or the repo.

## Project layout

```
Whoosh/            App sources (App/, Features/, Services/, Models/, Support/)
WhooshTests/       Swift Testing unit tests
Config/            xcconfig build settings (Shared.xcconfig, Secrets.example.xcconfig)
scripts/           test.sh, privacy-check.sh
project.yml        XcodeGen spec (generator only; the .xcodeproj is committed)
```

## Kiro spec, steering, and hooks

- **Steering** (conventions, tech, product, privacy): `.kiro/steering/`
- **Spec** (requirements, design, tasks): `.kiro/specs/ride-recording-mvp/`
- **Hooks** (test + privacy automation): `.kiro/hooks/`
- **Team** (cross-role plan + Supabase contract): `.kiro/team/`
