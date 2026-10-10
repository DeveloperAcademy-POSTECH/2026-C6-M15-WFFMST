import Foundation

nonisolated enum DeformationLevel: String, Codable, CaseIterable, Sendable {
    case conservative, standard, flexible
    nonisolated var title: String {
        switch self { case .conservative: return "보수적"; case .standard: return "표준"; case .flexible: return "큰 변형 실험" }
    }
    nonisolated var angleLimit: Double {
        switch self { case .conservative: return 45; case .standard: return 100; case .flexible: return 170 }
    }
    nonisolated var factorRange: ClosedRange<Double> {
        switch self { case .conservative: return 0.80...1.20; case .standard: return 0.65...1.35; case .flexible: return 0.50...1.60 }
    }
    nonisolated var beamSize: Int { self == .flexible ? 256 : 160 }
}

nonisolated struct RouteDeformationSummary: Codable, Sendable {
    let maxDirectionChangeDegrees: Double
    let maxTurnChangeDegrees: Double
    let minimumStepFactor: Double
    let maximumStepFactor: Double
    let endpointShiftMeters: Double
    let largeDeformation: Bool
    let completedFraction: Double
    let retainedHypotheses: Int
}

nonisolated struct RouteShapePolicy: Codable, Sendable {
    let totalTolerance: Double
    let windowTolerance: Double
    let windowMeters: Double
    // Optional for byte-compatible decoding of V12 policies. V12 remains a selectable control.
    var detectorVersion: Int? = nil
    nonisolated var improved: Bool { detectorVersion == 2 }
    nonisolated var excursionAngleDegrees:Double { totalTolerance<=0.051 ? 30 : (totalTolerance<=0.101 ? 45 : 75) }
    nonisolated static func make(_ level: DeformationLevel) -> Self {
        switch level {
        case .conservative: return Self(totalTolerance:0.05,windowTolerance:0.10,windowMeters:3)
        case .standard: return Self(totalTolerance:0.10,windowTolerance:0.20,windowMeters:3)
        case .flexible: return Self(totalTolerance:0.20,windowTolerance:0.35,windowMeters:3)
        }
    }
    nonisolated static func improved(_ level: DeformationLevel) -> Self {
        var policy=make(level); policy.detectorVersion=2; return policy
    }
}
nonisolated struct RouteExcursion: Codable, Sendable {
    let from: Int
    let through: Int
    let lengthMeters: Double
    let radiusMeters: Double
}
nonisolated struct RouteExcursionFit: Codable, Sendable {
    let from: Int
    let through: Int
    let returnErrorMeters: Double
    let lengthRatio: Double
    let shapeRMSErrorMeters: Double
}
nonisolated struct RouteShapeSummary: Codable, Sendable {
    let policy: RouteShapePolicy
    let excursions: [RouteExcursion]
    let fittedExcursions: [RouteExcursionFit]
    let coveredLengthRatio: Double
    let minimumWindowRatio: Double
    let maximumWindowRatio: Double
    let qualityPenalty: Double
    var detectionIncomplete: Bool? = nil
}

private nonisolated struct DeformationObservation: Sendable {
    let point: MapPoint
    let index: Int
    let time: Double
    let segment: Int
    let restart: Bool
    let travel: Double
}
private nonisolated struct DeformationNode: Sendable {
    let point: MapPoint
    let bias: Double
    let factor: Double
    let cost: Double
    let parent: Int?
    let observation: Int
    let part: Int
    var length = 0.0
    var excursionRoot: Int? = nil
}
nonisolated private struct DeformationKey: Hashable, Sendable {
    let x: Int, y: Int, direction: Int, factor: Int
    var entryX = 0
    var entryY = 0
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(x); hasher.combine(y); hasher.combine(direction); hasher.combine(factor)
        hasher.combine(entryX); hasher.combine(entryY)
    }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y && lhs.direction == rhs.direction && lhs.factor == rhs.factor
            && lhs.entryX == rhs.entryX && lhs.entryY == rhs.entryY
    }
}

