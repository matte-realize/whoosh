// WhoopFrame.swift
// Pure WHOOP 5.0 ("puffin") frame builder and decoder for the buzz spike. Foundation only, so it
// type-checks and runs without Xcode: see Checks/main.swift.
//
// Format, from the Goose reverse engineering (Rust/core/src/protocol.rs, build_v5_command_frame)
// and dbuffel/Whoop-Mac docs/PROTOCOL.md:
//   AA 01 <declLen u16 LE> 00 01 <crc16-modbus of those 6 bytes, LE> <payload> <crc32(payload) LE>
//   payload = [35 (COMMAND), seq, cmd, data...] zero-padded to a multiple of 4 bytes
//   declLen = padded payload length + 4

import Foundation

enum WhoopFrame {
    static let startOfFrame: UInt8 = 0xAA
    static let commandPacketType: UInt8 = 35

    /// Command numbers this spike sends. All are non-destructive.
    enum Command: UInt8 {
        case runAlarm = 68
        case runHapticsPattern = 79
        case stopHaptics = 122
        case getHello = 145
    }

    /// CRC16-Modbus: init 0xFFFF, reflected poly 0xA001.
    static func crc16Modbus(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc
    }

    /// Standard zlib CRC-32: init 0xFFFFFFFF, reflected poly 0xEDB88320, final XOR.
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }

    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]
    }

    /// Wrap an already-assembled payload in the 5.0 envelope (pads it to a multiple of 4).
    static func envelope(payload: [UInt8]) -> [UInt8] {
        var padded = payload
        let remainder = padded.count % 4
        if remainder != 0 { padded += [UInt8](repeating: 0, count: 4 - remainder) }
        let declaredLength = UInt16(padded.count + 4)
        var frame: [UInt8] = [startOfFrame, 0x01] + le16(declaredLength) + [0x00, 0x01]
        frame += le16(crc16Modbus(frame))
        frame += padded
        frame += le32(crc32(padded))
        return frame
    }

    static func command(_ command: Command, seq: UInt8, data: [UInt8]) -> [UInt8] {
        envelope(payload: [commandPacketType, seq, command.rawValue] + data)
    }

    /// The static session hello that Whoop-Mac and Goose write right after discovery. It is the
    /// `getHello` command with seq 1 and data [1]; the checks prove the builder reproduces it.
    static let hello: [UInt8] = [
        0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0xE6, 0x71,
        0x23, 0x01, 0x91, 0x01, 0x36, 0x3E, 0x5C, 0x8D,
    ]

    /// RUN_ALARM (68) in Goose's 5.0 form: data = [2, alarmID].
    static func runAlarm(seq: UInt8, alarmID: UInt8) -> [UInt8] {
        command(.runAlarm, seq: seq, data: [2, alarmID])
    }

    /// RUN_HAPTICS_PATTERN (79) in the 4.0 form: data = [patternId, loops, 0, 0, 0]. Unverified on 5.0.
    static func runHapticsPattern(seq: UInt8, patternID: UInt8, loops: UInt8) -> [UInt8] {
        command(.runHapticsPattern, seq: seq, data: [patternID, loops, 0, 0, 0])
    }

    static func stopHaptics(seq: UInt8) -> [UInt8] {
        command(.stopHaptics, seq: seq, data: [0])
    }

    // MARK: Decoding (for the log only)

    struct Summary: Equatable {
        let crcOK: Bool
        let packetType: UInt8
        let seq: UInt8
        let cmdOrEvent: UInt8
    }

    /// Validate and summarise one complete 5.0 frame. Returns nil when it is not a whole frame.
    static func summarize(_ bytes: [UInt8]) -> Summary? {
        guard bytes.count >= 16, bytes[0] == startOfFrame else { return nil }
        let declared = Int(bytes[2]) | Int(bytes[3]) << 8
        guard bytes.count >= declared + 8, declared >= 4 + 3 else { return nil }
        let headerOK = crc16Modbus(Array(bytes[0..<6])) == UInt16(bytes[6]) | UInt16(bytes[7]) << 8
        let payload = Array(bytes[8..<(8 + declared - 4)])
        let tail = Array(bytes[(8 + declared - 4)..<(8 + declared)])
        let payloadOK = le32(crc32(payload)) == tail
        return Summary(
            crcOK: headerOK && payloadOK,
            packetType: payload[0], seq: payload[1], cmdOrEvent: payload[2])
    }

    static func packetTypeName(_ type: UInt8) -> String {
        switch type {
        case 35: return "COMMAND"
        case 36: return "COMMAND_RESPONSE"
        case 37: return "PUFFIN_COMMAND"
        case 38: return "PUFFIN_COMMAND_RESPONSE"
        case 40: return "REALTIME_DATA"
        case 43: return "REALTIME_RAW_DATA"
        case 47: return "HISTORICAL_DATA"
        case 48: return "EVENT"
        case 49: return "METADATA"
        case 50: return "CONSOLE_LOGS"
        case 53: return "RELATIVE_PUFFIN_EVENTS"
        case 54: return "PUFFIN_EVENTS_FROM_STRAP"
        case 56: return "PUFFIN_METADATA"
        default: return "type\(type)"
        }
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.isEmpty ? "(empty)" : bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
