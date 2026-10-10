import Foundation

nonisolated struct MatchInput: Codable, Sendable {
    let meters: MapPoint?
    let time: Double
    let segment: Int
}
nonisolated struct MatchedRouteVertex: Codable, Sendable {
    let point: MapPoint
    let time: Double
    let sampleIndex: Int
    let part: Int
}
nonisolated struct UnresolvedRouteRange: Codable, Sendable {
    let from: Int
    let through: Int
    let reason: String
}
nonisolated struct MapMatchCandidate: Codable, Sendable {
    let scaleFactor: Double
    let score: Double
    let vertices: [MatchedRouteVertex]
    let samplePoints: [MapPoint?]
    let unresolved: [UnresolvedRouteRange]
    let maxLocalChangeMeters: Double
    let meanLocalChangeMeters: Double
    let inferredLengthMeters: Double
    let scaledLengthMeters: Double
    let searchLimited: Bool
    var deformation: RouteDeformationSummary? = nil
    var initialHeading: InitialHeadingFit? = nil
    var routeShape: RouteShapeSummary? = nil
}
nonisolated struct MapMatchResult: Codable, Sendable {
    var algorithm = "anchored-grid-sequence-v1"
    let candidates: [MapMatchCandidate]
    var selected = 0
    let elapsedSeconds: Double
    let searchIncomplete: Bool
    let mapHash: String
    let sourceRecordingID: String
    let anchor: MapPoint
    let rotationDegrees: Double
    let pixelsPerMeter: Double
    var scaleRange = [0.70, 1.15]
    var deformationLevel: DeformationLevel? = nil
    var initialHeadingSearch: InitialHeadingSearchSummary? = nil
    nonisolated var chosen: MapMatchCandidate? { candidates.indices.contains(selected) ? candidates[selected] : nil }
}

nonisolated struct MatchNavigationMap: Sendable {
    let grid: RouteObstacleGrid
    let clearance: [UInt16]

    nonisolated init(grid: RouteObstacleGrid, normalizedOutline: [MapPoint]? = nil) {
        var mask = grid.blocked
        if let polygon = normalizedOutline, polygon.count >= 3 {
            for y in 0..<grid.rows { for x in 0..<grid.columns {
                let p = MapPoint(x: (Double(x)+0.5)/Double(grid.columns), y: (Double(y)+0.5)/Double(grid.rows))
                if !Self.inside(p, polygon) { mask[y*grid.columns+x] = 1 }
            } }
        }
        self.grid = RouteObstacleGrid(columns: grid.columns, rows: grid.rows, cellSize: grid.cellSize,
            blocked: mask, minX: grid.minX, maxX: grid.maxX, minY: grid.minY, maxY: grid.maxY)
        var d = mask.map { $0 == 1 ? UInt16(0) : UInt16(16000) }
        for y in 0..<grid.rows { for x in 0..<grid.columns {
            let i = y*grid.columns+x
            if x > 0 { d[i] = min(d[i], d[i-1]+1) }
            if y > 0 { d[i] = min(d[i], d[i-grid.columns]+1) }
        } }
        for y in (0..<grid.rows).reversed() { for x in (0..<grid.columns).reversed() {
            let i = y*grid.columns+x
            if x+1 < grid.columns { d[i] = min(d[i], d[i+1]+1) }
            if y+1 < grid.rows { d[i] = min(d[i], d[i+grid.columns]+1) }
        } }
        clearance = d
    }
    nonisolated private static func inside(_ p: MapPoint, _ polygon: [MapPoint]) -> Bool {
        var contained = false, j = polygon.count-1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x { contained.toggle() }
            j = i
        }
        return contained
    }
    nonisolated func wallCost(_ p: MapPoint, scale: Double) -> Double {
        guard grid.isFree(p) else { return 100 }
        let x = Int(p.x/grid.cellSize), y = Int(p.y/grid.cellSize)
        let meters = Double(clearance[y*grid.columns+x])*grid.cellSize/scale
        return max(0, 0.18-meters) / 0.18
    }
}

