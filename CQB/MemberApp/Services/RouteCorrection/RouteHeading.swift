import Foundation

nonisolated enum RouteDirectionMode: String, Codable, CaseIterable, Sendable {
    case firstWalk, cameraAtStart
}

nonisolated enum RouteHeading {
    nonisolated static func fittedFirstWalk(_ points:[MapPoint?],segments:[Int],minimumDistance:Double = 0.8) -> Double? {
        guard points.count==segments.count,let first=points.firstIndex(where:{$0 != nil}),let origin=points[first] else { return nil }
        var prefix=[origin],walked=0.0,previous=origin,best:[MapPoint]=[]
        for i in points.indices where i>first {
            guard segments[i]==segments[first],let p=points[i] else { break }
            walked += hypot(p.x-previous.x,p.y-previous.y); previous=p
            let displacement=hypot(p.x-origin.x,p.y-origin.y)
            if walked>0.5,displacement/max(0.001,walked)<0.90 { break }
            prefix.append(p)
            if displacement>=minimumDistance { best=prefix }
            if displacement>=2 || walked>2.5 { break }
        }
        guard best.count>=3,let end=best.last else { return nil }
        let mx=best.map(\.x).reduce(0,+)/Double(best.count),my=best.map(\.y).reduce(0,+)/Double(best.count)
        var xx=0.0,xy=0.0,yy=0.0
        for p in best { xx += pow(p.x-mx,2); xy += (p.x-mx)*(p.y-my); yy += pow(p.y-my,2) }
        var angle=0.5*atan2(2*xy,xx-yy)
        if cos(angle)*(end.x-origin.x)+sin(angle)*(end.y-origin.y)<0 { angle += .pi }
        let residual=sqrt(best.map { pow(-( $0.x-mx)*sin(angle)+($0.y-my)*cos(angle),2) }.reduce(0,+)/Double(best.count))
        guard residual<=0.12 else { return nil }
        return atan2(sin(angle),cos(angle))
    }
    /// Circular mean around a stable starting pose; not an absolute compass heading.
    nonisolated static func stableCameraDirection(_ angles:[Double]) -> Double? {
        guard angles.count>=8,angles.allSatisfy(\.isFinite) else { return nil }
        let x=angles.map(cos).reduce(0,+)/Double(angles.count),y=angles.map(sin).reduce(0,+)/Double(angles.count)
        guard hypot(x,y)>=0.995 else { return nil }
        let angle=atan2(y,x)
        guard let last=angles.last,abs(atan2(sin(last-angle),cos(last-angle)))<=5 * .pi/180 else { return nil }
        return angle
    }
    nonisolated static func rotation(start: MapPoint, toward: MapPoint, referenceRadians: Double) -> Double? {
        guard referenceRadians.isFinite, hypot(toward.x-start.x, toward.y-start.y) >= 10 else { return nil }
        let degrees = (atan2(toward.y-start.y, toward.x-start.x) - referenceRadians) * 180 / .pi
        return (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    nonisolated static func firstWalk(_ points: [MapPoint?], segments: [Int]) -> Double? {
        guard points.count == segments.count, let first = points.firstIndex(where: { $0 != nil }), let origin = points[first] else { return nil }
        var walked = 0.0, previous = origin
        for i in points.indices where i > first {
            guard segments[i] == segments[first], let p = points[i] else { return nil }
            walked += hypot(p.x-previous.x, p.y-previous.y); previous = p
            let displacement = hypot(p.x-origin.x, p.y-origin.y)
            if displacement >= 0.8 {
                guard walked > 0, displacement / walked >= 0.85 else { return nil }
                return atan2(p.y-origin.y, p.x-origin.x)
            }
            if walked > 1.4 { return nil }
        }
        return nil
    }
}
