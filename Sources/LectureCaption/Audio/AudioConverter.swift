@preconcurrency import AVFoundation
import Foundation

enum PCM16ConverterError: Error {
    case unsupportedInputFormat
    case conversionFailed
}

final class PCM16AudioConverter {
    let outputFormat: AVAudioFormat

    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    init(sampleRate: Double = 16_000) {
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        )!
    }

    func convert(
        _ input: AVAudioPCMBuffer,
        sequence: Int,
        startedAt: TimeInterval
    ) throws -> PCM16Frame {
        guard input.frameLength > 0 else {
            return PCM16Frame(sequence: sequence, data: Data(), sampleRate: outputFormat.sampleRate, startedAt: startedAt)
        }

        if converter == nil || inputFormat?.isEqual(input.format) != true {
            guard let newConverter = AVAudioConverter(from: input.format, to: outputFormat) else {
                throw PCM16ConverterError.unsupportedInputFormat
            }
            converter = newConverter
            inputFormat = input.format
        }

        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 8
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw PCM16ConverterError.conversionFailed
        }

        let inputSupply = InputSupply(input)
        var conversionError: NSError?
        let status = converter!.convert(to: output, error: &conversionError) { _, inputStatus in
            guard let buffer = inputSupply.take() else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, conversionError == nil,
              let samples = output.int16ChannelData else {
            if let conversionError {
                throw conversionError
            }
            throw PCM16ConverterError.conversionFailed
        }

        return PCM16Frame(
            sequence: sequence,
            data: Data(bytes: samples[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size),
            sampleRate: outputFormat.sampleRate,
            startedAt: startedAt
        )
    }
}

private final class InputSupply: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        lock.withLock {
            defer { buffer = nil }
            return buffer
        }
    }
}