private nonisolated struct MatchObservation { let point: MapPoint; let index: Int; let segment: Int; let travel: Double }
private nonisolated struct MatchNode {
    let point: MapPoint
    let direction: Double?
    let cost: Double
    let parent: Int?
    let connector: [MapPoint]
    let observation: Int
    let part: Int
}
private nonisolated struct SearchEntry: Sendable { let cell: Int; let cost: Double; let priority: Double }
private nonisolated struct SearchHeap: Sendable {
    var items: [SearchEntry] = []
    nonisolated init() {}
    nonisolated mutating func push(_ value: SearchEntry) {
        items.append(value); var i = items.count-1
        while i > 0 {
            let p = (i-1)/2
            if items[p].priority <= items[i].priority { break }
            items.swapAt(p,i); i = p
        }
    }
    nonisolated mutating func pop() -> SearchEntry? {
        guard !items.isEmpty else { return nil }
        if items.count == 1 { return items.removeLast() }
        let first = items[0]; items[0] = items.removeLast(); var i = 0
        while 2*i+1 < items.count {
            var c = 2*i+1
            if c+1 < items.count, items[c+1].priority < items[c].priority { c += 1 }
            if items[i].priority <= items[c].priority { break }
            items.swapAt(i,c); i = c
        }
        return first
    }
}