/// Deterministic motion-state hypotheses with ancestry backtracking, not Monte Carlo resampling.
/// Map constraints are applied to the entire motion segment; no A* shortcut or absolute 2m search radius.
nonisolated enum NonrigidRouteMatcher {
    nonisolated private static func distance(_ a: MapPoint, _ b: MapPoint) -> Double { hypot(b.x-a.x,b.y-a.y) }
    nonisolated private static func wrap(_ x: Double) -> Double { atan2(sin(x),cos(x)) }

    nonisolated static func match(input: [MatchInput], anchor: MapPoint, pixelsPerMeter: Double,
        rotationDegrees: Double, map: MatchNavigationMap, mapHash: String, recordingID: String,
        level: DeformationLevel = .standard, budgetSeconds: Double = 20,
        shapePolicy: RouteShapePolicy? = nil,
        coherentOnly: Bool = false,
        progress: @Sendable (Double) -> Void = { _ in }) -> MapMatchResult? {
        guard pixelsPerMeter.isFinite, pixelsPerMeter > 0, rotationDegrees.isFinite,
              input.count > 1, map.grid.isFree(anchor), budgetSeconds > 0 else { return nil }
        let began = Date(), deadline = began.addingTimeInterval(budgetSeconds)
        let observations = makeObservations(input)
        guard observations.count > 1 else { return nil }
        let detection = shapePolicy?.improved == true ? findImprovedExcursions(observations,deadline:deadline) : nil
        let excursions = detection?.events ?? (shapePolicy == nil ? [] : findExcursions(observations))
        var eventForObservation = [Int?](repeating:nil,count:observations.count)
        for (ei,event) in excursions.enumerated() {
            for oi in event.start...event.settle { eventForObservation[oi]=ei }
        }
        let rotation = rotationDegrees * .pi/180
        let coherentLimit=level == .conservative ? 6.0 : (level == .standard ? 12.0 : 24.0)
        let limit = (coherentOnly ? min(level.angleLimit,coherentLimit) : level.angleLimit) * .pi/180
        let positionBin = max(map.grid.cellSize,pixelsPerMeter*0.12)
        var nodes: [DeformationNode] = [], beam: [Int] = [], ends: [Int] = []
        var unresolved: [UnresolvedRouteRange] = [], part = 0, limited = detection?.limited ?? false
        var failedSegment = false
        let seedFactors = [1.0,0.9,0.8,0.7,1.1,1.2].filter { level.factorRange.contains($0) }
        progress(0.01)
        for oi in observations.indices {
            if Task.isCancelled { return nil }
            let o = observations[oi]
            if Date() >= deadline || nodes.count >= 500_000 {
                unresolved.append(UnresolvedRouteRange(from:o.index,through:input.count-1,reason:"V9 탐색 시간/메모리 한도"))
                limited = true; break
            }
            if o.restart {
                if !beam.isEmpty { ends.append(beam[0]) }
                beam = []
                if oi > 0 { part += 1 }
                failedSegment = false
                let root = oi == 0 ? anchor : AnchoredMapMatcher.transformed(o.point,anchor:anchor,
                    scale:pixelsPerMeter,rotation:rotationDegrees,factor:1)
                if oi > 0 { unresolved.append(UnresolvedRouteRange(from:o.index,through:o.index,reason:"추적 단절 이후 연결 미확인")) }
                if map.grid.isFree(root) {
                    for factor in seedFactors {
                        beam.append(nodes.count)
                        nodes.append(DeformationNode(point:root,bias:0,factor:factor,cost:0.06*pow(log(factor),2),
                            parent:nil,observation:oi,part:part))
                    }
                } else {
                    failedSegment = true
                    unresolved.append(UnresolvedRouteRange(from:o.index,through:endOfSegment(oi,observations),reason:"재개 위치가 장애물 · 연결 미확인"))
                }
                continue
            }
            if failedSegment { continue }
            let previous = observations[oi-1]
            let dx = o.point.x-previous.point.x, dy = o.point.y-previous.point.y
            let rawDistance = hypot(dx,dy)
            let desired = atan2(dy,dx)+rotation
            let nominal = AnchoredMapMatcher.transformed(o.point,anchor:anchor,scale:pixelsPerMeter,rotation:rotationDegrees,factor:1)
            var proposals: [DeformationNode] = []
            proposals.reserveCapacity(beam.count*24)
            var visited = 0
            for id in beam {
                let parent = nodes[id]
                var windowRoot=id
                if let policy=shapePolicy {
                    while let ancestor=nodes[windowRoot].parent,
                        o.travel-observations[nodes[ancestor].observation].travel<=policy.windowMeters+0.3 {
                        windowRoot=ancestor
                    }
                }
                let event=eventForObservation[oi].map { excursions[$0] }
                let entryID=event.flatMap { previous.index == observations[$0.start].index ? id : parent.excursionRoot }
                var approachBias=parent.bias
                if let event,let entryID {
                    var approach=entryID
                    while let ancestor=nodes[approach].parent,
                        observations[event.start].travel-observations[nodes[ancestor].observation].travel<=0.8 {
                        approach=ancestor
                    }
                    approachBias=nodes[approach].bias
                }
                let predicted = MapPoint(x:parent.point.x+cos(desired+parent.bias)*rawDistance*parent.factor*pixelsPerMeter,
                    y:parent.point.y+sin(desired+parent.bias)*rawDistance*parent.factor*pixelsPerMeter)
                let blocked = !map.grid.canTravel(parent.point,predicted)
                var changes = [0.0,-4,4,-12,12]
                if level != .conservative { changes += [-30,30] }
                if blocked {
                    if level == .conservative { changes += [-24,24] }
                    if level == .standard { changes += [-50,50,-75,75] }
                    if level == .flexible { changes += [-50,50,-75,75,-100,100,-135,135,-160,160] }
                }
                // User-specified initial direction stays fixed over the first 0.6m.
                if part == 0, o.travel <= 0.6 { changes = [0] }
                var factors = [parent.factor,parent.factor-0.06,parent.factor+0.06]
                if blocked { factors += [parent.factor-0.18] }
                if rawDistance < 0.005 { factors = [parent.factor]; changes = [0] }
                for degrees in changes {
                    let bias = wrap(parent.bias+degrees * .pi/180)
                    guard abs(bias) <= limit+1e-9 else { continue }
                    for factor in factors where level.factorRange.contains(factor) {
                        let q = MapPoint(x:parent.point.x+cos(desired+bias)*rawDistance*factor*pixelsPerMeter,
                            y:parent.point.y+sin(desired+bias)*rawDistance*factor*pixelsPerMeter)
                        visited += 1
                        if visited % 512 == 0, Task.isCancelled || Date() >= deadline { limited = true; break }
                        guard map.grid.canTravel(parent.point,q) else { continue }
                        let nextLength=parent.length+rawDistance*factor
                        if let policy=shapePolicy {
                            // Per-segment prefixes and arc-distance windows are hard limits, not score hints.
                            if o.travel>=2,abs(nextLength/o.travel-1)>policy.totalTolerance+1e-8 { continue }
                            let windowTravel=o.travel-observations[nodes[windowRoot].observation].travel
                            if windowTravel>=2,
                                abs((nextLength-nodes[windowRoot].length)/windowTravel-1)>policy.windowTolerance+1e-8 { continue }
                        }
                        let change = wrap(bias-parent.bias)
                        if entryID != nil,let policy=shapePolicy,
                            abs(wrap(bias-approachBias))>policy.excursionAngleDegrees * .pi/180+1e-8 { continue }
                        let angleWeight = level == .flexible ? 0.06 : 0.18
                        let distanceWeight = level == .flexible ? 0.10 : 0.25
                        let reference = distance(q,nominal)/pixelsPerMeter
                        // Registration-first trials cannot hide a bad global angle with a huge local warp.
                        if coherentOnly,reference>(level == .flexible ? 2.0 : 1.5) { continue }
                        // Reference is soft and weakens with traverse distance; it is not a clipping radius.
                        var cost = parent.cost + angleWeight*change*change + 0.006*bias*bias*rawDistance
                            + distanceWeight*pow(log(factor),2)*rawDistance + 0.12*pow(factor-parent.factor,2)
                            + 0.004*reference*reference*rawDistance/(1+o.travel/8)
                            + 0.005*map.wallCost(q,scale:pixelsPerMeter)*rawDistance
                        if let event,let entryID {
                            let entry=nodes[entryID],first=observations[event.start]
                            let theta=rotation+approachBias,x=o.point.x-first.point.x,y=o.point.y-first.point.y
                            let target=MapPoint(x:entry.point.x+(cos(theta)*x-sin(theta)*y)*pixelsPerMeter,
                                y:entry.point.y+(sin(theta)*x+cos(theta)*y)*pixelsPerMeter)
                            let error=distance(q,target)/pixelsPerMeter
                            // A local frame does not weaken merely because the overall recording is long.
                            if shapePolicy?.improved == true {
                                // Keep the lobe near a coherent local frame, not a collection of equally long knots.
                                guard error<=max(0.6,event.radius*0.25) else { continue }
                                cost += 1.5*error*error*rawDistance + 1.8*change*change
                            } else { cost += 0.35*error*error*rawDistance + 0.9*change*change }
                            if oi==event.end {
                                let eventLength=nextLength-entry.length
                                guard abs(eventLength/event.length-1)<=shapePolicy!.windowTolerance+1e-8,
                                    error<=1.0 else { continue }
                                cost += 25*error*error
                            }
                            if oi>event.end { cost += 0.5*pow(wrap(bias-approachBias),2)*rawDistance }
                        }
                        proposals.append(DeformationNode(point:q,bias:bias,factor:factor,cost:cost,
                            parent:id,observation:oi,part:part,length:nextLength,excursionRoot:entryID))
                    }
                }
                if limited { break }
            }
            if limited {
                unresolved.append(UnresolvedRouteRange(from:previous.index,through:input.count-1,reason:"V9 탐색 시간 한도")); break
            }
            proposals.sort { $0.cost < $1.cost }
            var keys = Set<DeformationKey>(), selected: [DeformationNode] = []
            for p in proposals {
                let entry=p.excursionRoot.map { nodes[$0].point }
                let key = DeformationKey(x:Int(p.point.x/positionBin),y:Int(p.point.y/positionBin),
                    direction:Int((p.bias + .pi)/(.pi/12)),factor:Int(p.factor/0.15),
                    entryX:entry.map { Int($0.x/(pixelsPerMeter*0.3)) } ?? 0,
                    entryY:entry.map { Int($0.y/(pixelsPerMeter*0.3)) } ?? 0)
                if keys.insert(key).inserted { selected.append(p) }
                if selected.count == level.beamSize { break }
            }
            if selected.isEmpty {
                if let end = beam.first { ends.append(end) }
                beam = []; failedSegment = true
                unresolved.append(UnresolvedRouteRange(from:previous.index,through:endOfSegment(oi,observations),
                    reason:shapePolicy == nil ? "V9 이동 가설 소진 · 방향/변형 수준/문·벽 지도 확인" : "\(shapePolicy?.improved == true ? "V13" : "V12") 거리/왕복/벽 조건 양립 불가 · 축척·입구·원본 확인"))
            } else {
                beam = []
                for p in selected { beam.append(nodes.count); nodes.append(p) }
            }
            if oi % 8 == 0 { progress(0.05+0.90*Double(oi)/Double(observations.count)) }
        }
        guard !Task.isCancelled else { return nil }
        var finalEnds = beam
        // Closure is only a soft hint when the observed segment itself returns near its start.
        if let last = observations.last {
            let first = observations.lastIndex(where:{ $0.restart }) ?? 0
            if last.travel > 3, distance(last.point,observations[first].point) < 0.6 {
                let root = first == 0 ? anchor : AnchoredMapMatcher.transformed(observations[first].point,
                    anchor:anchor,scale:pixelsPerMeter,rotation:rotationDegrees,factor:1)
                finalEnds.sort { nodes[$0].cost + 2*pow(distance(nodes[$0].point,root)/pixelsPerMeter,2)
                    < nodes[$1].cost + 2*pow(distance(nodes[$1].point,root)/pixelsPerMeter,2) }
            }
        }
        if finalEnds.isEmpty { finalEnds = ends.isEmpty ? [] : [ends.removeLast()] }
        guard !finalEnds.isEmpty else { return nil }
        var candidates: [MapMatchCandidate] = []
        for end in finalEnds {
            if var candidate = result(endpoints:ends+[end],nodes:nodes,observations:observations,input:input,
                anchor:anchor,scale:pixelsPerMeter,rotation:rotationDegrees,map:map,unresolved:unresolved,
                limited:limited,hypotheses:beam.count,shapePolicy:shapePolicy,excursions:excursions) {
                if let detection { candidate.routeShape?.detectionIncomplete=detection.limited }
                let duplicate = candidates.contains { other in
                    let pairs = zip(other.samplePoints,candidate.samplePoints).compactMap { a,b -> Double? in
                        guard let a, let b else { return nil }; return distance(a,b)/pixelsPerMeter
                    }
                    let wholeMean=pairs.isEmpty ? Double.infinity : pairs.reduce(0,+)/Double(pairs.count)
                    guard shapePolicy?.improved == true else { return wholeMean<0.25 }
                    let localMean=excursions.map { event -> Double in
                        let values=(observations[event.start].index...observations[event.end].index).compactMap { i -> Double? in
                            guard let a=other.samplePoints[i],let b=candidate.samplePoints[i] else { return nil }
                            return distance(a,b)/pixelsPerMeter
                        }
                        return values.isEmpty ? 0 : values.reduce(0,+)/Double(values.count)
                    }.max() ?? 0
                    return max(wholeMean,localMean)<0.25
                }
                if !duplicate { candidates.append(candidate) }
            }
            if candidates.count == 3 { break }
        }
        guard !candidates.isEmpty else { return nil }
        progress(1)
        var output = MapMatchResult(candidates:candidates,elapsedSeconds:Date().timeIntervalSince(began),
            searchIncomplete:limited,mapHash:mapHash,sourceRecordingID:recordingID,anchor:anchor,
            rotationDegrees:rotationDegrees,pixelsPerMeter:pixelsPerMeter)
        output.algorithm = "motion-state-nonrigid-beam-backtrack-v1"
        if shapePolicy != nil { output.algorithm=shapePolicy?.improved == true ? "whole-lobe-context-and-shape-envelope-v2" : "excursion-memory-and-arc-budget-beam-v1" }
        output.scaleRange = [level.factorRange.lowerBound,level.factorRange.upperBound]
        output.deformationLevel = level
        return output
    }

    nonisolated private static func endOfSegment(_ index: Int, _ observations: [DeformationObservation]) -> Int {
        let next = observations.indices.first(where:{ $0 > index && observations[$0].restart })
        return observations[(next ?? observations.count)-1].index
    }
    /// Shared diagnostic for comparing a legacy result on exactly the same original data.
    nonisolated static func assessShape(_ candidate:MapMatchCandidate,input:[MatchInput],scale:Double,
        policy:RouteShapePolicy = .make(.standard))->RouteShapeSummary {
        let observations=makeObservations(input)
        let detection=policy.improved ? findImprovedExcursions(observations) : nil
        var summary=shapeSummary(candidate,policy:policy,events:detection?.events ?? findExcursions(observations),observations:observations,input:input,scale:scale)
        if let detection { summary.detectionIncomplete=detection.limited }
        return summary
    }

    nonisolated private static func makeObservations(_ input: [MatchInput]) -> [DeformationObservation] {
        var total = 0.0
        for i in input.indices.dropFirst() {
            if input[i].segment == input[i-1].segment, let a = input[i-1].meters, let b = input[i].meters { total += distance(a,b) }
        }
        let spacing = max(0.30,total/1400)
        var output: [DeformationObservation] = [], previous: MapPoint?, segment: Int?, travel = 0.0, kept = 0.0
        for i in input.indices {
            guard let p = input[i].meters, p.x.isFinite, p.y.isFinite else { previous = nil; segment = nil; continue }
            let restart = previous == nil || segment != input[i].segment
            if restart { travel = 0; kept = 0 }
            else if let previous { travel += distance(previous,p) }
            var corner = false
            if i > 0, i+1 < input.count, let a = input[i-1].meters, let b = input[i+1].meters,
                input[i-1].segment == input[i].segment, input[i+1].segment == input[i].segment,
                distance(a,p) > 0.02, distance(p,b) > 0.02 {
                corner = abs(wrap(atan2(b.y-p.y,b.x-p.x)-atan2(p.y-a.y,p.x-a.x))) > .pi/6
            }
            let end = i+1 == input.count || input[i+1].meters == nil || input[i+1].segment != input[i].segment
            if restart || corner || end || travel-kept >= spacing {
                output.append(DeformationObservation(point:p,index:i,time:input[i].time,segment:input[i].segment,restart:restart,travel:travel))
                kept = travel
            }
            previous = p; segment = input[i].segment
        }
        return output
    }

    nonisolated private static func result(endpoints: [Int], nodes: [DeformationNode], observations: [DeformationObservation],
        input: [MatchInput], anchor: MapPoint, scale: Double, rotation: Double, map: MatchNavigationMap,
        unresolved: [UnresolvedRouteRange], limited: Bool, hypotheses: Int,
        shapePolicy: RouteShapePolicy?,excursions:[ExcursionObservation]) -> MapMatchCandidate? {
        var vertices: [MatchedRouteVertex] = [], samples = [MapPoint?](repeating:nil,count:input.count)
        var directions: [Double] = [], turnChanges: [Double] = [], factors: [Double] = [], score = 0.0, length = 0.0, rawLength = 0.0
        for end in endpoints {
            score += nodes[end].cost
            var chain: [Int] = [], cursor: Int? = end
            while let i = cursor { chain.append(i); cursor = nodes[i].parent }
            chain.reverse()
            for (position,id) in chain.enumerated() {
                let n = nodes[id], o = observations[n.observation]
                vertices.append(MatchedRouteVertex(point:n.point,time:o.time,sampleIndex:o.index,part:n.part))
                samples[o.index] = n.point
                if position > 0 {
                    let prev = nodes[chain[position-1]], po = observations[prev.observation]
                    guard map.grid.canTravel(prev.point,n.point) else { return nil }
                    let actual = distance(prev.point,n.point)/scale, observed = distance(po.point,o.point)
                    length += actual; rawLength += observed
                    if observed > 0.005 {
                        factors.append(actual/observed); directions.append(abs(n.bias)*180 / .pi)
                        turnChanges.append(abs(wrap(n.bias-prev.bias))*180 / .pi)
                    }
                    for i in po.index...o.index where input[i].meters != nil {
                        let fraction = o.time > po.time ? min(1,max(0,(input[i].time-po.time)/(o.time-po.time))) : 1
                        samples[i] = MapPoint(x:prev.point.x+(n.point.x-prev.point.x)*fraction,y:prev.point.y+(n.point.y-prev.point.y)*fraction)
                    }
                }
            }
        }
        guard vertices.first.map({ distance($0.point,anchor) < 1e-8 }) == true else { return nil }
        for v in vertices { guard map.grid.isFree(v.point) else { return nil } }
        let meanFactor = rawLength > 0 ? length/rawLength : 1
        var changes: [Double] = [], fullRawLength = 0.0
        for i in input.indices {
            if i > 0, input[i].segment == input[i-1].segment, let a = input[i-1].meters, let b = input[i].meters {
                fullRawLength += distance(a,b)
            }
            if let p = input[i].meters, let q = samples[i] {
                changes.append(distance(q,AnchoredMapMatcher.transformed(p,anchor:anchor,scale:scale,rotation:rotation,factor:1))/scale)
            }
        }
        let finalRaw = input.last?.meters.map { AnchoredMapMatcher.transformed($0,anchor:anchor,scale:scale,rotation:rotation,factor:1) }
        let shift = finalRaw.flatMap { p in samples.last.flatMap { $0 }.map { distance(p,$0)/scale } } ?? 0
        let completed = Double(samples.compactMap({ $0 }).count)/Double(max(1,input.compactMap(\.meters).count))
        let summary = RouteDeformationSummary(maxDirectionChangeDegrees:directions.max() ?? 0,
            maxTurnChangeDegrees:turnChanges.max() ?? 0,minimumStepFactor:factors.min() ?? 1,
            maximumStepFactor:factors.max() ?? 1,endpointShiftMeters:shift,
            largeDeformation:(directions.max() ?? 0) > 45 || (factors.min() ?? 1) < 0.75 || (factors.max() ?? 1) > 1.25,
            completedFraction:completed,retainedHypotheses:hypotheses)
        var candidate=MapMatchCandidate(scaleFactor:meanFactor,score:score/Double(max(1,vertices.count)) + 20*(1-completed),
            vertices:vertices,samplePoints:samples,unresolved:unresolved,maxLocalChangeMeters:changes.max() ?? 0,
            meanLocalChangeMeters:changes.reduce(0,+)/Double(max(1,changes.count)),inferredLengthMeters:length,
            scaledLengthMeters:fullRawLength*meanFactor,searchLimited:limited,deformation:summary)
        if let policy=shapePolicy {
            candidate.routeShape=shapeSummary(candidate,policy:policy,events:excursions,observations:observations,input:input,scale:scale)
            if let shape=candidate.routeShape,abs(shape.coveredLengthRatio-1)>policy.totalTolerance+1e-6 { return nil }
        }
        return candidate
    }

    private struct ExcursionObservation {
        let start:Int,end:Int,settle:Int
        let length:Double,radius:Double
    }
    /// Evaluate the whole local return cluster before selecting boundaries. A departure after returning
    /// may legitimately turn 90/180 degrees; continuation heading is not evidence against a visit.
    /// These are geometric lobes, never semantic room labels or a promise of entering a doorway.
    nonisolated private static func findImprovedExcursions(_ o:[DeformationObservation],deadline:Date?=nil)->(events:[ExcursionObservation],limited:Bool) {
        var candidates:[(event:ExcursionObservation,score:Double)]=[]
        var checks=0,limited=false
        scanning: for end in o.indices where end>=5 && end+1<o.count {
            if Task.isCancelled { return ([],false) }
            for start in (1..<end-3).reversed() {
                checks += 1
                if checks>1_000_000 || (checks % 256 == 0 && deadline.map{Date()>=$0} == true) {
                    limited=true;break scanning
                }
                if o[start].segment != o[end].segment || o[start].restart { break }
                let length=o[end].travel-o[start].travel
                if length>18 { break }
                guard length>=2.5,o[end].time-o[start].time>=1,
                    o[start-1].segment==o[start].segment,o[end+1].segment==o[end].segment,!o[end+1].restart else { continue }
                let gap=distance(o[start].point,o[end].point)
                guard gap<=0.8,gap/length<0.12 else { continue }
                checks += end-start
                if checks>1_000_000 || deadline.map({Date()>=$0}) == true { limited=true;break scanning }
                let radius=o[start...end].map { distance($0.point,o[start].point) }.max() ?? 0
                guard radius>=0.9,length>=radius*1.8 else { continue }
                var settle=end
                while settle+1<o.count,o[settle+1].segment==o[end].segment,!o[settle+1].restart,
                    o[settle+1].travel-o[end].travel<=1.2 { settle += 1 }
                guard settle>end else { continue }
                // Prefer a close full return rather than the first partial contact with the incoming leg.
                let score=gap/max(0.9,radius)+0.002*length
                candidates.append((ExcursionObservation(start:start,end:end,settle:settle,length:length,radius:radius),score))
                if candidates.count>=20_000 { limited=true;break scanning }
            }
        }
        candidates.sort { abs($0.score-$1.score)>1e-9 ? $0.score<$1.score : $0.event.start<$1.event.start }
        var chosen:[ExcursionObservation]=[]
        for c in candidates {
            if !chosen.contains(where:{c.event.start<=$0.settle && c.event.settle>=$0.start}) {
                chosen.append(c.event)
                if chosen.count==128 { break }
            }
        }
        return (chosen.sorted { $0.start<$1.start },limited)
    }
    /// Geometric excursion hypotheses only; no claim that the destination is a semantic room.
    nonisolated private static func findExcursions(_ o:[DeformationObservation])->[ExcursionObservation] {
        var result:[ExcursionObservation]=[],available=1
        for end in o.indices where end>=available+4 {
            if Task.isCancelled { return [] }
            var best:ExcursionObservation?,bestScore=Double.infinity
            for start in (available..<end-3).reversed() {
                if o[start].segment != o[end].segment || o[start].restart && start>available { break }
                let length=o[end].travel-o[start].travel
                if length>18 { break }
                guard length>=2.5,!o[start...end].contains(where:{$0.restart}),
                    o[end].time-o[start].time>=1 else { continue }
                let gap=distance(o[start].point,o[end].point)
                guard gap<=0.65,gap/length<0.18 else { continue }
                let radius=o[start...end].map { distance($0.point,o[start].point) }.max() ?? 0
                guard radius>=0.9,length>=radius*1.8 else { continue }
                // Prefer excursions with continued travel on either side, not a final return to start.
                guard start>0,end+1<o.count,o[start-1].segment==o[end].segment,o[end+1].segment==o[end].segment,
                    !o[end+1].restart else { continue }
                var settle=end
                while settle+1<o.count,!o[settle+1].restart,o[settle+1].travel-o[end].travel<=1.2 { settle += 1 }
                let before=atan2(o[start].point.y-o[start-1].point.y,o[start].point.x-o[start-1].point.x)
                let after=atan2(o[settle].point.y-o[end].point.y,o[settle].point.x-o[end].point.x)
                guard settle>end,abs(wrap(after-before))<Double.pi/3 else { continue }
                let score=gap+0.03*length
                if score<bestScore { bestScore=score;best=ExcursionObservation(start:start,end:end,settle:settle,length:length,radius:radius) }
            }
            if let best { result.append(best);available=best.settle+1 }
            if result.count>=128 { break }
        }
        return result
    }
    nonisolated private static func shapeSummary(_ c:MapMatchCandidate,policy:RouteShapePolicy,
        events:[ExcursionObservation],observations:[DeformationObservation],input:[MatchInput],scale:Double)->RouteShapeSummary {
        var covered=0.0
        for i in input.indices.dropFirst() where input[i].segment==input[i-1].segment {
            if c.samplePoints[i] != nil,c.samplePoints[i-1] != nil,let a=input[i-1].meters,let b=input[i].meters { covered += distance(a,b) }
        }
        var fits:[RouteExcursionFit]=[],penalty=0.0
        for event in events {
            let a=observations[event.start],b=observations[event.end]
            guard let start=c.samplePoints[a.index],let end=c.samplePoints[b.index] else { continue }
            let observedRadius=event.radius
            let peak=(event.start...event.end).max { distance(observations[$0].point,a.point)<distance(observations[$1].point,a.point) }!
            guard let p=c.samplePoints[observations[peak].index] else { continue }
            let theta=atan2(p.y-start.y,p.x-start.x)-atan2(observations[peak].point.y-a.point.y,observations[peak].point.x-a.point.x)
            var sq=0.0,count=0,length=0.0
            for oi in event.start...event.end {
                let o=observations[oi]
                if let q=c.samplePoints[o.index] {
                    let x=o.point.x-a.point.x,y=o.point.y-a.point.y
                    let target=MapPoint(x:start.x+(cos(theta)*x-sin(theta)*y)*scale,y:start.y+(sin(theta)*x+cos(theta)*y)*scale)
                    sq += pow(distance(q,target)/scale,2);count += 1
                    if oi>event.start,let prev=c.samplePoints[observations[oi-1].index] { length += distance(q,prev)/scale }
                }
            }
            let x=b.point.x-a.point.x,y=b.point.y-a.point.y
            let target=MapPoint(x:start.x+(cos(theta)*x-sin(theta)*y)*scale,y:start.y+(sin(theta)*x+cos(theta)*y)*scale)
            let error=distance(end,target)/scale,rms=sqrt(sq/Double(max(1,count))),ratio=length/event.length
            penalty += 2*error*error+0.6*rms*rms+pow(log(max(0.01,ratio)),2)
                + max(0,0.6-distance(p,start)/scale/max(0.01,observedRadius))
            fits.append(RouteExcursionFit(from:a.index,through:b.index,returnErrorMeters:error,lengthRatio:ratio,shapeRMSErrorMeters:rms))
        }
        var windowRatios:[Double]=[]
        for i in c.vertices.indices {
            var j=i,raw=0.0,actual=0.0
            while j>0,c.vertices[j-1].part==c.vertices[i].part {
                let a=c.vertices[j-1],b=c.vertices[j]
                var nextRaw=0.0
                for k in (a.sampleIndex+1)...b.sampleIndex {
                    if let p=input[k-1].meters,let q=input[k].meters { nextRaw += distance(p,q) }
                }
                // Same <=3.3m ancestor window used while proposing states, including the current step.
                if raw+nextRaw>policy.windowMeters+0.3 { break }
                raw += nextRaw;actual += distance(a.point,b.point)/scale;j -= 1
            }
            if raw>=2 { windowRatios.append(actual/raw) }
        }
        return RouteShapeSummary(policy:policy,excursions:events.map { RouteExcursion(from:observations[$0.start].index,
            through:observations[$0.end].index,lengthMeters:$0.length,radiusMeters:$0.radius) },fittedExcursions:fits,
            coveredLengthRatio:covered>0 ? c.inferredLengthMeters/covered : 1,minimumWindowRatio:windowRatios.min() ?? 1,maximumWindowRatio:windowRatios.max() ?? 1,
            qualityPenalty:penalty/Double(max(1,fits.count)))
    }
}
