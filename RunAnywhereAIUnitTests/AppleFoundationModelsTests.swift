//
//  AppleFoundationModelsTests.swift
//  RunAnywhereAITests
//
//  "Apple Foundation Models don't work" is usually not a defect in this app:
//  the framework refuses on a device where Apple Intelligence is off, not
//  eligible, or still downloading, and it says which. What *was* a defect is
//  that the app reduced all of that to a Bool, so the row sat in the picker
//  looking broken with nothing the user could do.
//
//  These tests pin the contract in both directions: the verdict must agree with
//  the reason, the reason must survive the trip into the app, and an
//  unavailable Apple model must never be handed out as a recommendation.
//
//  The first test prints the live verdict. On a machine where the model is
//  refused, that line is the answer to "why doesn't it work" — read it before
//  reading anything else.
//

import RunAnywhere
import XCTest
@testable import RunAnywhereAI

final class AppleFoundationModelsTests: XCTestCase {
    private let resolver = HardwareTierResolver()

    // MARK: - What this device actually reports

    /// Not an assertion about any particular machine — a report. Whatever the
    /// runtime says here is what every screen in the app is working from.
    func testLiveVerdictIsReported() {
        let reason = resolver.appleFoundationUnavailableReason
        print("[AppleFoundationModels] available=\(resolver.appleFoundationAvailable) reason=\(reason ?? "none")")
        XCTAssertEqual(
            resolver.appleFoundationAvailable,
            reason == nil,
            "a device is either usable or has a reason it is not; never both or neither"
        )
    }

    // MARK: - The SDK contract

    func testSDKAvailabilityAgreesWithItsOwnReason() {
        XCTAssertEqual(
            SystemFoundationModels.isAvailable,
            SystemFoundationModels.unavailableReason == nil
        )
    }

    /// The resolver is the app's only reader of this. If it disagrees with the
    /// SDK, half the app is gated on one verdict and half on another.
    func testResolverMatchesTheSDK() {
        XCTAssertEqual(resolver.appleFoundationAvailable, SystemFoundationModels.isAvailable)
        XCTAssertEqual(
            resolver.appleFoundationUnavailableReason,
            SystemFoundationModels.unavailableReason
        )
    }

    /// A reason only earns its place if it tells the reader what to change.
    /// A blank string, or one that just restates the verdict, does not.
    func testAnUnavailableReasonIsSomethingTheUserCanActOn() throws {
        let reason = try XCTUnwrap(
            resolver.appleFoundationUnavailableReason,
            "Apple's model is available on this machine, so there is no reason to check"
        )
        XCTAssertFalse(reason.trimmingCharacters(in: .whitespaces).isEmpty)
        XCTAssertGreaterThan(reason.count, 20, "too short to say what to do: \(reason)")
        XCTAssertFalse(
            reason.lowercased() == "false" || reason.lowercased() == "unavailable",
            "restates the verdict instead of explaining it: \(reason)"
        )
    }

    // MARK: - Nothing recommends a model that cannot run

    /// Repeated because the catalog is walked through a Dictionary, whose
    /// iteration order changes per process. One pass agreeing proves nothing;
    /// this failed roughly half the time before the back-fill was gated.
    func testAppleModelIsNotTheDefaultChatModelWhenItCannotRun() {
        for _ in 0..<50 {
            let selection = ModelRecommendationEngine().recommend(
                tier: .unknown,
                appleFoundationAvailable: false,
                from: [appleModel(), localModel()]
            )
            XCTAssertNotEqual(selection.defaultChatModel?.id, appleModel().id)
            XCTAssertFalse(
                selection.recommendedLLMs.contains { $0.isAppleFoundationModel },
                "a model the runtime refuses was recommended"
            )
        }
    }

    /// The order itself has to hold still, or the list reshuffles under the
    /// user between refreshes for no reason they can see.
    func testRecommendationOrderIsStableAcrossCalls() {
        let engine = ModelRecommendationEngine()
        let models = [appleModel(), localModel(), secondLocalModel()]
        let first = engine.recommend(tier: .unknown, appleFoundationAvailable: true, from: models)
            .recommendedLLMs.map(\.id)

        for _ in 0..<50 {
            let again = engine.recommend(tier: .unknown, appleFoundationAvailable: true, from: models)
                .recommendedLLMs.map(\.id)
            XCTAssertEqual(again, first)
        }
    }