nonisolated enum AnchoredMapMatcher {
    nonisolated private static func distance(_ a: MapPoint, _ b: MapPoint) -> Double { hypot(b.x-a.x,b.y-a.y) }
    nonisolated private static func angleDifference(_ a: Double, _ b: Double) -> Double { atan2(sin(a-b),cos(a-b)) }
    nonisolated private static func heading(_ a: MapPoint, _ b: MapPoint) -> Double { atan2(b.y-a.y,b.x-a.x) }

    nonisolated static func transformed(_ p: MapPoint, anchor: MapPoint, scale: Double, rotation: Double, factor: Double) -> MapPoint {
        let r = rotation * .pi/180
        return MapPoint(x: anchor.x + scale*factor*(cos(r)*p.x-sin(r)*p.y),
                        y: anchor.y + scale*factor*(sin(r)*p.x+cos(r)*p.y))
    }

    nonisolated static func match(input: [MatchInput], anchor: MapPoint, pixelsPerMeter: Double,
                                 rotationDegrees: Double, map: MatchNavigationMap, mapHash: String,
                                 recordingID: String, budgetSeconds: Double = 15,
                                 progress: @Sendable (Double) -> Void = { _ in }) -> MapMatchResult? {
        guard pixelsPerMeter.isFinite, pixelsPerMeter > 0, rotationDegrees.isFinite,
              input.count >= 2, map.grid.isFree(anchor) else { return nil }
        let began = Date(), deadline = began.addingTimeInterval(budgetSeconds)
        let observations = buildObservations(input)
        guard observations.count >= 2 else { return nil }
        // Keep several scale candidates: cheap wall fit does not decide the final route.
        let coarse = (0...18).map { 0.70+Double($0)*0.025 }
        let scored = coarse.map { factor -> (Double,Double) in
            var penalty = 0.0
            for o in observations {
                let p = transformed(o.point,anchor:anchor,scale:pixelsPerMeter,rotation:rotationDegrees,factor:factor)
                if !map.grid.isFree(p) { penalty += 1 }
            }
            return (factor, penalty/Double(observations.count) + 0.4*pow(log(factor),2))
        }.sorted { $0.1 < $1.1 }
        var factors = Array(scored.prefix(4).map(\.0))
        if !factors.contains(where: { abs($0-1) < 1e-6 }) { factors.append(1) }
        var results: [MapMatchCandidate] = []
        progress(0.08)
        for (i,factor) in factors.enumerated() {
            if Task.isCancelled { return nil }
            if Date() >= deadline { break }
            if let candidate = solve(observations: observations, input: input, anchor: anchor,
                    scale: pixelsPerMeter, rotation: rotationDegrees, factor: factor, map: map, deadline: deadline) {
                results.append(candidate)
            }
            progress(0.1 + 0.65*Double(i+1)/Double(factors.count))
        }
        if let winner = results.min(by: { $0.score < $1.score }), Date() < deadline {
            factors = [-0.01,-0.005,0.005,0.01].map { winner.scaleFactor+$0 }.filter { $0 >= 0.70 && $0 <= 1.15 }
            for factor in factors {
                if Task.isCancelled { return nil }
                if Date() >= deadline { break }
                if let candidate = solve(observations: observations, input: input, anchor: anchor,
                        scale: pixelsPerMeter, rotation: rotationDegrees, factor: factor, map: map, deadline: deadline) { results.append(candidate) }
            }
        }
        if let winner = results.min(by:{ $0.score < $1.score }) {
            for rank in 1...2 where Date() < deadline {
                if Task.isCancelled { return nil }
                if let alternative = solve(observations:observations,input:input,anchor:anchor,scale:pixelsPerMeter,
                    rotation:rotationDegrees,factor:winner.scaleFactor,map:map,deadline:deadline,endRank:rank) { results.append(alternative) }
            }
        }
        guard !Task.isCancelled, !results.isEmpty else { return nil }
        results.sort { $0.score < $1.score }
        // Collapse duplicate routes; different scale alone is not a useful alternative.
        var distinct: [MapMatchCandidate] = []
        for candidate in results {
            let duplicate = distinct.contains { other in
                var sum = 0.0, count = 0
                for i in input.indices {
                    if let a = candidate.samplePoints[i], let b = other.samplePoints[i] { sum += distance(a,b)/pixelsPerMeter; count += 1 }
                }
                return count > 0 && sum/Double(count) < 0.20 && candidate.unresolved.count == other.unresolved.count
            }
            if !duplicate { distinct.append(candidate) }
            if distinct.count == 3 { break }
        }
        progress(1)
        return MapMatchResult(candidates: distinct, elapsedSeconds: Date().timeIntervalSince(began),
            searchIncomplete: Date() >= deadline || distinct.contains(where:{ $0.searchLimited || $0.unresolved.contains(where:{ $0.reason == "계산 시간 한도" }) }), mapHash: mapHash, sourceRecordingID: recordingID,
            anchor: anchor, rotationDegrees: rotationDegrees, pixelsPerMeter: pixelsPerMeter)
    }

    nonisolated private static func buildObservations(_ input: [MatchInput]) -> [MatchObservation] {
        var total = 0.0
        for i in input.indices.dropFirst() {
            if let a = input[i-1].meters, let b = input[i].meters, input[i-1].segment == input[i].segment { total += distance(a,b) }
        }
        let spacing = max(0.40,total/1800)
        var result: [MatchObservation] = [], last: MapPoint?, previousSegment: Int?, traveled = 0.0, lastKeptTravel = 0.0
        for i in input.indices {
            guard let p = input[i].meters, p.x.isFinite, p.y.isFinite else { last = nil; previousSegment = nil; continue }
            let newSegment = previousSegment != input[i].segment || last == nil
            if newSegment { traveled = 0; lastKeptTravel = 0 }
            else if let last { traveled += distance(last,p) }
            var corner = false
            if i > 0, i+1 < input.count, let a = input[i-1].meters, let b = input[i+1].meters,
               input[i-1].segment == input[i].segment, input[i+1].segment == input[i].segment,
               distance(a,p) > 0.03, distance(p,b) > 0.03 {
                corner = abs(angleDifference(heading(a,p),heading(p,b))) > .pi/4
            }
            let end = i+1 == input.count || input[i+1].meters == nil || input[i+1].segment != input[i].segment
            if newSegment || end || corner || traveled-lastKeptTravel >= spacing {
                result.append(MatchObservation(point:p,index:i,segment:input[i].segment,travel:traveled)); lastKeptTravel = traveled
            }
            last = p; previousSegment = input[i].segment
        }
        return result
    }

    nonisolated private static func candidates(near p: MapPoint, scale: Double, map: MatchNavigationMap) -> [MapPoint] {
        var points: [MapPoint] = [], seen = Set<Int>()
        for radius in [0.0,0.25,0.5,1.0,1.5,2.0] {
            for direction in 0..<(radius == 0 ? 1 : 16) {
                let angle = Double(direction) * .pi / 8
                let q = MapPoint(x:p.x+cos(angle)*radius*scale,y:p.y+sin(angle)*radius*scale)
                guard map.grid.isFree(q) else { continue }
                let key = Int(q.y/map.grid.cellSize)*map.grid.columns+Int(q.x/map.grid.cellSize)
                if seen.insert(key).inserted { points.append(q) }
            }
        }
        points.sort { distance($0,p)/scale + 0.08*map.wallCost($0,scale:scale) < distance($1,p)/scale + 0.08*map.wallCost($1,scale:scale) }
        // Spatial bins preserve alternatives on both sides of a nearby wall.
        var result: [MapPoint] = [], bins = Set<Int>()
        for q in points {
            let bin = Int((heading(p,q) + .pi) * 4 / .pi) % 8
            if bins.insert(bin).inserted { result.append(q) }
        }
        bins = []
        for q in points.reversed() {
            let bin = Int((heading(p,q) + .pi) * 4 / .pi) % 8
            if bins.insert(bin).inserted, !result.contains(where:{ distance($0,q) < 0.01 }) { result.append(q) }
        }
        return result
    }

    nonisolated private static func solve(observations: [MatchObservation], input: [MatchInput], anchor: MapPoint,
                                          scale: Double, rotation: Double, factor: Double,
                                          map: MatchNavigationMap, deadline: Date, endRank: Int = 0) -> MapMatchCandidate? {
        var nodes: [MatchNode] = [], beam: [Int] = [], endpoints: [Int] = [], missing: [UnresolvedRouteRange] = []
        var part = 0, lastObservation: MatchObservation?, searchLimited = false
        var pathCache: [String:[MapPoint]] = [:]
        for (oi,o) in observations.enumerated() {
            if Task.isCancelled { return nil }
            if Date() >= deadline {
                missing.append(UnresolvedRouteRange(from:o.index,through:input.count-1,reason:"계산 시간 한도")); break
            }
            let target = transformed(o.point,anchor:anchor,scale:scale,rotation:rotation,factor:factor)
            let continuous = lastObservation.map { $0.segment == o.segment && $0.index < o.index &&
                !input[($0.index+1)...o.index].contains(where: { $0.meters == nil }) } ?? false
            if !continuous, !beam.isEmpty { endpoints.append(beam[0]); beam = []; part += 1 }
            var options = candidates(near:target,scale:scale,map:map)
            if oi == 0 { options = [anchor] }
            var layer: [MatchNode] = []
            let expected = continuous ? max(0.02,(o.travel-(lastObservation?.travel ?? 0))*factor) : 0
            let oldTarget = lastObservation.map { transformed($0.point,anchor:anchor,scale:scale,rotation:rotation,factor:factor) } ?? target
            let desiredHeading = heading(oldTarget,target)
            for q in options {
                let change = distance(q,target)/scale
                let nodeCost = 0.6*change*change + 0.025*map.wallCost(q,scale:scale)
                if beam.isEmpty {
                    layer.append(MatchNode(point:q,direction:nil,cost:nodeCost,parent:nil,connector:[q],observation:oi,part:part))
                    continue
                }
                var arrivalOptions: [Int:MatchNode] = [:]
                for previousID in beam {
                    let previous = nodes[previousID]
                    let directMeters = distance(previous.point,q)/scale
                    if directMeters > expected + 2.5 { continue }
                    let key = "\(previousID):\(Int(q.x/map.grid.cellSize)):\(Int(q.y/map.grid.cellSize))"
                    let connection: [MapPoint]?
                    if let cached = pathCache[key] { connection = cached }
                    else {
                        connection = path(from:previous.point,to:q,map:map,scale:scale,
                            maximumMeters:expected+2.5,deadline:deadline,onLimit:{ searchLimited = true })
                        if let connection { pathCache[key] = connection }
                    }
                    guard let connection else { continue }
                    var length = 0.0, extraTurns = 0.0, initial: Double?, final: Double?
                    for i in connection.indices.dropFirst() where distance(connection[i-1],connection[i]) > 0.001 {
                        let h = heading(connection[i-1],connection[i]); if initial == nil { initial = h }
                        if let final { extraTurns += abs(angleDifference(h,final)) }
                        final = h; length += distance(connection[i-1],connection[i])/scale
                    }
                    let h = initial ?? previous.direction ?? desiredHeading
                    var penalty = 1.3*pow(length-expected,2) + 0.35*pow(angleDifference(h,desiredHeading),2) + 0.08*extraTurns
                    if let prevDirection = previous.direction, oi >= 2 {
                        let a = observations[oi-2], b = observations[oi-1]
                        if a.segment == b.segment && b.segment == o.segment {
                            let ar = transformed(a.point,anchor:anchor,scale:scale,rotation:rotation,factor:factor)
                            let wantedTurn = angleDifference(desiredHeading,heading(ar,oldTarget))
                            penalty += 0.25*pow(angleDifference(angleDifference(h,prevDirection),wantedTurn),2)
                        }
                    }
                    let trial = MatchNode(point:q,direction:final ?? previous.direction,cost:previous.cost+nodeCost+penalty,
                        parent:previousID,connector:connection,observation:oi,part:part)
                    let directionBin = Int(((trial.direction ?? 0) + .pi) * 4 / .pi) % 8
                    if arrivalOptions[directionBin] == nil || trial.cost < arrivalOptions[directionBin]!.cost {
                        arrivalOptions[directionBin] = trial
                    }
                }
                layer.append(contentsOf:arrivalOptions.values.sorted { $0.cost < $1.cost }.prefix(2))
            }
            if layer.isEmpty {
                if !beam.isEmpty { endpoints.append(beam[0]); beam = []; part += 1 }
                missing.append(UnresolvedRouteRange(from:lastObservation?.index ?? o.index,through:o.index,
                    reason:searchLimited ? "탐색 한도 · 연결 찾지 못함" : "연결 찾지 못함 · 시작점/방향/지도/탐색 범위 확인"))
                lastObservation = o; continue
            }
            // A restart after failure is not claimed to be connected to the anchored prefix.
            if beam.isEmpty, oi > 0 {
                missing.append(UnresolvedRouteRange(from:o.index,through:o.index,reason:"이후 구간 연결 미확인"))
            }
            layer.sort { $0.cost < $1.cost }
            beam = []
            for node in layer.prefix(8) { beam.append(nodes.count); nodes.append(node) }
            lastObservation = o
            if pathCache.count > 2000 { pathCache.removeAll(keepingCapacity:true) }
        }
        if !beam.isEmpty { endpoints.append(beam[min(endRank,beam.count-1)]) }
        guard !endpoints.isEmpty else { return nil }
        var vertices: [MatchedRouteVertex] = [], samples = [MapPoint?](repeating:nil,count:input.count)
        var score = 0.0, changes = [Double](), routeLength = 0.0
        for end in endpoints {
            score += nodes[end].cost
            var chain: [Int] = [], cursor: Int? = end
            while let id = cursor { chain.append(id); cursor = nodes[id].parent }
            chain.reverse()
            for (position,id) in chain.enumerated() {
                let node = nodes[id], o = observations[node.observation]
                let previousNode = position > 0 ? nodes[chain[position-1]] : nil
                let fromIndex = previousNode.map { observations[$0.observation].index } ?? o.index
                let startTime = input[fromIndex].time, endTime = input[o.index].time
                var lengths = [0.0]
                for i in node.connector.indices.dropFirst() { lengths.append(lengths.last! + distance(node.connector[i-1],node.connector[i])) }
                let total = lengths.last ?? 0
                for i in node.connector.indices {
                    let t = total > 0 ? lengths[i]/total : 1
                    vertices.append(MatchedRouteVertex(point:node.connector[i],time:startTime+(endTime-startTime)*t,sampleIndex:o.index,part:node.part))
                }
                routeLength += total/scale
                for i in fromIndex...o.index where input[i].meters != nil {
                    let t = endTime > startTime ? min(1,max(0,(input[i].time-startTime)/(endTime-startTime))) : 1
                    samples[i] = interpolatePath(node.connector,lengths:lengths,fraction:t)
                }
                let target = transformed(o.point,anchor:anchor,scale:scale,rotation:rotation,factor:factor)
                changes.append(distance(node.point,target)/scale)
            }
        }
        for v in vertices { guard map.grid.isFree(v.point) else { return nil } }
        for i in vertices.indices.dropFirst() where vertices[i-1].part == vertices[i].part {
            guard map.grid.canTravel(vertices[i-1].point,vertices[i].point) else { return nil }
        }
        changes = []
        for i in input.indices {
            if let raw = input[i].meters, let corrected = samples[i] {
                changes.append(distance(corrected,transformed(raw,anchor:anchor,scale:scale,rotation:rotation,factor:factor))/scale)
            }
        }
        let missingWeight = Double(missing.reduce(0) { $0+max(1,$1.through-$1.from) })/Double(max(1,input.count))
        var totalObserved = 0.0
        for i in observations.indices.dropFirst() where observations[i-1].segment == observations[i].segment {
            totalObserved += max(0,observations[i].travel-observations[i-1].travel)
        }
        return MapMatchCandidate(scaleFactor:factor,
            score:score/Double(max(1,observations.count)) + 0.8*pow(log(factor),2) + 20*missingWeight,
            vertices:vertices,samplePoints:samples,unresolved:missing,
            maxLocalChangeMeters:changes.max() ?? 0, meanLocalChangeMeters:changes.reduce(0,+)/Double(max(1,changes.count)),
            inferredLengthMeters:routeLength,scaledLengthMeters:totalObserved*factor,searchLimited:searchLimited)
    }

    nonisolated private static func interpolatePath(_ path: [MapPoint], lengths: [Double], fraction: Double) -> MapPoint? {
        guard let first = path.first, let last = path.last else { return nil }
        let target = (lengths.last ?? 0)*fraction
        for i in path.indices.dropFirst() where lengths[i] >= target {
            let span = lengths[i]-lengths[i-1], t = span > 0 ? (target-lengths[i-1])/span : 0
            return MapPoint(x:path[i-1].x+(path[i].x-path[i-1].x)*t,y:path[i-1].y+(path[i].y-path[i-1].y)*t)
        }
        return fraction <= 0 ? first : last
    }

    nonisolated static func path(from a: MapPoint, to b: MapPoint, map: MatchNavigationMap,
                                 scale: Double, maximumMeters: Double, deadline: Date, onLimit: () -> Void = {}) -> [MapPoint]? {
        let grid = map.grid
        guard grid.isFree(a), grid.isFree(b) else { return nil }
        if grid.canTravel(a,b) { return [a,b] }
        let ax = Int(a.x/grid.cellSize), ay = Int(a.y/grid.cellSize)
        let bx = Int(b.x/grid.cellSize), by = Int(b.y/grid.cellSize)
        let start = ay*grid.columns+ax, goal = by*grid.columns+bx
        func center(_ cell: Int) -> MapPoint { MapPoint(x:(Double(cell%grid.columns)+0.5)*grid.cellSize,y:(Double(cell/grid.columns)+0.5)*grid.cellSize) }
        guard grid.canTravel(a,center(start)), grid.canTravel(center(goal),b) else { return nil }
        var heap = SearchHeap(), costs = [start:0.0], parents: [Int:Int] = [:], visits = 0
        heap.push(SearchEntry(cell:start,cost:0,priority:distance(a,b)))
        let radius = Int(ceil((maximumMeters*scale)/grid.cellSize))
        let minX = max(0,min(ax,bx)-radius), maxX = min(grid.columns-1,max(ax,bx)+radius)
        let minY = max(0,min(ay,by)-radius), maxY = min(grid.rows-1,max(ay,by)+radius)
        while let item = heap.pop() {
            visits += 1
            if visits > 2500 { onLimit(); return nil }
            if visits % 64 == 0 && (Task.isCancelled || Date() >= deadline) { onLimit(); return nil }
            if item.cost > (costs[item.cell] ?? .infinity)+1e-9 { continue }
            if item.cell == goal {
                var cells = [goal], cursor = goal
                while cursor != start { guard let parent = parents[cursor] else { return nil }; cells.append(parent); cursor = parent }
                let full = [a] + cells.reversed().map(center) + [b]
                // Visibility reduction preserves the actual door detour vertices.
                var reduced = [a], i = 0
                while i+1 < full.count {
                    var j = min(full.count-1,i+16)
                    while j > i+1 && !grid.canTravel(full[i],full[j]) { j -= 1 }
                    reduced.append(full[j]); i = j
                }
                return reduced
            }
            let x = item.cell%grid.columns, y = item.cell/grid.columns
            for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                let nx = x+dx, ny = y+dy
                guard nx >= minX, nx <= maxX, ny >= minY, ny <= maxY else { continue }
                let next = ny*grid.columns+nx
                guard grid.blocked[next] == 0,
                      grid.canTravel(center(item.cell),center(next)) else { continue }
                let step = grid.cellSize*(dx == 0 || dy == 0 ? 1 : sqrt(2))
                let trial = item.cost+step*(1+0.10*map.wallCost(center(next),scale:scale))
                guard trial/scale <= maximumMeters, trial < (costs[next] ?? .infinity) else { continue }
                costs[next] = trial; parents[next] = item.cell
                heap.push(SearchEntry(cell:next,cost:trial,priority:trial+distance(center(next),b)))
            } }
        }
        return nil
    }
}
