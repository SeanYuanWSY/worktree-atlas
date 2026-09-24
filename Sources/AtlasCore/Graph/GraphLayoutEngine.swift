// Lane assignment adapted from Oreo992/GitScope GraphLayoutEngine.swift (MIT).
// Copyright (c) 2026 Oreo. See THIRD_PARTY_NOTICES.md for the exact upstream commit.
import Foundation

public struct GraphLayoutEngine: Sendable {
    public init() {}
    /// Input must be in child-before-parent topological order, never merely date order.
    public func lanes(for commits: [CommitNode]) -> [String: Int] {
        var laneBySHA: [String: Int] = [:]
        var activeLanes: [String?] = []
        for commit in commits {
            let lane = laneBySHA[commit.sha] ?? Self.firstFreeLane(in: activeLanes)
            laneBySHA[commit.sha] = lane
            Self.ensureLane(lane, existsIn: &activeLanes)
            guard let firstParent = commit.parentSHAs.first else {
                activeLanes[lane] = nil
                continue
            }
            let firstParentLane = laneBySHA[firstParent] ?? lane
            laneBySHA[firstParent] = firstParentLane
            Self.ensureLane(firstParentLane, existsIn: &activeLanes)
            activeLanes[lane] = firstParentLane == lane ? firstParent : nil
            if firstParentLane != lane { activeLanes[firstParentLane] = firstParent }
            for parentSHA in commit.parentSHAs.dropFirst() {
                let parentLane = laneBySHA[parentSHA] ?? Self.firstFreeLane(in: activeLanes)
                laneBySHA[parentSHA] = parentLane
                Self.ensureLane(parentLane, existsIn: &activeLanes)
                activeLanes[parentLane] = parentSHA
            }
        }
        return laneBySHA
    }
    private static func firstFreeLane(in lanes: [String?]) -> Int {
        lanes.firstIndex(where: { $0 == nil }) ?? lanes.count
    }
    private static func ensureLane(_ lane: Int, existsIn lanes: inout [String?]) {
        while lanes.count <= lane { lanes.append(nil) }
    }
}
