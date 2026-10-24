// BLEExplorer.swift (iPhone target)
// Throwaway spike code. NOT compiled or run yet: it needs Xcode and the iOS SDK, and a real
// iPhone (the simulator has no Bluetooth). Set the target's Swift Language Mode to 5.
//
// Needs one Info.plist key on the iPhone target:
//   NSBluetoothAlwaysUsageDescription = "Whoosh Bluetooth test: scans for nearby devices to see
//   what they offer. Nothing is stored or uploaded."
//
// Privacy: scanning shows other people's nearby devices. This app keeps the list in memory only,
// writes nothing to disk, and sends nothing over the network.

import CoreBluetooth
import Foundation
import Observation

struct FoundDevice: Identifiable {
    let id: UUID                     // CoreBluetooth's per-phone identifier, not a MAC address
    var name: String
    var rssi: Int
    var advertisedServices: [String]
    var connectable: Bool?
}

struct DiscoveredCharacteristic: Identifiable {
    let id = UUID()
    let serviceLabel: String
    let characteristicLabel: String
    let properties: [String]
    let canWrite: Bool
    let isImmediateAlertLevel: Bool
    let characteristic: CBCharacteristic
}

@Observable
final class BLEExplorer: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var state = "starting"
    var isScanning = false
    var devices: [FoundDevice] = []
    var connectedName: String?
    var characteristics: [DiscoveredCharacteristic] = []
    var log: [String] = []

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var active: CBPeripheral?

    override init() {
        super.init()
        // nil queue means callbacks arrive on the main queue, so no thread hopping is needed.
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: Actions

    func startScan() {
        guard central.state == .poweredOn else {
            append("Bluetooth is not ready: \(state)")
            return
        }
        devices.removeAll()
        peripherals.removeAll()
        // nil services: show everything nearby. Duplicates off, so the list does not flood.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
        append("scanning")
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
        append("scan stopped")
    }

    func connect(_ device: FoundDevice) {
        guard let peripheral = peripherals[device.id] else { return }
        stopScan()
        characteristics.removeAll()
        active = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
        append("connecting to \(device.name)")
    }

    func disconnect() {
        guard let active else { return }
        central.cancelPeripheralConnection(active)
    }

    func read(_ item: DiscoveredCharacteristic) {
        active?.readValue(for: item.characteristic)
    }

    func subscribe(_ item: DiscoveredCharacteristic) {
        active?.setNotifyValue(true, for: item.characteristic)
        append("subscribe requested: \(item.characteristicLabel)")
    }

    /// Writes one byte. For the Immediate Alert Level characteristic, 1 is "mild alert" and
    /// 2 is "high alert", 0 stops it. Whether the device vibrates is up to the device.
    func write(_ byte: UInt8, to item: DiscoveredCharacteristic) {
        guard let active else { return }
        let supportsNoResponse = item.characteristic.properties.contains(.writeWithoutResponse)
        let type: CBCharacteristicWriteType = supportsNoResponse ? .withoutResponse : .withResponse
        active.writeValue(Data([byte]), for: item.characteristic, type: type)
        append("wrote 0x\(String(format: "%02X", byte)) to \(item.characteristicLabel) (\(supportsNoResponse ? "no response" : "with response"))")
    }

    func clearLog() { log.removeAll() }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: state = "powered on"
        case .poweredOff: state = "Bluetooth is off"
        case .unauthorized: state = "permission denied (Settings > Whoosh spike > Bluetooth)"
        case .unsupported: state = "Bluetooth not supported on this device"
        case .resetting: state = "resetting"
        default: state = "unknown"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? advertisedName ?? "(no name)"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map { BLEFormat.label(service: $0.uuidString) }
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        let device = FoundDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue,
                                 advertisedServices: services, connectable: connectable)
        peripherals[peripheral.identifier] = peripheral
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
        devices.sort { $0.rssi > $1.rssi }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedName = peripheral.name ?? "(no name)"
        append("connected, discovering services")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        append("connect failed: \(error?.localizedDescription ?? "unknown error")")
        active = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        append("disconnected\(error.map { ": \($0.localizedDescription)" } ?? "")")
        connectedName = nil
        active = nil
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            append("service discovery failed: \(error.localizedDescription)")
            return
        }
        let services = peripheral.services ?? []
        append("found \(services.count) services")
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            append("characteristic discovery failed: \(error.localizedDescription)")
            return
        }
        for characteristic in service.characteristics ?? [] {
            let raw = characteristic.properties.rawValue
            characteristics.append(DiscoveredCharacteristic(
                serviceLabel: BLEFormat.label(service: service.uuid.uuidString),
                characteristicLabel: BLEFormat.label(characteristic: characteristic.uuid.uuidString),
                properties: BLEFormat.propertyNames(raw),
                canWrite: BLEFormat.canWrite(raw),
                isImmediateAlertLevel: BLEFormat.isImmediateAlertLevel(
                    service: service.uuid.uuidString, characteristic: characteristic.uuid.uuidString),
                characteristic: characteristic
            ))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let label = BLEFormat.label(characteristic: characteristic.uuid.uuidString)
        if let error {
            append("\(label): read/notify error: \(error.localizedDescription)")
        } else {
            append("\(label): \(BLEFormat.hex(characteristic.value ?? Data()))")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let label = BLEFormat.label(characteristic: characteristic.uuid.uuidString)
        append(error.map { "\(label): write failed: \($0.localizedDescription)" } ?? "\(label): write acknowledged")
    }

    private func append(_ text: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        log.insert("\(stamp)  \(text)", at: 0)
    }
}
