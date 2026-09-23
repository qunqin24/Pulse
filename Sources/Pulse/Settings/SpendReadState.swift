import Foundation

/// The Settings window's completed spend snapshot. SwiftUI owns cancellation
/// of the scan task; this state decides when to reuse/release its result and
/// prevents a cancelled predecessor from publishing into a later visit.
struct SpendReadState {
    struct Request: Hashable {
        let isEnabled: Bool
        let isWindowVisible: Bool
        let isPaneSelected: Bool
        let rescan: Int
    }

    enum Action: Equatable {
        case retain
        case release
        case scan(id: UUID, refresh: Bool)
    }

    /// Nil means no completed read. An empty snapshot is still a completed
    /// read and must not trigger IO on every sidebar visit.
    private(set) var snapshot: AgentLedgers.Snapshot?
    private(set) var snapshotID: UUID?
    private var readID: UUID?
    private var consumedRescan = 0

    mutating func prepare(_ request: Request) -> Action {
        readID = nil
        guard request.isEnabled, request.isWindowVisible else {
            snapshot = nil
            snapshotID = nil
            return .release
        }
        guard request.isPaneSelected else { return .retain }

        let refresh = request.rescan != consumedRescan
        guard snapshot == nil || refresh else { return .retain }
        // Keep at most one result: release old detail before a rescan allocates
        // its replacement, retaining the streaming reader's peak-memory win.
        snapshot = nil
        snapshotID = nil
        consumedRescan = request.rescan
        let id = UUID()
        readID = id
        return .scan(id: id, refresh: refresh)
    }

    func isCurrent(_ id: UUID) -> Bool { readID == id }

    @discardableResult
    mutating func complete(_ snapshot: AgentLedgers.Snapshot, for id: UUID) -> Bool {
        guard isCurrent(id) else { return false }
        self.snapshot = snapshot
        snapshotID = id
        return true
    }

    /// Only the current task may clear loading/progress in its defer block.
    @discardableResult
    mutating func finish(_ id: UUID) -> Bool {
        guard isCurrent(id) else { return false }
        readID = nil
        return true
    }
}
