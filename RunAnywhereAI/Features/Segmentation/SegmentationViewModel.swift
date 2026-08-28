#if os(iOS)
import Combine
import CoreGraphics
import Foundation
import Observation
import RunAnywhere
import SwiftUI
import UIKit
import os

enum SegmentationStatus: Equatable {
    case idle
    case running
    case done(classes: Int, milliseconds: Int)
    case failed(String)
}

@Observable
@MainActor
final class SegmentationViewModel {
    private(set) var modelState: ModelState = .none
    private(set) var loadedModelID: String?
    private(set) var isModelReady = false

    private(set) var source: UIImage?
    private(set) var sourceLabel: String?
    private(set) var mask: UIImage?
    private(set) var classes: [ClassInfo] = []
    private(set) var status: SegmentationStatus = .idle
    private(set) var isRunning = false
    var notice: String?

    private var lifecycle: AnyCancellable?
    private var installed: [InstalledModel] = []
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Segmentation")

    /// Longest edge handed to the model. A full-resolution camera-roll photo is
    /// tens of megapixels, and the mask is one UInt16 per pixel on top of it.
    private static let maxEdge: CGFloat = 1024

    var canRun: Bool { isModelReady && source != nil && !isRunning }

    // MARK: - Lifecycle

    func start(store: ModelStore) async {
        installed = store.installed
        if lifecycle == nil { observeLifecycle() }
        await adoptLoadedModel()
    }

    private func observeLifecycle() {
        lifecycle = RunAnywhere.eventBus.events(for: .component)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in self?.apply(event.componentLifecycle) }
            }
    }

    private func apply(_ event: RAComponentLifecycleEvent) {
        guard event.component == .semanticSegmentation else { return }
        switch event.currentState {
        case .ready:
            isModelReady = true
            guard event.modelID != loadedModelID else { return }
            loadedModelID = event.modelID
            modelState = describe(id: event.modelID)
        case .notLoaded, .unloading, .shutdown, .deleting:
            isModelReady = false
            loadedModelID = nil
            modelState = .none
        default:
            break
        }
    }

    // MARK: - Model

    private func adoptLoadedModel() async {
        let state = await RunAnywhere.models.state()
        guard let loaded = state.loaded[.semanticSegmentation] else {
            isModelReady = false
            loadedModelID = nil
            modelState = .none
            return
        }
        isModelReady = true
        loadedModelID = loaded.id
        modelState = describe(id: loaded.id)
    }

    func load(_ model: InstalledModel, store: ModelStore) async {
        installed = store.installed
        notice = nil
        modelState = .loading(model.name, 0.1)
        do {
            try await store.load(model.id)
            isModelReady = true
            loadedModelID = model.id
            modelState = .loaded(model.name, model.backend)
        } catch {
            isModelReady = false
            loadedModelID = nil
            modelState = .none
            notice = "\(model.name) would not load: \(error.localizedDescription)"
            logger.error("segmentation model load failed: \(error, privacy: .public)")
        }
    }

    private func describe(id: String) -> ModelState {
        guard let known = installed.first(where: { $0.id == id }) else {
            return .loaded(id, "Local")
        }
        return .loaded(known.name, known.backend)
    }

    // MARK: - Picture

    func use(_ image: UIImage) {
        let prepared = Self.downscaled(image)
        source = prepared
        mask = nil
        classes = []
        status = .idle
        notice = nil
        sourceLabel = "\(Int(prepared.size.width)) × \(Int(prepared.size.height))"
    }

    // MARK: - Running

    func run() async {
        guard let image = source else { return }
        isRunning = true
        status = .running
        mask = nil
        classes = []
        notice = nil
        defer { isRunning = false }

        do {
            let started = Date()
            let result = try await RunAnywhere.segmentation.segment(.uiImage(image))
            let elapsed = Int((Date().timeIntervalSince(started) * 1000).rounded())

            classes = result.classes.sorted { $0.pixelCount > $1.pixelCount }
            mask = Self.overlay(classMask: result.classMask, width: result.width, height: result.height)
            status = .done(classes: result.classes.count, milliseconds: elapsed)
        } catch {
            status = .failed(error.localizedDescription)
            logger.error("segmentation failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Rendering

    private static func downscaled(_ image: UIImage) -> UIImage {
        // Pixels, not points: a 3x photo is three times larger than `size` says.
        let longest = max(image.size.width * image.scale, image.size.height * image.scale)
        guard longest > maxEdge else { return image }
        let ratio = maxEdge / longest
        let target = CGSize(
            width: (image.size.width * image.scale * ratio).rounded(),
            height: (image.size.height * image.scale * ratio).rounded()
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Paint the little-endian UInt16 class mask into a translucent overlay.
    private static func overlay(classMask: Data, width: Int, height: Int) -> UIImage? {
        let pixels = width * height
        guard pixels > 0, classMask.count >= pixels * 2 else { return nil }

        var rgba = Data(count: pixels * 4)
        classMask.withUnsafeBytes { maskBuffer in
            rgba.withUnsafeMutableBytes { outBuffer in
                let mask = maskBuffer.bindMemory(to: UInt8.self)
                let out = outBuffer.bindMemory(to: UInt8.self)
                for index in 0..<pixels {
                    let classId = Int(mask[index * 2]) | (Int(mask[index * 2 + 1]) << 8)
                    let parts = components(for: classId)
                    out[index * 4] = parts.red
                    out[index * 4 + 1] = parts.green
                    out[index * 4 + 2] = parts.blue
                    // Class 0 is "unlabelled": leave the picture showing through.
                    out[index * 4 + 3] = classId == 0 ? 0 : 255
                }
            }
        }
        return image(fromRGBA: rgba, width: width, height: height)
    }

    /// A mask needs as many distinguishable colours as the model has classes,
    /// which is more than a palette can name — so they are generated, spread
    /// around the hue circle by the golden ratio, and deterministic per class so
    /// the swatch beside a row matches the region on the picture.
    private static func components(for classId: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let hue = (Double(classId) * 0.61803398875).truncatingRemainder(dividingBy: 1)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(hue: hue, saturation: 0.85, brightness: 0.95, alpha: 1)
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (UInt8(red * 255), UInt8(green * 255), UInt8(blue * 255))
    }

    static func tint(for classId: Int) -> Color {
        let parts = components(for: classId)
        return Color(
            red: Double(parts.red) / 255,
            green: Double(parts.green) / 255,
            blue: Double(parts.blue) / 255
        )
    }

    private static func image(fromRGBA data: Data, width: Int, height: Int) -> UIImage? {
        guard data.count == width * height * 4, let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
#endif
