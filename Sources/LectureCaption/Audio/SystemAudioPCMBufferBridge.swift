@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation

enum SystemAudioPCMBufferBridge {
    static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let format = AVAudioFormat(streamDescription: streamDescription) else {
            return nil
        }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0,
              let destination = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            return nil
        }

        var requiredSize = 0
        var retainedBlockBuffer: CMBlockBuffer?
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &retainedBlockBuffer
        )
        guard sizeStatus == noErr, requiredSize > 0 else { return nil }

        let rawList = UnsafeMutableRawPointer.allocate(byteCount: requiredSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawList.deallocate() }
        let sourceList = rawList.assumingMemoryBound(to: AudioBufferList.self)
        var retainedCopy: CMBlockBuffer?
        let copyStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: sourceList,
            bufferListSize: requiredSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &retainedCopy
        )
        guard copyStatus == noErr else { return nil }

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(sourceList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(destination.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else { return nil }

        for index in sourceBuffers.indices {
            let source = sourceBuffers[index]
            let destinationBuffer = destinationBuffers[index]
            guard let sourceData = source.mData,
                  let destinationData = destinationBuffer.mData,
                  source.mDataByteSize <= destinationBuffer.mDataByteSize else {
                return nil
            }
            memcpy(destinationData, sourceData, Int(source.mDataByteSize))
        }

        destination.frameLength = AVAudioFrameCount(frameCount)
        return destination
    }
}
