//
//  WorkflowTemplateFixture.swift
//  RunAnywhereAITests
//
//  What each template needs before it can run, and what it has to leave behind.
//

import Foundation
import XCTest
@testable import RunAnywhereAI

/// One template's real inputs and its real expected outputs.
///
/// Kept as data rather than as a branch inside the test, so a template that has
/// no entry is skipped visibly instead of quietly passing. Adding a template to
/// the library and not to this table means it is not covered, and the count
/// assertion in the suite is what makes that noticeable.
struct Fixture {
    /// Written into whatever file the template reads. The template owns the
    /// name; the fixture owns only what is in it.
    var input: String = ""
    /// What has to be true of each file the template writes.
    var expect: (String) -> Bool = { !$0.isEmpty }
    /// A last chance to fill in anything a template deliberately ships blank.
    var adjust: (inout WorkflowNode) -> Void = { _ in }

    func verify(files: [String], in sandbox: URL, template: String) throws {
        XCTAssertFalse(files.isEmpty, "\(template) writes nothing, so nothing was checked")
        for name in files {
            let path = sandbox.appendingPathComponent(name)
            guard let written = try? String(contentsOf: path, encoding: .utf8) else {
                XCTFail("\(template) did not write \(name)")
                continue
            }
            XCTAssertFalse(
                written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(template) wrote \(name) but left it empty"
            )
            // An unresolved placeholder means a prompt variable named a node
            // that produced nothing — the run "succeeds" and writes the
            // template's own syntax into the reader's file.
            XCTAssertFalse(
                written.contains("{{"),
                "\(template) left an unresolved placeholder in \(name): " + written.prefix(200)
            )
            XCTAssertTrue(
                isAcceptable(written, template: template),
                "\(template) wrote \(name), but it does not look like the job was done: "
                    + written.prefix(200)
            )
        }
    }

    private func isAcceptable(_ text: String, template: String) -> Bool { expect(text) }
}

extension Fixture {

    /// A document with facts specific enough that a summary of something else
    /// could not pass by accident.
    static let report = """
        Quarterly Review — Bridgeport Water Authority

        Reservoir levels closed the quarter at 61 percent of capacity, down from
        74 percent a year ago. The Eastfield treatment plant ran at reduced
        output for eleven days in August after a pump failure.

        Households in the Northgate district were asked to limit outdoor use for
        three weeks. Compliance was measured at 82 percent.

        The board asks every department head to submit a revised drought
        contingency plan before the end of October.
        """

    static func plan(for template: String) -> Fixture? {
        switch template {
        case "Summarise a document":
            // Not a keyword match: a model may word a summary any number of
            // ways. What is checked is that it wrote something substantial.
            return Fixture(input: report, expect: { $0.count > 80 })

        case "Pull fields out of a document":
            return Fixture(
                input: """
                    INVOICE 4471
                    Vendor: Halloway Print Works
                    Date: 2026-02-11
                    Total: 348.20 USD
                    """,
                // A tab-separated row, so the separator is the thing to check:
                // a model that answered in prose fails here.
                expect: { $0.contains("\t") }
            )

        case "Sort a note by urgency":
            return Fixture(
                input: """
                    The boiler in the east stairwell is leaking onto the landing
                    and the caretaker cannot reach the shutoff. Water is now
                    reaching the electrical riser.
                    """,
                expect: { $0.count > 20 }
            )

        default:
            // Everything else needs a capability this suite does not have: a
            // microphone, a camera roll, the clipboard, a notification centre,
            // or the network. Those are covered by
            // WorkflowTemplateValidationTests only, which is a weaker claim and
            // is why this list should shrink.
            return nil
        }
    }
}
