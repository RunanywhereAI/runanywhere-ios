//
//  OCRViewModel.swift
//  RunAnywhereAI
//
//  Full-page text recognition over `RunAnywhere.ocr`.
//
//  Pure platform plumbing, like SegmentationViewModel: it loads a catalog OCR
//  model, hands the picked image to the SDK as an `ImageInput`, and draws the
//  quads that come back. Detection, recognition, CTC decoding and the mapping
//  of boxes back into source-image pixels all live in the SDK / C++ commons.
//

#if canImport(UIKit)
import Foundation
import SwiftUI
import RunAnywhere
import UIKit
import os.log

@MainActor
@Observable
final class OCRViewModel {
    // Model lifecycle
    private(set) var isModelLoaded = false
    private(set) var loadedModelName: String?
    private(set) var isProcessing = false

    // Image input
    private(set) var sourceImage: UIImage?

    // OCR output
    private(set) var isReading = false
    private(set) var regions: [OCRRegion] = []
    private(set) var overlayImage: UIImage?
    private(set) var processingTimeMs: Int = 0

    private(set) var statusMessage = ""
    private(set) var error: String?

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "OCR")

    /// Longest edge handed to the model. Higher than segmentation's 1024
    /// because OCR reads glyphs: downscaling a page until the text is a few
    /// pixels tall is how a working detector gets blamed for finding nothing.
    private static let maxDimension = 2048

    /// The transcript, one region per line, in detector order.
    var transcript: String { regions.map(\.text).joined(separator: "\n") }

    // MARK: - Model status

    func refreshModelStatus() async {
        let state = await RunAnywhere.models.state()
        guard let model = state.loaded[.ocr] else {
            isModelLoaded = false
            return
        }
        isModelLoaded = true
        loadedModelName = model.name.isEmpty ? model.id : model.name
    }

    // MARK: - Model supply (catalog Get → Use)

    func loadModelFromSelection(_ model: RAModelInfo) async {
        isProcessing = true
        error = nil
        statusMessage = "Loading model…"
        defer { isProcessing = false }

        do {
            try await RunAnywhere.models.load(id: model.id)
        } catch {
            self.error = "Model load failed: \(error.localizedDescription)"
            statusMessage = ""
            return
        }
        loadedModelName = model.name.isEmpty ? model.id : model.name
        isModelLoaded = true
        statusMessage = "Model loaded: \(loadedModelName ?? model.id)."
    }

    // MARK: - Image input

    func setImage(_ image: UIImage) {
        let prepared = Self.downscaled(image, maxDimension: Self.maxDimension)
        sourceImage = prepared
        overlayImage = nil
        regions = []
        error = nil
        let size = prepared.size
        statusMessage = "Image ready (\(Int(size.width))×\(Int(size.height)))."
    }

    // MARK: - Reading

    func runOCR() async {
        guard isModelLoaded else { error = "Load an OCR model first."; return }
        guard let image = sourceImage else { error = "Pick an image first."; return }

        isReading = true
        error = nil
        overlayImage = nil
        regions = []
        statusMessage = "Reading page…"
        defer { isReading = false }

        do {
            let result = try await RunAnywhere.ocr.readPage(.uiImage(image))
            // Commons measures this across the engine call, so it is the real
            // read time and not a round trip through SwiftUI.
            processingTimeMs = result.processingTimeMs
            regions = result.regions
            overlayImage = Self.overlay(regions: result.regions, on: image)
            statusMessage = "Read \(result.regions.count) regions in \(processingTimeMs)ms."
        } catch {
            logger.error("OCR failed: \(error.localizedDescription)")
            self.error = "OCR failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Rendering helpers

    private static func downscaled(_ image: UIImage, maxDimension: Int) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > CGFloat(maxDimension) else { return image }
        let scale = CGFloat(maxDimension) / longest
        let target = CGSize(width: (image.size.width * scale).rounded(),
                            height: (image.size.height * scale).rounded())
        return UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Stroke each region's quad over the source image.
    ///
    /// Draws the QUAD and not `boundingBox`: the detector emits rotated boxes,
    /// and painting axis-aligned rectangles over skewed text would make a
    /// correct detection look wrong.
    private static func overlay(regions: [OCRRegion], on image: UIImage) -> UIImage? {
        guard !regions.isEmpty else { return nil }
        return UIGraphicsImageRenderer(size: image.size).image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let cg = context.cgContext
            cg.setLineWidth(max(1.5, image.size.width / 500))
            cg.setStrokeColor(UIColor(red: 1.0, green: 0.412, blue: 0.0, alpha: 0.95).cgColor)
            for region in regions where region.quad.count == 4 {
                cg.beginPath()
                cg.move(to: region.quad[0])
                for point in region.quad.dropFirst() {
                    cg.addLine(to: point)
                }
                cg.closePath()
                cg.strokePath()
            }
        }
    }
}
#endif
