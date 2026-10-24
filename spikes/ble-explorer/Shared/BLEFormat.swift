// BLEFormat.swift
// Pure helpers for the BLE explorer spike. Foundation only, so it type-checks and runs without
// Xcode: `swiftc -swift-version 6 BLEFormat.swift main.swift`.

import Foundation

enum BLEFormat {
    /// Bit values of GATT characteristic properties. They match CoreBluetooth's
    /// `CBCharacteristicProperties.rawValue`, which is how the explorer passes them in.
    static let propertyBits: [(bit: UInt, name: String)] = [
        (0x01, "broadcast"),
        (0x02, "read"),
        (0x04, "write-no-response"),
        (0x08, "write"),
        (0x10, "notify"),
        (0x20, "indicate"),
        (0x40, "signed-write"),
        (0x80, "extended"),
    ]

    /// `[0x01, 0x0A]` becomes `"01 0A"`. Empty data becomes `"(empty)"`.
    static func hex(_ data: Data) -> String {
        guard !data.isEmpty else { return "(empty)" }
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Names of the properties set in a raw property value, in a fixed order.
    static func propertyNames(_ raw: UInt) -> [String] {
        propertyBits.filter { raw & $0.bit != 0 }.map(\.name)
    }

    /// True when the characteristic accepts writes, with or without a response.
    static func canWrite(_ raw: UInt) -> Bool {
        raw & (0x04 | 0x08) != 0
    }

    private static let baseSuffix = "-0000-1000-8000-00805F9B34FB"

    /// Reduces a Bluetooth SIG base UUID to its 4 hex digit form, upper case.
    /// `"0000180d-0000-1000-8000-00805f9b34fb"` becomes `"180D"`. Anything else is returned
    /// upper-cased and otherwise unchanged (custom 128-bit UUIDs and already-short UUIDs).
    static func shortUUID(_ uuid: String) -> String {
        let upper = uuid.uppercased()
        if upper.count == 36, upper.hasSuffix(baseSuffix), upper.hasPrefix("0000") {
            let start = upper.index(upper.startIndex, offsetBy: 4)
            let end = upper.index(start, offsetBy: 4)
            return String(upper[start..<end])
        }
        return upper
    }

    /// Well-known service names, to make the explorer's list readable. Not exhaustive.
    private static let serviceNames: [String: String] = [
        "1800": "Generic Access",
        "1801": "Generic Attribute",
        "1802": "Immediate Alert",
        "1803": "Link Loss",
        "1804": "Tx Power",
        "180A": "Device Information",
        "180D": "Heart Rate",
        "180F": "Battery",
        "1812": "Human Interface Device",
    ]

    /// Well-known characteristic names, again only the ones worth recognizing here.
    private static let characteristicNames: [String: String] = [
        "2A00": "Device Name",
        "2A01": "Appearance",
        "2A06": "Alert Level",
        "2A19": "Battery Level",
        "2A24": "Model Number",
        "2A25": "Serial Number",
        "2A26": "Firmware Revision",
        "2A27": "Hardware Revision",
        "2A28": "Software Revision",
        "2A29": "Manufacturer Name",
        "2A37": "Heart Rate Measurement",
        "2A38": "Body Sensor Location",
    ]

    static func serviceName(_ uuid: String) -> String? {
        serviceNames[shortUUID(uuid)]
    }

    static func characteristicName(_ uuid: String) -> String? {
        characteristicNames[shortUUID(uuid)]
    }

    /// One readable label such as `"180D Heart Rate"` or `"6E400001-B5A3-F393-E0A9-E50E24DCCA9E"`.
    static func label(service uuid: String) -> String {
        let short = shortUUID(uuid)
        return serviceName(uuid).map { "\(short) \($0)" } ?? short
    }

    static func label(characteristic uuid: String) -> String {
        let short = shortUUID(uuid)
        return characteristicName(uuid).map { "\(short) \($0)" } ?? short
    }

    /// The standard Immediate Alert service (1802) with its Alert Level characteristic (2A06) is
    /// the Bluetooth SIG's way to ask a device to alert. 0 = no alert, 1 = mild, 2 = high.
    /// Whether a device acts on it with a vibration is up to the device: test, do not assume.
    static func isImmediateAlertLevel(service: String, characteristic: String) -> Bool {
        shortUUID(service) == "1802" && shortUUID(characteristic) == "2A06"
    }
}
