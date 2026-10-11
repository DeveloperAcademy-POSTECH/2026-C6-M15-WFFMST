import Foundation

nonisolated struct InitialHeadingFit: Codable, Sendable {
    let rotationDegrees: Double
    let offsetDegrees: Double
    let distanceCoverage: Double
    let coveredLengthRatio: Double
    let localPositionChangeMeters: Double
    let objective: Double
}
nonisolated struct InitialHeadingSearchSummary: Codable, Sendable {
    let baselineRotationDegrees: Double
    let searchHalfRangeDegrees: Double
    let evaluatedRotations: Int
    let originalLengthMeters: Double
    let ambiguous: Bool
    let reachedBoundary: Bool
    let baselineDistanceCoverage: Double
    var registrationFirst: Bool? = nil
}

/// V11: a bounded outer search of constant registration yaw, followed by the unchanged V9 matcher.
/// Input orientation remains a prior; it is never overwritten by a candidate.
nonisolated enum InitialHeadingMatcher {
    nonisolated static func normalized(_ angle: Double) -> Double { (angle.truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360) }
    nonisolated static func delta(_ a:Double,_ b:Double) -> Double { atan2(sin((a-b) * .pi/180),cos((a-b) * .pi/180))*180 / .pi }
    nonisolated static func match(input:[MatchInput],anchor:MapPoint,pixelsPerMeter:Double,
        rotationDegrees:Double,map:MatchNavigationMap,mapHash:String,recordingID:String,
        level:DeformationLevel = .standard,budgetSeconds:Double = 20,
        preserveExcursions:Bool = false,
        improvedExcursions:Bool = false,
        progress:@Sendable (Double)->Void = {_ in}) -> MapMatchResult? {
        guard input.count>1,rotationDegrees.isFinite,pixelsPerMeter.isFinite,pixelsPerMeter>0,
              budgetSeconds>0,map.grid.isFree(anchor) else { return nil }
        let start=Date(),deadline=start.addingTimeInterval(budgetSeconds),halfRange=60.0
        let baseline=normalized(rotationDegrees)
        var total=0.0
        for i in input.indices.dropFirst() {
            if input[i].segment==input[i-1].segment,let a=input[i-1].meters,let b=input[i].meters {
                total += hypot(b.x-a.x,b.y-a.y)
            }
        }
        guard total.isFinite,total>0.01 else { return nil }
        struct Trial { let candidate:MapMatchCandidate; let fit:InitialHeadingFit }
        var retained:[Trial]=[],evaluated=Set<Int>(),tested:[InitialHeadingFit]=[]
        var baselineTrial:Trial?,limited=false,evaluationCount=0
        var resultTemplate:MapMatchResult?
        func rank(_ a:Trial,_ b:Trial)->Bool {
            if abs(a.fit.objective-b.fit.objective)>1e-9 { return a.fit.objective<b.fit.objective }
            return abs(a.fit.offsetDegrees)<abs(b.fit.offsetDegrees)
        }
        func routeDifference(_ a:MapMatchCandidate,_ b:MapMatchCandidate)->Double {
            let pairs=zip(a.samplePoints,b.samplePoints).compactMap { a,b -> Double? in
                guard let a,let b else { return nil };return hypot(a.x-b.x,a.y-b.y)/pixelsPerMeter
            }
            let mean=pairs.isEmpty ? Double.infinity : pairs.reduce(0,+)/Double(pairs.count)
            guard improvedExcursions,let events=a.routeShape?.excursions else { return mean }
            // A different short visit must not disappear in the mean of a long recording.
            return events.reduce(mean) { difference,event in
                let local=(event.from...event.through).compactMap { i -> Double? in
                    guard let p=a.samplePoints[i],let q=b.samplePoints[i] else { return nil }
                    return hypot(p.x-q.x,p.y-q.y)/pixelsPerMeter
                }
                return max(difference,local.isEmpty ? 0 : local.reduce(0,+)/Double(local.count))
            }
        }
        func evaluate(_ offset:Double,coherent:Bool=false) {
            guard !Task.isCancelled,Date()<deadline else { limited=true; return }
            guard evaluationCount<25 else { limited=true;return }
            let key=Int(offset.rounded())*2+(coherent ? 1 : 0)
            guard evaluated.insert(key).inserted else { return }
            let remaining=deadline.timeIntervalSinceNow
            let budget=min(offset==0 ? 3.0 : 1.5,remaining)
            let angle=normalized(baseline+offset)
            evaluationCount += 1
            let trialStarted=Date()
            guard let result=NonrigidRouteMatcher.match(input:input,anchor:anchor,pixelsPerMeter:pixelsPerMeter,
                rotationDegrees:angle,map:map,mapHash:mapHash,recordingID:recordingID,level:level,budgetSeconds:budget,
                shapePolicy:improvedExcursions ? .improved(level) : (preserveExcursions ? .make(level) : nil),
                coherentOnly:coherent) else {
                if Date().timeIntervalSince(trialStarted)>=budget { limited=true }; return
            }
            if result.searchIncomplete { limited=true }
            if resultTemplate==nil { resultTemplate=result }
            for c in result.candidates {
                var covered=0.0
                for i in input.indices.dropFirst() where input[i].segment==input[i-1].segment {
                    if c.samplePoints[i] != nil,c.samplePoints[i-1] != nil,let a=input[i-1].meters,let b=input[i].meters {
                        covered += hypot(b.x-a.x,b.y-a.y)
                    }
                }
                let coverage=min(1,covered/total)
                let ratio=covered>0.01 ? c.inferredLengthMeters/covered : 1
                let d=c.deformation,complete=d?.completedFraction ?? 0
                // Costs are comparable only after separating missing distance/samples from local fit.
                let fitCost=max(0,c.score-20*(1-complete))
                let objective=30*(1-coverage)+8*(1-complete)+fitCost
                    + 4*pow(log(max(0.01,ratio)),2)
                    + 1.2*pow((d?.maxDirectionChangeDegrees ?? 0)/100,2)
                    + 0.5*pow((d?.maxTurnChangeDegrees ?? 0)/90,2)
                    + 0.06*pow(offset/halfRange,2) + (result.searchIncomplete ? 0.2 : 0)
                    + (c.routeShape?.qualityPenalty ?? 0)
                let fit=InitialHeadingFit(rotationDegrees:angle,offsetDegrees:offset,distanceCoverage:coverage,
                    coveredLengthRatio:ratio,localPositionChangeMeters:c.maxLocalChangeMeters,objective:objective)
                let trial=Trial(candidate:c,fit:fit)
                tested.append(fit)
                if offset==0,baselineTrial==nil || rank(trial,baselineTrial!) { baselineTrial=trial }
                retained.append(trial); retained.sort(by:rank)
                // Keep a few spatial/angle alternatives, not every full sample array from every trial.
                var diverse:[Trial]=[]
                for t in retained {
                    let same=diverse.contains { other in
                        guard abs(delta(other.fit.rotationDegrees,t.fit.rotationDegrees))<8 else { return false }
                        if !preserveExcursions { return true }
                        return routeDifference(other.candidate,t.candidate)<0.35
                    }
                    if !same { diverse.append(t) }
                    if diverse.count==4 { break }
                }
                retained=diverse
            }
            progress(min(0.94,Double(evaluationCount)/25))
        }
        if improvedExcursions {
            // Cheap rigid registration ranking: no trajectory bending and no invented road graph.
            // It only orders hypotheses; every accepted edge is still checked by the full matcher.
            var ranked:[(offset:Double,cost:Double)]=[]
            let strideCount=max(1,(input.count+1399)/1400)
            for offset in stride(from:-halfRange,through:halfRange,by:2.0) {
                if Task.isCancelled { return nil }
                if Date()>=deadline { limited=true;break }
                var previous:MapPoint?,segment:Int?,travel=0.0,blocked=0.0
                for i in stride(from:0,to:input.count,by:strideCount) {
                    guard let p=input[i].meters else { previous=nil;segment=nil;continue }
                    let q=AnchoredMapMatcher.transformed(p,anchor:anchor,scale:pixelsPerMeter,rotation:baseline+offset,factor:1)
                    if let previous,segment==input[i].segment {
                        let distance=hypot(q.x-previous.x,q.y-previous.y)/pixelsPerMeter
                        travel += distance
                        if !map.grid.canTravel(previous,q) { blocked += distance }
                    }
                    previous=q;segment=input[i].segment
                }
                ranked.append((offset,blocked/max(0.01,travel)+0.002*pow(offset/halfRange,2)))
            }
            ranked.sort { abs($0.cost-$1.cost)>1e-9 ? $0.cost<$1.cost : abs($0.offset)<abs($1.offset) }
            var shortlist:[Double]=[]
            for trial in ranked where !shortlist.contains(where:{abs($0-trial.offset)<6}) {
                shortlist.append(trial.offset)
                if shortlist.count==4 { break }
            }
            for offset in shortlist { evaluate(offset,coherent:true) }
            evaluate(0,coherent:true)
            if let center=retained.first?.fit.offsetDegrees {
                for step in [-4.0,-2,2,4] where abs(center+step)<=halfRange { evaluate(center+step,coherent:true) }
            }
        }
        let coherentFit=improvedExcursions && retained.first.map {
            $0.fit.distanceCoverage>0.999 && ($0.candidate.deformation?.maxDirectionChangeDegrees ?? 180)<=24
                && $0.fit.localPositionChangeMeters<=1.5 && $0.fit.objective<0.15 && !$0.candidate.searchLimited
        } == true
        // If a small-deformation explanation completes the route, do not spend the phone's budget
        // inventing large warps. Otherwise retain the old wider search as a clearly bounded fallback.
        if !coherentFit {
            evaluate(0)
            for offset in [-10.0,10,-20,20,-30,30,-40,40,-50,50,-60,60] {
                if Task.isCancelled { return nil }
                if Date()>=deadline || evaluationCount>=25 { limited=true;break }
                evaluate(offset)
            }
            if let center=retained.first?.fit.offsetDegrees {
                for step in [-8.0,-6,-4,-2,2,4,6,8] where abs(center+step)<=halfRange {
                    if Task.isCancelled { return nil }
                    if Date()>=deadline || evaluationCount>=25 { limited=true;break }
                    evaluate(center+step)
                }
            }
        }
        guard !Task.isCancelled,var template=resultTemplate,!retained.isEmpty else { return nil }
        // Do not move an already good baseline merely because a nearby trial has a tiny lower cost.
        if let base=baselineTrial,let best=retained.first,
            base.fit.objective-best.fit.objective<0.12,base.fit.distanceCoverage>=best.fit.distanceCoverage-0.01 {
            retained.removeAll(where:{abs(delta($0.fit.rotationDegrees,base.fit.rotationDegrees))<8
                && (!preserveExcursions || routeDifference($0.candidate,base.candidate)<0.35)})
            retained.insert(base,at:0)
        }
        let best=retained[0]
        let ambiguous=total<3 || tested.contains { fit in
            abs(delta(fit.rotationDegrees,best.fit.rotationDegrees))>=8
                && abs(fit.objective-best.fit.objective)<0.12
                && abs(fit.distanceCoverage-best.fit.distanceCoverage)<0.02
        } || (preserveExcursions && retained.dropFirst().contains { trial in
            routeDifference(trial.candidate,best.candidate)>=0.35 && abs(trial.fit.objective-best.fit.objective)<0.15
                && abs(trial.fit.distanceCoverage-best.fit.distanceCoverage)<0.02
        })
        var candidates:[MapMatchCandidate]=[]
        for trial in retained.prefix(3) {
            let c=trial.candidate
            var changes:[Double]=[]
            for i in input.indices {
                if let p=input[i].meters,let q=c.samplePoints[i] {
                    let raw=AnchoredMapMatcher.transformed(p,anchor:anchor,scale:pixelsPerMeter,rotation:baseline,factor:1)
                    changes.append(hypot(q.x-raw.x,q.y-raw.y)/pixelsPerMeter)
                }
            }
            var candidate=MapMatchCandidate(scaleFactor:c.scaleFactor,score:trial.fit.objective,vertices:c.vertices,
                samplePoints:c.samplePoints,unresolved:c.unresolved,maxLocalChangeMeters:changes.max() ?? 0,
                meanLocalChangeMeters:changes.reduce(0,+)/Double(max(1,changes.count)),inferredLengthMeters:c.inferredLengthMeters,
                scaledLengthMeters:total*c.scaleFactor,searchLimited:c.searchLimited,deformation:c.deformation)
            candidate.initialHeading=trial.fit
            candidate.routeShape=c.routeShape
            candidates.append(candidate)
        }
        template=MapMatchResult(candidates:candidates,elapsedSeconds:Date().timeIntervalSince(start),searchIncomplete:limited,
            mapHash:mapHash,sourceRecordingID:recordingID,anchor:anchor,rotationDegrees:baseline,pixelsPerMeter:pixelsPerMeter)
        template.algorithm="initial-yaw-search-plus-v9-v1"
        if preserveExcursions { template.algorithm=improvedExcursions ? "initial-yaw-and-whole-lobe-shape-envelope-v2" : "initial-yaw-and-excursion-arc-budget-v1" }
        template.deformationLevel=level
        template.scaleRange=[level.factorRange.lowerBound,level.factorRange.upperBound]
        template.initialHeadingSearch=InitialHeadingSearchSummary(baselineRotationDegrees:baseline,searchHalfRangeDegrees:halfRange,
            evaluatedRotations:evaluationCount,originalLengthMeters:total,ambiguous:ambiguous,
            reachedBoundary:abs(best.fit.offsetDegrees)>=halfRange-2,baselineDistanceCoverage:baselineTrial?.fit.distanceCoverage ?? 0)
        if improvedExcursions { template.initialHeadingSearch?.registrationFirst=true }
        progress(1)
        return template
    }
}
