import Foundation
import Testing
@testable import Whoosh

/// Tests for `SupabaseCrashNotifier` (crash-response task 25) using an injected
/// `CrashNotifierTransport` double — **no real network**. They cover the policy
/// the notifier owns: request encoding (contract §5.2, no footage/free-text
/// field), response decoding (§5.5), `deduplicated`, status `GET` query shape
/// (§6), typed-error mapping from the structured body and from the HTTP status
/// (§5.3/§13), the one `401` session refresh + retry, timeout, and offline.
struct SupabaseCrashNotifierTests {

    // MARK: - Transport double

    /// Records calls and returns scripted bytes or throws scripted transport
    /// errors. An `actor` to match the `Sendable` transport protocol; a
    /// `Mutex`-free design is fine since the notifier awaits each call.
    actor FakeCrashTransport: CrashNotifierTransport {
        struct PostCall: Sendable { let function: String; let body: Data; let timeout: TimeInterval }
        struct GetCall: Sendable { let function: String; let query: [URLQueryItem]; let timeout: TimeInterval }

        enum Outcome: Sendable {
            case data(Data)
            case error(CrashTransportError)
        }

        /// A queue of outcomes consumed front-to-back; the last one repeats.
        private var outcomes: [Outcome]
        private(set) var ensureSessionCount = 0
        private(set) var postCalls: [PostCall] = []
        private(set) var getCalls: [GetCall] = []

        init(_ outcomes: [Outcome]) { self.outcomes = outcomes }

        func ensureSession() async throws { ensureSessionCount += 1 }

        func post(functionName: String, body: Data, timeout: TimeInterval) async throws -> Data {
            postCalls.append(PostCall(function: functionName, body: body, timeout: timeout))
            return try next()
        }

        func get(functionName: String, query: [URLQueryItem], timeout: TimeInterval) async throws -> Data {
            getCalls.append(GetCall(function: functionName, query: query, timeout: timeout))
            return try next()
        }

        private func next() throws -> Data {
            let outcome = outcomes.count > 1 ? outcomes.removeFirst() : (outcomes.first ?? .error(CrashTransportError(statusCode: nil)))
            switch outcome {
            case let .data(data): return data
            case let .error(error): throw error
            }
        }
    }

    // MARK: - Fixtures

    private let eventId = UUID(uuidString: "5b0b6f0e-2c0a-4a35-9a54-5f3a8f6f1a11")!
    private let ref1 = UUID(uuidString: "c1d4a3d2-0b87-4b9b-8b4c-1f2a3b4c5d6e")!
    private let ref2 = UUID(uuidString: "9e8d7c6b-5a49-4382-9170-0a1b2c3d4e5f")!

    private func request(
        kind: CrashMessageKind = .crashAlert,
        location: LocationSnapshot? = LocationSnapshot(
            latitude: 42.360123, longitude: -71.058881,
            horizontalAccuracy: 12.4, fixTime: Date(timeIntervalSince1970: 1_700_000_000),
            status: .current
        )
    ) -> CrashNotificationRequest {
        CrashNotificationRequest(
            crashEventId: eventId,
            kind: kind,
            riderLabel: "Alex",
            detectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            utcOffsetMinutes: -240,
            delayedSeconds: 0,
            location: location,
            recipients: [
                CrashNotificationRecipient(recipientRef: ref1, e164: "+16175550123"),
                CrashNotificationRecipient(recipientRef: ref2, e164: "+16175550124"),
            ],
            consentVersion: 1,
            templateVersion: 1
        )
    }

    private func successBody(deduplicated: Bool = false) -> Data {
        let json = """
        {
          "schemaVersion": 1,
          "requestId": "req_1",
          "crashEventId": "5b0b6f0e-2c0a-4a35-9a54-5f3a8f6f1a11",
          "kind": "crash_alert",
          "deduplicated": \(deduplicated),
          "recipients": [
            { "recipientRef": "c1d4a3d2-0b87-4b9b-8b4c-1f2a3b4c5d6e", "status": "queued", "errorCode": null, "providerErrorCode": null, "segments": 4, "updatedAt": "2026-10-24T17:41:39Z" },
            { "recipientRef": "9e8d7c6b-5a49-4382-9170-0a1b2c3d4e5f", "status": "rejected", "errorCode": "trial_recipient_unverified", "providerErrorCode": 21608, "segments": 0, "updatedAt": "2026-10-24T17:41:39Z" }
          ],
          "serverTime": "2026-10-24T17:41:39Z"
        }
        """
        return Data(json.utf8)
    }

