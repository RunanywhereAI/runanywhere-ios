import SwiftUI

struct ChatBindings: ViewModifier {
    let composer: ChatComposerModel
    let chat: ChatViewModel
    let dictation: DictationController
    let conversations: ConversationStore
    @Binding var selection: String
    let tab: SideNavTab
    let defaults: DefaultModels
    let store: ModelStore

    func body(content: Content) -> some View {
        content
            .task { await defaults.warmUp() }
            .onChange(of: composer.toolsEnabled) { _, value in chat.toolsEnabled = value }
            .onChange(of: composer.thinkingEnabled) { _, value in chat.thinkingEnabled = value }
            .onChange(of: chat.isGenerating) { _, value in composer.isGenerating = value }
            .onChange(of: chat.isStopping) { _, value in composer.isStopping = value }
            .onChange(of: chat.turns) { _, turns in
                persist(turns)
                composer.isConversationEmpty = chat.isEmpty
            }
            .onChange(of: chat.isEmpty, initial: true) { _, empty in
                composer.isConversationEmpty = empty
            }
            .onChange(of: chat.indexState) { _, state in composer.indexState = state }
            .onChange(of: chat.toolsUnavailable) { _, message in
                composer.toolsUnavailableMessage = message
            }
            .onChange(of: selection) { _, value in open(value) }
            .onChange(of: dictation.lastError) { _, message in
                guard let message else { return }
                composer.noticeKind = .dictation
                composer.notice = message
            }
    }

    private func persist(_ turns: [ChatTurn]) {
        let id = conversations.currentID ?? conversations.createConversation().id
        selection = id
        conversations.update(id: id, turns: turns)
    }

    private func open(_ id: String) {
        guard !id.isEmpty, tab == .chat, conversations.currentID != id else { return }
        conversations.select(id)
        withAnimation(.easeInOut(duration: 0.2)) {
            chat.adopt(conversations.turns(for: id))
        }
    }
}
