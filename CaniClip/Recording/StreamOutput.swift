import CoreMedia
import ScreenCaptureKit

/// Receives SCStream sample buffers and forwards complete frames to the sink.
final class StreamOutput: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "com.caniclip.stream-output", qos: .userInteractive)
    private let sink: GifRecordingSink

    init(sink: GifRecordingSink) {
        self.sink = sink
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[String: Any]],
              let statusRaw = attachments.first?[SCStreamFrameInfo.status.rawValue] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw), status == .complete else { return }
        guard let pixelBuffer = sampleBuffer.imageBuffer,
              let frame = FrameConverter.bgraFrame(from: pixelBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        sink.append(frame, presentationTime: pts)
    }
}