    // MARK: - Success / decoding (§5.5)

    @Test func sendDecodesPerRecipientResults() async throws {
        let transport = FakeCrashTransport([.data(successBody())])
        let notifier = SupabaseCrashNotifier(transport: transport, appVersion: "1.0 (42)")

        let result = try await notifier.send(request())

        #expect(result.crashEventId == eventId)
        #expect(result.kind == .crashAlert)
        #expect(result.deduplicated == false)
        #expect(result.recipients.count == 2)
        let queued = result.recipients.first { $0.recipientRef == ref1 }
        #expect(queued?.status == .queued)
        #expect(queued?.segments == 4)
        let rejected = result.recipients.first { $0.recipientRef == ref2 }
        #expect(rejected?.status == .rejected)
        #expect(rejected?.whooshErrorCode == "trial_recipient_unverified")
        #expect(rejected?.providerErrorCode == 21608)

        let posts = await transport.postCalls
        #expect(posts.count == 1)
        #expect(posts.first?.function == "send-crash-alert")
        #expect(posts.first?.timeout == 10)
    }

    @Test func sendSurfacesDeduplicated() async throws {
        let transport = FakeCrashTransport([.data(successBody(deduplicated: true))])
        let notifier = SupabaseCrashNotifier(transport: transport, appVersion: "1.0")
        let result = try await notifier.send(request())
        #expect(result.deduplicated == true)
    }

    // MARK: - Request shape (§5.2): no footage/free-text; location rules

