import Foundation
import JavaScriptCore

/// Runs web/src/lib/sim/engine.ts (transpiled by build-engine.mjs) in JavaScriptCore, so the film
/// uses exactly the same simulation as the website.

struct VehicleState: Decodable {
    let id: Int
    let kind: String
    let x: Double
    let z: Double
    let length: Double
    let width: Double
    let height: Double
    let speed: Double
    let direction: Int
    let state: String
    let missed: Bool
}

struct NearMissState: Decodable {
    let id: Int
    let t: Double
    let source: String
    let kind: String?
    let hint: String?
    let score: Double?
    let lat: Double
    let lon: Double
    let at: Double
    let falseAlarm: Bool
}

struct SimSnapshot: Decodable {
    let t: Double
    let riderDistance: Double
    let riderSpeed: Double
    let rideStartsAt: Double
    let recording: Bool
    let rideTime: Double
    let vehicles: [VehicleState]
    let cue: Bool
    let lastCueHint: String?
    let lastCueKind: String?
    let nearMisses: [NearMissState]
    let toast: Bool
    let crashPhase: String
    let crashDetectedAt: Double
    let crashSentAt: Double?
    let crashEndedAt: Double?
    let remaining: Double?
    let fall: Double
    let riderDown: Bool
    let message: String?
    let messageTime: String?
    let clock: String
    let lat: Double
    let lon: Double
}

struct RouteInfo: Decodable {
    let points: [[Double]]
    let length: Double
}

final class Engine {
    private let context: JSContext

    init(engineFile: URL) throws {
        guard let ctx = JSContext() else { throw NSError(domain: "Engine", code: 1) }
        context = ctx
        var jsError: String?
        context.exceptionHandler = { _, value in jsError = value?.toString() }
        let source = try String(contentsOf: engineFile, encoding: .utf8)
        context.evaluateScript(source)
        if let jsError { throw NSError(domain: "Engine", code: 2, userInfo: [NSLocalizedDescriptionKey: jsError]) }
    }

    private func call(_ name: String, _ args: [Any]) -> JSValue {
        let fn = context.objectForKeyedSubscript("film")!.objectForKeyedSubscript(name)!
        let value = fn.call(withArguments: args)!
        if let e = context.exception {
            fatalError("JS error in film.\(name): \(e)")
        }
        return value
    }

    func create(_ name: String, scenario: String) { _ = call("create", [name, scenario]) }
    func advance(_ name: String, by dt: Double) { if dt > 0 { _ = call("advance", [name, dt]) } }

    func snapshot(_ name: String) -> SimSnapshot {
        let json = call("state", [name]).toString()!
        do {
            return try JSONDecoder().decode(SimSnapshot.self, from: Data(json.utf8))
        } catch {
            fatalError("bad snapshot: \(error)\n\(json.prefix(400))")
        }
    }

    func route() -> RouteInfo {
        let json = call("route", []).toString()!
        return try! JSONDecoder().decode(RouteInfo.self, from: Data(json.utf8))
    }

    func routePoint(_ meters: Double) -> (lat: Double, lon: Double) {
        let v = call("routePoint", [meters])
        return (v.objectForKeyedSubscript("lat").toDouble(), v.objectForKeyedSubscript("lon").toDouble())
    }
}
