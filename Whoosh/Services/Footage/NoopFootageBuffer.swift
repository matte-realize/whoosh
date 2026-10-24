import Foundation

/// The v1 default `FootageBuffer`: there is no camera footage, so `preserve`
/// always returns `nil` ("no footage") and `delete` is a no-op (spec design
/// "Service protocols"). Injected at the composition root so the coordinator
/// always has a non-optional buffer.
///
/// Contains no camera, capture, or network code.
struct NoopFootageBuffer: FootageBuffer {
    init() {}

    /// No-op: no footage exists, so no reference is produced.
    func preserve(eventId: UUID, around detectedAt: Date) -> String? { nil }

    /// No-op: nothing to delete.
    func delete(reference: String) {}
}
