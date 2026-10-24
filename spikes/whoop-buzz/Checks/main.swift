// Checks for WhoopFrame. Run with no Xcode:
//   swiftc -swift-version 6 Shared/WhoopFrame.swift Checks/main.swift -o /tmp/whoopcheck && /tmp/whoopcheck

import Foundation

nonisolated(unsafe) var failures = 0
func check(_ ok: Bool, _ name: String) {
    print("\(ok ? "PASS" : "FAIL")  \(name)")
    if !ok { failures += 1 }
}

// The strongest check: the builder must reproduce the known-good 16-byte hello byte for byte.
let rebuilt = WhoopFrame.command(.getHello, seq: 1, data: [1])
check(rebuilt == WhoopFrame.hello, "builder reproduces the known hello frame (\(WhoopFrame.hex(rebuilt)))")

check(WhoopFrame.crc32(Array("123456789".utf8)) == 0xCBF4_3926, "crc32 of '123456789' is the standard CBF43926")
check(WhoopFrame.crc16Modbus(Array("123456789".utf8)) == 0x4B37, "crc16-modbus of '123456789' is the standard 4B37")

let alarm = WhoopFrame.runAlarm(seq: 64, alarmID: 0)
check(alarm.count == 20, "RUN_ALARM frame is 20 bytes (5-byte payload padded to 8, +4 crc32, +8 header)")
check(Array(alarm[8..<16]) == [35, 64, 68, 2, 0, 0, 0, 0], "RUN_ALARM payload is [35, seq, 68, 2] zero-padded to 8")
check(alarm[2] == 12 && alarm[3] == 0, "RUN_ALARM declared length is 12 (padded payload 8 + crc32 4)")
check(WhoopFrame.summarize(alarm) == .init(crcOK: true, packetType: 35, seq: 64, cmdOrEvent: 68),
      "RUN_ALARM frame decodes back with both CRCs valid")

var broken = alarm
broken[9] ^= 0xFF
check(WhoopFrame.summarize(broken)?.crcOK == false, "a corrupted payload byte fails the CRC")
check(WhoopFrame.summarize([0xAA, 0x01]) == nil, "a truncated frame is rejected")

for len in 0...7 {
    let f = WhoopFrame.envelope(payload: [UInt8](repeating: 9, count: len + 3))
    check((f.count - 12) % 4 == 0 && WhoopFrame.summarize(f)?.crcOK == true, "payload of \(len + 3) bytes pads to a multiple of 4 and decodes")
}

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
