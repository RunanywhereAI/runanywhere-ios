import AVFoundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// The live viewfinder. One representable per platform: UIKit makes the preview
/// layer the view's own backing layer so it is sized for us, AppKit hosts it as
/// a layer-backed `NSView`.
#if os(iOS)
struct VisionCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        // The session is rebuilt on a model swap or a retry while the same view
        // stays on screen; without this the preview holds the dead one and stays
        // black while frames flow into the model.
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // Guaranteed by `layerClass` above.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
#elseif os(macOS)
struct VisionCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = preview
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let preview = view.layer as? AVCaptureVideoPreviewLayer else { return }
        if preview.session !== session {
            preview.session = session
        }
    }
}
#endif
