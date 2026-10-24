import SwiftUI
import WhooshWire

/// The Settings page (watch-companion design "Pages → Settings"): default
/// Save-to-Health, the "Also play a sound" mirror, haptics on/off, a link to the
/// on-watch "Feel the patterns" tuning list (task 19), and diagnostics counts.
/// Honest copy: haptics are a cue, not a guarantee; the rear-vehicle cue is
/// experimental and Whoosh cannot guarantee detection or delivery.
struct SettingsPageView: View {
    @Bindable var model: WatchSessionModel

    var body: some View {
        List {
            Section("Watch") {
                Toggle("Save to Health", isOn: $model.defaultSaveToHealth)
                Toggle("Also play a sound", isOn: $model.alsoPlaySound)
                Toggle("Wrist haptics", isOn: $model.hapticsEnabled)
            }

            Section("Haptics") {
                NavigationLink {
                    FeelPatternsView(player: nil, model: model)
                } label: {
                    Label("Feel the patterns", systemImage: "waveform")
                }
                Text("Haptics are a cue, not a guarantee. The rear-vehicle cue is experimental; Whoosh cannot guarantee detection or delivery.")
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.mistDim)
            }

            Section("Diagnostics") {
                row("Cues played", "\(model.cuesPlayed)")
                row("Commands sent", "\(model.commandsSent)")
                row("Unread notices", "\(model.unreadNoticeCount)")
                row("Link", model.reachable ? "Connected" : "Not connected")
            }
        }
        .navigationTitle("Settings")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(WatchTheme.mistDim)
        }
        .font(.caption2)
    }
}

/// On-watch "Feel the patterns" list (task 19): plays each catalog pattern so
/// the owner can tune them on the real wrist. Uses the `HapticPlaying` seam so
/// it works with the real `WKHapticPlayer` on device and with a fake in previews.
struct FeelPatternsView: View {
    /// An explicit player for on-device use; when nil, falls back to the model's
    /// injection path (previews record the play without buzzing).
    let player: HapticPlaying?
    let model: WatchSessionModel

    var body: some View {
        List(HapticPatternSelector.catalog, id: \.name) { pattern in
            Button {
                play(pattern)
            } label: {
                HStack {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(WatchTheme.lime)
                    Text(displayName(pattern.name))
                    Spacer()
                    Text("\(pattern.steps.count)")
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.mistDim)
                }
            }
            .accessibilityLabel("Play \(displayName(pattern.name)) pattern")
        }
        .navigationTitle("Feel patterns")
    }

    private func play(_ pattern: HapticPattern) {
        if let player, player.isActive {
            player.play(pattern)
        } else {
            // Preview / no-player fallback: route a preview alert so the model's
            // player (fake) records it; never starts a countdown.
            model.injectForPreview(alert: WireAlert(
                alertId: UUID().uuidString,
                kind: .patternPreview,
                tier: .confirm,
                patternName: pattern.name,
                createdAgoMs: 0,
                ttlMs: 60_000
            ))
        }
    }

    /// Humanize a camelCase pattern name for display.
    private func displayName(_ raw: String) -> String {
        var out = ""
        for ch in raw {
            if ch.isUppercase { out.append(" ") }
            out.append(ch)
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsPageView(model: WatchDemo.makeModel(scenario: .riding))
    }
}

#Preview("Feel patterns") {
    NavigationStack {
        FeelPatternsView(player: nil, model: WatchDemo.makeModel(scenario: .idleReady))
    }
}
