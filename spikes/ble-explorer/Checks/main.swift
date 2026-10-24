// Checks for Shared/BLEFormat.swift. Run from spikes/ble-explorer:
//   swiftc -swift-version 6 Shared/BLEFormat.swift Checks/main.swift -o /tmp/blecheck && /tmp/blecheck
import Foundation

nonisolated(unsafe) var failures = 0
func check(_ ok: Bool, _ name: String) {
    print(ok ? "PASS  \(name)" : "FAIL  \(name)")
    if !ok { failures += 1 }
}

check(BLEFormat.hex(Data([0x01, 0x0A, 0xFF])) == "01 0A FF", "hex of three bytes")
check(BLEFormat.hex(Data()) == "(empty)", "hex of empty data")

// Property bits: read(0x02) + notify(0x10) = 0x12
check(BLEFormat.propertyNames(0x12) == ["read", "notify"], "read + notify names")
check(BLEFormat.propertyNames(0x00) == [], "no properties")
check(BLEFormat.propertyNames(0x04 | 0x08) == ["write-no-response", "write"], "both write kinds")

check(BLEFormat.canWrite(0x04), "write-no-response is writable")
check(BLEFormat.canWrite(0x08), "write is writable")
check(!BLEFormat.canWrite(0x12), "read + notify is not writable")
check(!BLEFormat.canWrite(0), "nothing is not writable")

check(BLEFormat.shortUUID("0000180d-0000-1000-8000-00805f9b34fb") == "180D", "base UUID shortens")
check(BLEFormat.shortUUID("180d") == "180D", "short UUID is upper-cased")
check(BLEFormat.shortUUID("6e400001-b5a3-f393-e0a9-e50e24dcca9e") == "6E400001-B5A3-F393-E0A9-E50E24DCCA9E",
      "custom UUID stays full")
// Starts with 0000 but is not the SIG base: must not be shortened.
check(BLEFormat.shortUUID("00001234-1111-2222-3333-444455556666") == "00001234-1111-2222-3333-444455556666",
      "non-base 0000 UUID stays full")

check(BLEFormat.label(service: "180D") == "180D Heart Rate", "known service label")
check(BLEFormat.label(service: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E") == "6E400001-B5A3-F393-E0A9-E50E24DCCA9E",
      "unknown service label is the UUID")
check(BLEFormat.label(characteristic: "2a06") == "2A06 Alert Level", "known characteristic label")

check(BLEFormat.isImmediateAlertLevel(service: "1802", characteristic: "2A06"), "immediate alert detected")
check(BLEFormat.isImmediateAlertLevel(service: "0000180a-0000-1000-8000-00805f9b34fb", characteristic: "2A06") == false,
      "alert level under another service is not immediate alert")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