    func testAppleModelIsTheDefaultChatModelWhenItCanRun() {
        let selection = ModelRecommendationEngine().recommend(
            tier: .unknown,
            appleFoundationAvailable: true,
            from: [appleModel(), localModel()]
        )
        XCTAssertEqual(selection.defaultChatModel?.id, appleModel().id)
    }

    /// Voice runs the same preference through a second entry point, which is
    /// exactly the kind of pair that drifts.
    func testVoicePipelineDoesNotPickTheAppleModelWhenItCannotRun() {
        for _ in 0..<50 {
            let pipeline = ModelRecommendationEngine().recommendVoicePipeline(
                tier: .unknown,
                appleFoundationAvailable: false,
                from: [appleModel(), localModel()]
            )
            XCTAssertNotEqual(pipeline.llm?.id, appleModel().id)
        }
    }

    /// The verdict the app runs on is the one the device reports, so the two
    /// entry points have to reach the same conclusion from it.
    func testBothEntryPointsAgreeOnThisDevice() {
        let engine = ModelRecommendationEngine()
        let models = [appleModel(), localModel()]
        let available = resolver.appleFoundationAvailable

        let chat = engine.recommend(
            tier: resolver.resolve(),
            appleFoundationAvailable: available,
            from: models
        ).defaultChatModel
        let voice = engine.recommendVoicePipeline(
            tier: resolver.resolve(),
            appleFoundationAvailable: available,
            from: models
        ).llm

        XCTAssertEqual(chat?.id == appleModel().id, voice?.id == appleModel().id)
    }

    // MARK: - What the row claims

    /// The row used to show "Built in" with a green tick regardless, which
    /// reads as ready. It may only say that when the runtime agrees.
    func testBuiltInRowOnlyClaimsReadyWhenTheRuntimeAgrees() {
        let claimsReady = ModelActionButton.builtInUnavailableReason(for: appleModel()) == nil
        XCTAssertEqual(claimsReady, resolver.appleFoundationAvailable)
    }

    /// Only Apple's built-in can be refused by the runtime; no other built-in
    /// row should start showing a warning because of this.
    func testOtherBuiltInModelsAreNeverMarkedUnavailable() {
        var builtIn = RAModelInfo()
        builtIn.id = "some-other-builtin"
        builtIn.category = .speechSynthesis
        XCTAssertNil(ModelActionButton.builtInUnavailableReason(for: builtIn))
    }

    // MARK: - What the picker offers

    /// The picker gates on this one field, so it has to carry the reason for
    /// the Apple row and stay nil for everything else.
    func testStoreRowCarriesTheReasonForTheAppleModelOnly() {
        XCTAssertEqual(appleModel().runtimeUnavailableReason, resolver.appleFoundationUnavailableReason)
        XCTAssertNil(localModel().runtimeUnavailableReason)
    }

    /// "Selectable" and "the runtime will accept it" have to be the same
    /// question, or the picker offers a row that fails on tap.
    func testAppleRowIsSelectableOnlyWhenTheRuntimeAcceptsIt() {
        let selectable = appleModel().runtimeUnavailableReason == nil
        XCTAssertEqual(selectable, resolver.appleFoundationAvailable)
    }

    // MARK: - Fixtures

    private func appleModel() -> RAModelInfo {
        var model = RAModelInfo()
        model.id = "apple-foundation-default"
        model.name = "Apple LLM"
        model.category = .language
        model.framework = .foundationModels
        return model
    }

    private func secondLocalModel() -> RAModelInfo {
        var model = RAModelInfo()
        model.id = "mlx-lfm2.5-1.2b-instruct-4bit"
        model.name = "LFM2.5 1.2B"
        model.category = .language
        model.framework = .mlx
        return model
    }

    private func localModel() -> RAModelInfo {
        var model = RAModelInfo()
        model.id = "mlx-qwen3.5-0.8b-mlx-4bit"
        model.name = "Qwen3.5 0.8B"
        model.category = .language
        model.framework = .mlx
        return model
    }
}
