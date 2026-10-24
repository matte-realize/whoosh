// ExplorerView.swift (iPhone target)
// Throwaway spike UI. Not compiled yet. Use it as the root view of the spike's iPhone app.

import SwiftUI

struct ExplorerView: View {
    @State private var explorer = BLEExplorer()

    var body: some View {
        NavigationStack {
            List {
                Section("Bluetooth") {
                    Text(explorer.state).font(.footnote)
                    if explorer.connectedName == nil {
                        Button(explorer.isScanning ? "Stop scan" : "Scan for devices") {
                            explorer.isScanning ? explorer.stopScan() : explorer.startScan()
                        }
                    } else {
                        Text("Connected: \(explorer.connectedName ?? "")")
                        Button("Disconnect", role: .destructive) { explorer.disconnect() }
                    }
                }

                if explorer.connectedName == nil {
                    Section("Nearby (strongest first)") {
                        if explorer.devices.isEmpty {
                            Text("Nothing yet. Scan, and keep the device close.").font(.footnote)
                        }
                        ForEach(explorer.devices) { device in
                            Button {
                                explorer.connect(device)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name).bold()
                                    Text("signal \(device.rssi) dBm"
                                         + (device.connectable == false ? ", not connectable" : ""))
                                        .font(.caption)
                                    if !device.advertisedServices.isEmpty {
                                        Text(device.advertisedServices.joined(separator: ", ")).font(.caption2)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Section("What it offers") {
                        if explorer.characteristics.isEmpty {
                            Text("Discovering…").font(.footnote)
                        }
                        ForEach(explorer.characteristics) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.characteristicLabel).bold()
                                Text("in \(item.serviceLabel)").font(.caption)
                                Text(item.properties.isEmpty ? "no properties" : item.properties.joined(separator: ", "))
                                    .font(.caption2)
                                HStack {
                                    Button("Read") { explorer.read(item) }
                                    Button("Subscribe") { explorer.subscribe(item) }
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                                if item.canWrite {
                                    HStack {
                                        Button("Write 0x00") { explorer.write(0x00, to: item) }
                                        Button("Write 0x01") { explorer.write(0x01, to: item) }
                                        Button("Write 0x02") { explorer.write(0x02, to: item) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .font(.caption)
                                    if item.isImmediateAlertLevel {
                                        Text("Standard Immediate Alert level: 1 = mild, 2 = high.").font(.caption2)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Log (newest first)") {
                    Button("Clear log", role: .destructive) { explorer.clearLog() }
                    ForEach(Array(explorer.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("BLE explorer")
        }
    }
}
