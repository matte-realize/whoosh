// ContentView.swift (iPhone target)
// Throwaway spike UI.

import SwiftUI
import UIKit

struct ContentView: View {
    @State private var ble = WhoopBLE()

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    Text(ble.status).font(.footnote)
                    HStack {
                        Button("Scan") { ble.startScan() }
                        Spacer()
                        if ble.isConnected {
                            Button("Disconnect", role: .destructive) { ble.disconnect() }
                        }
                    }
                    ForEach(ble.found) { strap in
                        Button {
                            ble.connect(strap.id)
                        } label: {
                            HStack {
                                Text(strap.name)
                                Spacer()
                                Text(strap.rssi == 0 ? "connected" : "\(strap.rssi) dBm")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Buzz (do these in order)") {
                    Button("1. Send hello") { ble.sendHello() }
                    Button("2. BUZZ: RUN_ALARM") { ble.buzz(alarmID: 0) }
                        .fontWeight(.semibold)
                }
                .disabled(!ble.canWrite)

                Section("If nothing buzzed, try these") {
                    Button("RUN_ALARM alarm id 1") { ble.buzz(alarmID: 1) }
                    Button("RUN_HAPTICS_PATTERN 0 (quick buzz)") { ble.hapticsPattern(0) }
                    Button("RUN_HAPTICS_PATTERN 2 (double buzz)") { ble.hapticsPattern(2) }
                    Button("STOP_HAPTICS") { ble.stopHaptics() }
                }
                .disabled(!ble.canWrite)

                Section("Log (newest first)") {
                    Button("Copy log") { UIPasteboard.general.string = ble.logText }
                    Button("Clear log", role: .destructive) { ble.clearLog() }
                    ForEach(ble.log) { line in
                        Text(line.text).font(.caption2.monospaced())
                    }
                }
            }
            .navigationTitle("WHOOP buzz spike")
        }
    }
}