    @Test func sendBodyHasOnlyContractFieldsAndNoFootage() async throws {
        let transport = FakeCrashTransport([.data(successBody())])
        let notifier = SupabaseCrashNotifier(transport: transport, appVersion: "1.0 (42)")
        _ = try await notifier.send(request())

        let body = await transport.postCalls.first!.body
        let obj = try JSONSerialization.jsonObject(with: body) as! [String: Any]

        // Exactly the contract's top-level keys — nothing that could carry a
        // clip, URL, media, or arbitrary message text.
        let keys = Set(obj.keys)
        #expect(keys == [
            "schemaVersion", "templateVersion", "crashEventId", "kind",
            "riderLabel", "detectedAt", "utcOffsetMinutes", "delayedSeconds",
            "location", "recipients", "consent", "appVersion",
        ])
        #expect((obj["kind"] as? String) == "crash_alert")
        #expect((obj["detectedAt"] as? String) == "2023-11-14T22:13:20Z")
        // Precise coordinates to 5 decimals; accuracy rounded, min 1.
        let loc = obj["location"] as! [String: Any]
        #expect((loc["status"] as? String) == "current")
        #expect((loc["latitude"] as? Double) == 42.36012)
        #expect((loc["longitude"] as? Double) == -71.05888)
        #expect((loc["accuracyMeters"] as? Int) == 12)
    }

    @Test func testKindSendsNoLocation() async throws {
        let transport = FakeCrashTransport([.data(successBody())])
        let notifier = SupabaseCrashNotifier(transport: transport, appVersion: "1.0")
        _ = try await notifier.send(request(kind: .test, location: nil))

        let body = await transport.postCalls.first!.body
        let obj = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        #expect(obj["location"] == nil)
    }

    @Test func unavailableLocationOmitsCoordinates() async throws {
        let transport = FakeCrashTransport([.data(successBody())])
        let notifier = SupabaseCrashNotifier(transport: transport, appVersion: "1.0")
        _ = try await notifier.send(request(location: .unavailable))

        let body = await transport.postCalls.first!.body
        let obj = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let loc = obj["location"] as! [String: Any]
        #expect((loc["status"] as? String) == "unavailable")
        #expect(loc["latitude"] == nil)
        #expect(loc["longitude"] == nil)
        #expect(loc["accuracyMeters"] == nil)
    }

    // MARK: - Status GET (§6)

    @Test func statusBuildsQueryAndDecodes() async throws {
        let transport = FakeCrashTransport([.data(successBody())])
        let notifier = SupabaseCrashNotifier(transport: transport, appVersion: "1.0")

        let result = try await notifier.status(crashEventId: eventId, kind: .crashAlert)
        #expect(result.recipients.count == 2)

        let gets = await transport.getCalls
        #expect(gets.count == 1)
        #expect(gets.first?.function == "crash-alert-status")
        let query = gets.first?.query ?? []
        #expect(query.contains(URLQueryItem(name: "crashEventId", value: eventId.uuidString.lowercased())))
        #expect(query.contains(URLQueryItem(name: "kind", value: "crash_alert")))
    }

    // MARK: - Error mapping (§5.3/§13)

    @Test func structuredErrorBodyMapsToTypedCode() async throws {
        let body = Data(#"{ "code": "rate_limited", "retryable": false }"#.utf8)
        let transport = FakeCrashTransport([.error(CrashTransportError(statusCode: 429, body: body))])
        let notifier = SupabaseCrashNotifier(transport: transport, appVersion: "1.0")

        await #expect(throws: CrashNotifierError(code: .rateLimited, isRetryable: false)) {
            _ = try await notifier.send(request())
        }
    }

    @Test func serviceDisabledBodyIsNonRetryable() async throws {
        let body = Data(#"{ "code": "service_disabled", "retryable": false }"#.utf8)
        let transport = FakeCrashTransport([.error(CrashTransportError(statusCode: 503, body: body))])
        let notifier = SupabaseCrashNotifier(transport: transport, appVersion: "1.0")
        do {
            _ = try await notifier.send(request())
            Issue.record("expected throw")
        } catch let error as CrashNotifierError {
            #expect(error.code == .serviceDisabled)
            #expect(error.isRetryable == false)
        }
    }

    @Test func httpStatusWithoutBodyIsClassified() async throws {
        // 500 with no usable body ⇒ retryable server error.
        let transport = FakeCrashTransport([.error(CrashTransportError(statusCode: 500, body: nil))])
        let notifier = SupabaseCrashNotifier(transport: transport, appVersion: "1.0")
        do {
            _ = try await notifier.send(request())
            Issue.record("expected throw")
        } catch let error as CrashNotifierError {
            #expect(error.code == .serverError)
            #expect(error.isRetryable)
        }
    }

    @Test func timeoutMapsToTimeoutCode() async throws {
        let transport = FakeCrashTransport([.error(CrashTransportError(statusCode: nil, isTimeout: true))])
        let notifier = SupabaseCrashNotifier(transport: transport, appVersion: "1.0")
        await #expect(throws: CrashNotifierError(.timeout)) {
            _ = try await notifier.send(request())
        }
    }

    @Test func offlineMapsToNoConnection() async throws {
        let transport = FakeCrashTransport([.error(CrashTransportError(statusCode: nil))])
        let notifier = SupabaseCrashNotifier(transport: transport, appVersion: "1.0")
        await #expect(throws: CrashNotifierError(.noConnection)) {
            _ = try await notifier.send(request())
        }
    }

    // MARK: - 401 refresh + retry (§13)

    @Test func unauthorizedRefreshesSessionOnceThenSucceeds() async throws {
        let transport = FakeCrashTransport([
            .error(CrashTransportError(statusCode: 401)),
            .data(successBody()),
        ])
        let notifier = SupabaseCrashNotifier(transport: transport, appVersion: "1.0")

        let result = try await notifier.send(request())
        #expect(result.recipients.count == 2)

        // One pre-warm + one refresh ⇒ two ensureSession calls; two POSTs.
        let ensures = await transport.ensureSessionCount
        let posts = await transport.postCalls.count
        #expect(ensures == 2)
        #expect(posts == 2)
    }

    @Test func unauthorizedTwiceSurfacesTypedError() async throws {
        let transport = FakeCrashTransport([
            .error(CrashTransportError(statusCode: 401)),
            .error(CrashTransportError(statusCode: 401)),
        ])
        let notifier = SupabaseCrashNotifier(transport: transport, appVersion: "1.0")
        await #expect(throws: CrashNotifierError(.unauthenticated)) {
            _ = try await notifier.send(request())
        }
    }
}
