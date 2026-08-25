//
//  ChatSystemPromptTests.swift
//  RunAnywhereAITests
//
//  The tool document used to be passed as the whole system prompt, which
//  replaced the model's identity with a page about `web_research`. These pin
//  the rule: one assistant instruction always, the tool contract added to it
//  when tools are on, never instead of it.
//

import XCTest
@testable import RunAnywhereAI

@MainActor
final class ChatSystemPromptTests: XCTestCase {
    func testToolsOffIsTheAssistantInstructionAlone() {
        XCTAssertEqual(
            ChatViewModel.systemPrompt(toolsEnabled: false),
            ChatViewModel.assistantPrompt
        )
    }

    func testToolsOnKeepsTheAssistantInstructionAndAddsTheToolContract() {
        let combined = ChatViewModel.systemPrompt(toolsEnabled: true)
        XCTAssertTrue(
            combined.hasPrefix(ChatViewModel.assistantPrompt),
            "the tool contract replaced the assistant instruction instead of following it"
        )
        XCTAssertTrue(combined.contains(ChatTools.skill))
        XCTAssertGreaterThan(combined.count, ChatViewModel.assistantPrompt.count)
    }

    func testThinkingOnAddsTheReasoningNudgeAndNothingElse() {
        let plain = ChatViewModel.systemPrompt(toolsEnabled: false, thinkingEnabled: false)
        let thinking = ChatViewModel.systemPrompt(toolsEnabled: false, thinkingEnabled: true)
        XCTAssertTrue(thinking.hasPrefix(plain))
        XCTAssertTrue(thinking.contains(ChatViewModel.reasoningClause))
        XCTAssertFalse(plain.contains(ChatViewModel.reasoningClause))
    }

    func testToolsAndThinkingTogetherKeepBoth() {
        let both = ChatViewModel.systemPrompt(toolsEnabled: true, thinkingEnabled: true)
        XCTAssertTrue(both.hasPrefix(ChatViewModel.assistantPrompt))
        XCTAssertTrue(both.contains(ChatViewModel.reasoningClause))
        XCTAssertTrue(both.contains(ChatTools.skill))
    }

    /// The instruction is what the model reads first, so an empty or
    /// placeholder-length one is worth catching here rather than in a chat.
    func testTheAssistantInstructionSaysSomething() {
        let prompt = ChatViewModel.assistantPrompt
        XCTAssertFalse(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertGreaterThan(prompt.count, 40)
        // An instruction that forbids reasoning fights the thinking toggle: it
        // stopped reasoning arriving at all and made a small model answer
        // arithmetic wrong rather than work it through.
        XCTAssertFalse(
            prompt.lowercased().contains("do not explain your reasoning"),
            "this wording fights the thinking toggle"
        )
    }
}
