//
//  WorkflowTemplateFixture.swift
//  RunAnywhereAITests
//
//  What each template needs before it can run, and what it has to leave behind.
//

import Foundation
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

    struct Wrong: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// Everything here throws rather than asserting, so a failure travels back
    /// to the one place that also prints the trace explaining it.
    func verify(files: [String], in sandbox: URL, template: String) throws {
        guard !files.isEmpty else { throw Wrong("writes nothing, so nothing was checked") }

        // A template that branches writes one file, not all of them: "Sort a
        // note by urgency" sends the note down the urgent path or the later
        // path, never both. So what is required is that a run wrote something,
        // and that whatever it wrote is sound — demanding every declared output
        // would fail every workflow with a condition in it.
        let present = files.filter {
            FileManager.default.fileExists(atPath: sandbox.appendingPathComponent($0).path)
        }
        guard !present.isEmpty else {
            throw Wrong("wrote none of the files it declares: \(files.joined(separator: ", "))")
        }

        for name in present {
            let path = sandbox.appendingPathComponent(name)
            guard let written = try? String(contentsOf: path, encoding: .utf8) else {
                throw Wrong("could not read back \(name)")
            }
            guard !written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Wrong("wrote \(name) but left it empty")
            }
            // An unresolved placeholder means a prompt variable named a node
            // that produced nothing — the run "succeeds" and writes the
            // template's own syntax into the reader's file.
            guard !written.contains("{{") else {
                throw Wrong("left an unresolved placeholder in \(name): \(written.prefix(120))")
            }
            guard expect(written) else {
                throw Wrong("wrote \(name), but it does not look like the job was done: "
                    + written.prefix(120))
            }
        }
    }

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
