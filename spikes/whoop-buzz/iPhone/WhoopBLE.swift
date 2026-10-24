// WhoopBLE.swift (iPhone target)
// Throwaway spike: find a WHOOP 5.0 strap, write the session hello, send buzz commands, log everything.

import CoreBluetooth
import Foundation
import Observation

struct LogLine: Identifiable {
    let id = UUID()
    let text: String
}

struct FoundStrap: Identifiable {
    let id: UUID
    let name: String
    var rssi: Int
}

@Observable
final class WhoopBLE: NSObject {
    static let service = CBUUID(string: "fd4b0001-cce1-4033-93ce-002d5875f58a")
    static let commandChar = CBUUID(string: "fd4b0002-cce1-4033-93ce-002d5875f58a")
    static let heartRateService = CBUUID(string: "180D")

    private(set) var status = "Idle"
    private(set) var found: [FoundStrap] = []
    private(set) var log: [LogLine] = []
    private(set) var isConnected = false
    private(set) var canWrite = false

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var strap: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var seq: UInt8 = 63
    private var notifyCounts: [CBUUID: Int] = [:]
    private var scanning = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: Actions

    func startScan() {
        guard central.state == .poweredOn else {
            note("Bluetooth is not on (state \(central.state.rawValue))")
            return
        }
        found = []
        // A strap already connected to the WHOOP app or iOS does not advertise, so a scan misses it.
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.service, Self.heartRateService])
        for p in connected { register(p, rssi: 0, source: "already connected to this phone") }
        central.scanForPeripherals(withServices: [Self.service], options: nil)
        scanning = true
        status = "Scanning for fd4b0001…"
        note("Scan started (service fd4b0001)")
    }

    func stopScan() {
        central.stopScan()
        scanning = false
    }

    func connect(_ id: UUID) {
        guard let p = peripherals[id] else { return }
        stopScan()
        strap = p
        p.delegate = self
        notifyCounts = [:]
        status = "Connecting to \(p.name ?? "strap")…"
        note("Connecting to \(p.name ?? id.uuidString)")
        central.connect(p, options: nil)
    }

    func disconnect() {
        if let strap { central.cancelPeripheralConnection(strap) }
    }

    func sendHello() { write(WhoopFrame.hello, label: "HELLO (static)") }

    func buzz(alarmID: UInt8) {
        write(WhoopFrame.runAlarm(seq: nextSeq(), alarmID: alarmID), label: "RUN_ALARM [2,\(alarmID)]")
    }

    func hapticsPattern(_ id: UInt8) {
        write(WhoopFrame.runHapticsPattern(seq: nextSeq(), patternID: id, loops: 3),
              label: "RUN_HAPTICS_PATTERN id=\(id) loops=3")
    }

    func stopHaptics() { write(WhoopFrame.stopHaptics(seq: nextSeq()), label: "STOP_HAPTICS") }

    func clearLog() { log = [] }

    var logText: String { log.reversed().map(\.text).joined(separator: "\n") }

    // MARK: Internals

    private func nextSeq() -> UInt8 {
        seq = seq == .max ? 64 : seq + 1
        return seq
    }

    private func write(_ frame: [UInt8], label: String) {
        guard let strap, let ch = commandCharacteristic else {
            note("Cannot send \(label): no command characteristic yet")
            return
        }
        // Same order as Goose (the only project that has sent 5.0 commands): confirmed write first.
        // A confirmed write also makes iOS bond with the strap, and a strap may ignore commands
        // from an unbonded link. Fall back to write-without-response only if that is all it offers.
        let type: CBCharacteristicWriteType =
            ch.properties.contains(.write) ? .withResponse : .withoutResponse
        note("→ \(label)  [\(type == .withResponse ? "with" : "without") response]  \(WhoopFrame.hex(frame))")
        strap.writeValue(Data(frame), for: ch, type: type)
    }

    private func register(_ p: CBPeripheral, rssi: Int, source: String) {
        peripherals[p.identifier] = p
        let name = p.name ?? "(unnamed)"
        if let i = found.firstIndex(where: { $0.id == p.identifier }) {
            found[i].rssi = rssi
        } else {
            found.append(FoundStrap(id: p.identifier, name: name, rssi: rssi))
            note("Found \(name)  \(p.identifier.uuidString.prefix(8))…  \(source)")
        }
    }

    private func note(_ text: String) {
        let stamp = Self.formatter.string(from: Date())
        log.insert(LogLine(text: "\(stamp)  \(text)"), at: 0)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private func describeProperties(_ p: CBCharacteristicProperties) -> String {
        var names: [String] = []
        if p.contains(.read) { names.append("read") }
        if p.contains(.writeWithoutResponse) { names.append("write-no-resp") }
        if p.contains(.write) { names.append("write") }
        if p.contains(.notify) { names.append("notify") }
        if p.contains(.indicate) { names.append("indicate") }
        return names.joined(separator: ",")
    }
}

