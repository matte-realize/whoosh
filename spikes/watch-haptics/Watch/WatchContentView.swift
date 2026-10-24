// WatchContentView.swift (watchOS target)
// Throwaway spike UI. Not compiled yet. Use it as the root view of the spike's watch app.

import SwiftUI

struct WatchContentView: View {
    @State private var receiver = WatchReceiver()

    var body: some View {
        List {
            Section("Status") {
                Text("Link: \(receiver.connection)").font(.caption2)
                Text("Workout: \(receiver.workoutState)").font(.caption2)
                Text("From phone: \(receiver.received), last: \(receiver.lastPattern)").font(.caption2)
            }

            Section("Cycling workout") {
                if receiver.workoutActive {
                    Button("End workout", role: .destructive) { receiver.stopWorkout() }
                } else {
                    Button("Start cycling workout") { Task { await receiver.startWorkout() } }
                }
            }

            Section("Feel each haptic here") {
                ForEach(HapticPattern.allCases, id: \.self) { pattern in
                    Button(pattern.rawValue) { receiver.playLocally(pattern) }
                }
            }
        }
    }
}
