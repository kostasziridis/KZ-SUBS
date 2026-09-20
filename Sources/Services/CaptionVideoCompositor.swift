import AVFoundation
import CoreImage

/// A caption already placed where it belongs in the output frame.
///
/// `@unchecked Sendable`: `CIImage` is immutable once built, and these are only read
/// during compositing.
struct PositionedCaption: @unchecked Sendable {
    let image: CIImage
    let start: TimeInterval
    let end: TimeInterval
}

/// Carries the captions to the compositor.
///
/// AVFoundation creates the compositor itself, so there is nowhere to hand it the
/// data directly - the instruction is the supported way through.
final class CaptionCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {

    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid

    let trackID: CMPersistentTrackID
    let captions: [PositionedCaption]
    /// The track's preferred transform, applied here rather than by a layer instruction
    /// because a custom compositor receives the raw source frame.
    let transform: CGAffineTransform
    let renderSize: CGSize

    init(
        timeRange: CMTimeRange,
        trackID: CMPersistentTrackID,
        captions: [PositionedCaption],
        transform: CGAffineTransform,
        renderSize: CGSize
    ) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.captions = captions
        self.transform = transform
        self.renderSize = renderSize
        self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
        super.init()
    }
}

/// Draws the captions onto each frame with Core Image.
///
/// Chosen over `AVVideoCompositionCoreAnimationTool`, which renders a Core Animation
/// layer tree offline: that path needs IOSurfaces the Simulator cannot provide and
/// traps there, so it can only ever be tested on a device. This works in both places.
final class CaptionVideoCompositor: NSObject, AVVideoCompositing {

    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    var sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]
    ]

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // Nothing cached per context; buffers come from the context on each request.
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard
            let instruction = request.videoCompositionInstruction as? CaptionCompositionInstruction,
            let sourceBuffer = request.sourceFrame(byTrackID: instruction.trackID),
            let outputBuffer = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: AppError.exportFailed)
            return
        }

        var image = CIImage(cvPixelBuffer: sourceBuffer)

        if !instruction.transform.isIdentity {
            image = image.transformed(by: instruction.transform)
            // A rotation leaves the extent off the origin; bring it back so the frame
            // lines up with the render size.
            image = image.transformed(
                by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y)
            )
        }

        let time = request.compositionTime.seconds
        for caption in instruction.captions where time >= caption.start && time < caption.end {
            image = caption.image.composited(over: image)
        }

        context.render(
            image,
            to: outputBuffer,
            bounds: CGRect(origin: .zero, size: instruction.renderSize),
            colorSpace: colorSpace
        )

        request.finish(withComposedVideoFrame: outputBuffer)
    }

    func cancelAllPendingVideoCompositionRequests() {
        // Requests are served synchronously, so there is nothing queued to drop.
    }
}
