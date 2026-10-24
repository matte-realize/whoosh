// PhoneContentView.swift (iPhone target)
// Throwaway spike UI. Not compiled yet. Use it as the root view of the spike's iPhone app.

import SwiftUI

struct PhoneContentView: View {
    @State private var sender = PhoneSender()
    @State private var autoRun: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    Text(sender.status).font(.footnote)
                    if let median = sender.medianRoundTripMs {
                        Text("Median round trip: \(median) ms (\(sender.roundTripsMs.count) replies, phone clock)")
                            .font(.footnote)
                    }
                }

                Section("Send one haptic") {
                    ForEach(HapticPattern.allCases, id: \.self) { pattern in
                        Button(pattern.rawValue) { sender.send(pattern) }
                    }
                }

                Section("Repeat test") {
                    if autoRun == nil {
                        Button("Send 'notification' every 5 s") {
                            autoRun = Task {
                                while !Task.isCancelled {
                                    sender.send(.notification)
                                    try? await Task.sleep(for: .seconds(5))
                                }
                            }
                        }
                    } else {
                        Button("Stop repeating", role: .destructive) {
                            autoRun?.cancel()
                            autoRun = nil
                        }
                    }
                }

                Section("Log (newest first)") {
                    Button("Clear log", role: .destructive) { sender.clearLog() }
                    ForEach(sender.log) { line in
                        Text(line.text).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("Watch haptic spike")
        }
    }
}