// MARK: - CBCentralManagerDelegate

extension WhoopBLE: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: status = "Bluetooth ready. Tap Scan."
        case .unauthorized: status = "Bluetooth permission denied. Enable it in Settings."
        case .poweredOff: status = "Bluetooth is off."
        case .unsupported: status = "Bluetooth unsupported (the simulator has none)."
        default: status = "Bluetooth state \(central.state.rawValue)"
        }
        note(status)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        register(peripheral, rssi: RSSI.intValue, source: "advertising")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        status = "Connected. Discovering services…"
        note("Connected")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status = "Connect failed"
        note("Connect failed: \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        canWrite = false
        commandCharacteristic = nil
        status = "Disconnected"
        note("Disconnected\(error.map { ": \($0.localizedDescription)" } ?? "")")
    }
}

// MARK: - CBPeripheralDelegate

extension WhoopBLE: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { note("Service discovery error: \(error.localizedDescription)"); return }
        let services = peripheral.services ?? []
        note("Services: \(services.map { $0.uuid.uuidString }.joined(separator: ", "))")
        for s in services { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { note("Characteristic discovery error: \(error.localizedDescription)"); return }
        for c in service.characteristics ?? [] {
            note("  \(service.uuid.uuidString.prefix(8)) / \(c.uuid.uuidString.prefix(8))  \(describeProperties(c.properties))")
            if c.uuid == Self.commandChar {
                commandCharacteristic = c
                canWrite = true
                status = "Ready. Send hello, then buzz."
            }
            // Goose subscribes to every notifiable characteristic in every service, not just fd4b.
            if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: c)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            note("Subscribe \(characteristic.uuid.uuidString.prefix(8)) failed: \(error.localizedDescription)")
        } else {
            note("Subscribed \(characteristic.uuid.uuidString.prefix(8))")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        note(error.map { "Write error: \($0.localizedDescription)" } ?? "Write acknowledged")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { note("Notify error: \(error.localizedDescription)"); return }
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        let summary = WhoopFrame.summarize(bytes)
        let count = (notifyCounts[characteristic.uuid] ?? 0) + 1
        notifyCounts[characteristic.uuid] = count

        // The live data streams are noisy. Always show command responses and events (what a buzz
        // would produce); show only the first few packets of anything else.
        let important = summary.map { [36, 38, 48, 54].contains($0.packetType) } ?? false
        guard important || count <= 5 else { return }

        let label = summary.map {
            "\(WhoopFrame.packetTypeName($0.packetType)) seq=\($0.seq) cmd/event=\($0.cmdOrEvent) crc=\($0.crcOK ? "ok" : "BAD")"
        } ?? "partial/unframed"
        let shown = bytes.prefix(48)
        note("← \(characteristic.uuid.uuidString.prefix(8)) #\(count) \(bytes.count)B \(label)\n    \(WhoopFrame.hex(Array(shown)))\(bytes.count > 48 ? " …" : "")")
    }
}
