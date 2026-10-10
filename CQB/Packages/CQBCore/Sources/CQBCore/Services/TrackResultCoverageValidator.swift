import Foundation

/// Structural checks for the producer's explicit index coverage. This does not
/// rerun V13, infer provenance, or certify that a claimed correction is accurate.
/// O(samples + vertices + coverage + diagnostics), including overlapping diagnostics.
enum TrackResultCoverageValidator {
    private static let timeTolerance = 1e-8

    static func validate(_ result: TrackResultDocument, raw: RawTrackDocument,
                         floorPlan: ValidatedFloorPlan) throws {
        let samples = raw.samples
        let offset = raw.recordingStartOffsetSeconds
        let diagnosticPrefix = try diagnosticCoverage(result.unresolvedIntervals, raw: raw)
        var nextSample = 0, nextVertex = 0
        var previousRun: (lastSample: Int, lastVertex: Int)?
        var usable = false, hasMissing = false

        for coverage in result.sampleCoverage {
            try Task.checkCancellation()
            let range = coverage.samples
            guard range.from == nextSample, valid(range, count: samples.count) else {
                throw TrackValidationError.invalidCoverage
            }
            nextSample = range.through + 1
            guard let vertices = coverage.vertices else {
                hasMissing = true
                // Every unknown sample needs an explicit diagnostic. A normal
                // vertex with the same time never supplies coverage for it.
                guard diagnosticPrefix[range.through + 1] - diagnosticPrefix[range.from] ==
                        range.through - range.from + 1 else {
                    throw TrackValidationError.invalidCoverage
                }
                continue
            }
            guard vertices.from == nextVertex, vertices.from >= 0,
                  vertices.through >= vertices.from, vertices.through < result.vertices.count else {
                throw TrackValidationError.invalidCoverage
            }
            nextVertex = vertices.through + 1
            let first = result.vertices[vertices.from], last = result.vertices[vertices.through]
            let start = samples[range.from].time + offset, end = samples[range.through].time + offset

            // A declared continuous run cannot skip unknown raw positions or
            // cross a segment boundary, even when both sides have equal times.
            for index in range.from...range.through {
                try Task.checkCancellation()
                guard samples[index].relativeMeters != nil,
                      samples[index].segment == samples[range.from].segment else {
                    throw TrackValidationError.disconnectedPath
                }
            }
            if let previousRun {
                let previous = result.vertices[previousRun.lastVertex]
                // Adjacent output vertices with the same part would be drawn as
                // an edge, irrespective of a missing coverage block in between.
                guard previous.part != first.part else { throw TrackValidationError.disconnectedPath }
                guard first.t >= previous.t else { throw TrackValidationError.invalidResult }
                // A V13 resume-only diagnostic is enough; it need not exclude
                // either endpoint or expand to the preceding solved sample.
                guard diagnosticPrefix[range.from + 1] > diagnosticPrefix[previousRun.lastSample + 1] else {
                    throw TrackValidationError.invalidInterval
                }
            }
            guard abs(first.t - start) <= timeTolerance, abs(last.t - end) <= timeTolerance else {
                throw TrackValidationError.invalidCoverage
            }
            var previous: TrackResultVertex?
            for index in vertices.from...vertices.through {
                try Task.checkCancellation()
                let vertex = result.vertices[index]
                guard vertex.t.isFinite, vertex.t >= start - timeTolerance, vertex.t <= end + timeTolerance,
                      vertex.part >= 0, !floorPlan.isBlocked(at: vertex.point) else {
                    throw TrackValidationError.invalidResult
                }
                guard vertex.part == first.part else { throw TrackValidationError.invalidCoverage }
                if let sourceIndex = vertex.sampleIndex {
                    guard sourceIndex >= range.from, sourceIndex <= range.through else {
                        throw TrackValidationError.invalidResult
                    }
                    if vertex.provenance == .correctedSample,
                       abs(vertex.t - (samples[sourceIndex].time + offset)) > timeTolerance {
                        throw TrackValidationError.invalidResult
                    }
                } else if vertex.provenance == .correctedSample {
                    throw TrackValidationError.invalidResult
                }
                if let previous {
                    guard vertex.t >= previous.t else { throw TrackValidationError.invalidResult }
                    if vertex.point != previous.point { usable = true }
                }
                previous = vertex
            }
            // When the producer explicitly identifies an actual corrected raw
            // sample, equal timestamps cannot enlarge its boundary to a different
            // sample. Generated/unspecified endpoints do not carry this evidence.
            if first.provenance == .correctedSample, first.sampleIndex != range.from {
                throw TrackValidationError.invalidCoverage
            }
            if last.provenance == .correctedSample, last.sampleIndex != range.through {
                throw TrackValidationError.invalidCoverage
            }
            previousRun = (range.through, vertices.through)
        }
        guard nextSample == samples.count, nextVertex == result.vertices.count else {
            throw TrackValidationError.invalidCoverage
        }
        switch result.status {
        case .failed:
            guard result.vertices.isEmpty, hasMissing, !result.unresolvedIntervals.isEmpty else {
                throw TrackValidationError.invalidStatus
            }
        case .done:
            guard usable, !hasMissing, result.unresolvedIntervals.isEmpty, result.failureReason == nil else {
                throw TrackValidationError.invalidStatus
            }
        case .partial:
            guard usable, !result.unresolvedIntervals.isEmpty, result.failureReason == nil else {
                throw TrackValidationError.invalidStatus
            }
        }
    }

    /// Prefix count of indices covered by at least one diagnostic. Unlike the
    /// old time sweep this supports overlapping/unsorted V13 diagnostics without
    /// rewriting them, and costs linear time rather than ranges × samples.
    private static func diagnosticCoverage(_ ranges: [TrackUnresolvedInterval],
                                           raw: RawTrackDocument) throws -> [Int] {
        var prefix = [Int](repeating: 0, count: raw.samples.count + 1)
        for range in ranges {
            try Task.checkCancellation()
            guard valid(range.samples, count: raw.samples.count), range.from.isFinite, range.to.isFinite,
                  range.from <= range.to, range.from != range.to || range.bounds == .closed,
                  abs(range.from - (raw.samples[range.samples.from].time + raw.recordingStartOffsetSeconds)) <= timeTolerance,
                  abs(range.to - (raw.samples[range.samples.through].time + raw.recordingStartOffsetSeconds)) <= timeTolerance else {
                throw TrackValidationError.invalidInterval
            }
            prefix[range.samples.from] += 1
            prefix[range.samples.through + 1] -= 1
        }
        var active = 0, covered = 0
        for index in raw.samples.indices {
            try Task.checkCancellation()
            active += prefix[index]
            prefix[index] = covered
            if active > 0 { covered += 1 }
        }
        prefix[raw.samples.count] = covered
        return prefix
    }

    private static func valid(_ range: TrackSampleRange, count: Int) -> Bool {
        range.from >= 0 && range.through >= range.from && range.through < count
    }
}
