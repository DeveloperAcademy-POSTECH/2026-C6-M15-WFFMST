import AVFoundation

/// PCM sample operations preserve the source sample rate and use half-open sample ranges.
nonisolated enum RecordingAudioSamples {
    static func sampleRate(of buffer: CMSampleBuffer) -> Double? {
        guard let format = CMSampleBufferGetFormatDescription(buffer),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format),
              stream.pointee.mSampleRate > 0 else { return nil }
        return stream.pointee.mSampleRate
    }

    static func endTime(of buffer: CMSampleBuffer) -> Double {
        let start = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        guard let rate = sampleRate(of: buffer) else { return start }
        return start + Double(CMSampleBufferGetNumSamples(buffer)) / rate
    }

    /// A sample belongs to the interval containing its start time. Both sides use the same
    /// rounded-up index, so splitting a buffer neither duplicates nor loses PCM samples.
    static func slice(_ buffer: CMSampleBuffer, from start: Double, to end: Double) -> CMSampleBuffer? {
        guard let rate = sampleRate(of: buffer), start < end else { return nil }
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        guard pts.isFinite else { return nil }
        let count = CMSampleBufferGetNumSamples(buffer)
        func index(at time: Double) -> Int {
            let value = (time - pts) * rate
            if value <= 0 { return 0 }
            if value >= Double(count) { return count }
            return Int(ceil(value - 0.000001))
        }
        let lower = index(at: start)
        let upper = index(at: end)
        guard lower < upper else { return nil }
        var copy: CMSampleBuffer?
        guard CMSampleBufferCopySampleBufferForRange(
            allocator: kCFAllocatorDefault, sampleBuffer: buffer,
            sampleRange: CFRange(location: lower, length: upper - lower), sampleBufferOut: &copy
        ) == noErr else { return nil }
        return copy
    }

    static func retime(_ buffer: CMSampleBuffer, convert: (CMTime) -> CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count
        ) == noErr, count > 0 else { return nil }
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        let status = timings.withUnsafeMutableBufferPointer { pointer in
            CMSampleBufferGetSampleTimingInfoArray(
                buffer, entryCount: count, arrayToFill: pointer.baseAddress, entriesNeededOut: &count
            )
        }
        guard status == noErr else { return nil }
        for index in timings.indices {
            if timings[index].presentationTimeStamp.isValid {
                timings[index].presentationTimeStamp = convert(timings[index].presentationTimeStamp)
            }
            if timings[index].decodeTimeStamp.isValid {
                timings[index].decodeTimeStamp = convert(timings[index].decodeTimeStamp)
            }
        }
        var copy: CMSampleBuffer?
        let result = timings.withUnsafeBufferPointer { pointer in
            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault, sampleBuffer: buffer,
                sampleTimingEntryCount: count, sampleTimingArray: pointer.baseAddress,
                sampleBufferOut: &copy
            )
        }
        return result == noErr ? copy : nil
    }
}
