//
//  ModelDownloadHelper.swift
//  RunAnywhereAITests
//
//  Fetches the models the execution suite needs, on demand.
//

import RunAnywhere
import XCTest
@testable import RunAnywhereAI

/// Downloads models so the workflow suite has something capable to run against.
///
/// Skipped unless `RA_DOWNLOAD_MODELS` names what to fetch, because a test that
/// pulls gigabytes on every run is a test nobody runs. It exists so getting a
/// machine ready is a command rather than a trip through the UI.
final class ModelDownloadHelper: XCTestCase {

    @MainActor
    func testDownloadRequestedModels() async throws {
        guard let requested = ProcessInfo.processInfo.environment["RA_DOWNLOAD_MODELS"],
              !requested.isEmpty else {
            throw XCTSkip("Set RA_DOWNLOAD_MODELS to a comma-separated list of model ids.")
        }

        try RunAnywhere.initialize(environment: .development)
        await ModelCatalogBootstrap.registerAll(mlxRegistered: true)
        _ = try? await RunAnywhere.models.refresh()

        var report: [String] = []
        for id in requested.split(separator: ",").map({ String($0).trimmingCharacters(in: .whitespaces) }) {
            do {
                let stream = try await RunAnywhere.models.download(id: id)
                var lastFailure: String?
                for try await event in stream {
                    if case .failed(_, _, let error) = event { lastFailure = error.message }
                }
                let catalog = (try? await RunAnywhere.models.list()) ?? []
                let landed = catalog.first { $0.id == id }.map { !$0.localPath.isEmpty } ?? false
                report.append("\(id): \(landed ? "installed" : "FAILED \(lastFailure ?? "no local path")")")
            } catch {
                report.append("\(id): threw \(error)")
            }
        }

        // The outcome travels in the assertion because test output does not
        // reach xcodebuild.
        XCTAssertTrue(
            report.allSatisfy { $0.contains("installed") },
            report.joined(separator: "\n")
        )
    }
}
