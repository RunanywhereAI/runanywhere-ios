import SwiftUI
import RunAnywhere
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct HomeScreen: View {
    let store: ModelStore

    #if os(macOS)
    @State private var isNavOpen = true
    #else
    @State private var isNavOpen = false
    #endif
    @State private var selection = ""
    @Binding var tab: SideNavTab
    @State private var moreDestination: MoreDestination?
    @State private var isConnectOpen = false
    @State private var modelState: ModelState = .none
    @State private var activeModelID: String?
    @State private var showModelPicker = false
    @State private var pickingPurpose: ModelPurpose?
    @State private var composer = ChatComposerModel()
    @State private var chat = ChatViewModel()
    @State private var dictation = DictationController()
    @State private var defaults = DefaultModels()
    @State private var conversations = ConversationStore()
    @State private var workflowEditor = WorkflowEditorViewModel()
    @State private var isPickingWorkflowTemplate = false
    @Environment(AppSettings.self) private var settings
    @State private var importing: AttachmentImport?

    /// The saved-workflow library, read straight off the editor so the
    /// sidebar and the canvas can never disagree about what exists.
    private var workflows: [DrawerEntry] {
        workflowEditor.savedWorkflows.map { DrawerEntry(id: $0.id, title: $0.name) }
    }

    /// In user mode the SDK hub is gone and Connect has moved into Settings,
    /// which leaves the hub with nothing a reader would open — so the row goes
    /// too rather than leading to an empty grid.
    private var footer: [DrawerFooterItem] {
        var items = [DrawerFooterItem(id: "models", title: "Manage Models", symbol: "square.stack.3d.up")]
        if settings.mode == .developer {
            items.append(DrawerFooterItem(id: "more", title: "More", symbol: "square.grid.2x2"))
        }
        items.append(DrawerFooterItem(id: "settings", title: "Settings", symbol: "gearshape.fill"))
        return items
    }

    var body: some View {
        SideNav(
            isOpen: $isNavOpen,
            chats: chatEntries,
            workflows: workflows,
            footer: footer,
            selection: $selection,
            tab: $tab,
            onNew: { tab == .workflow ? pickWorkflowTemplate() : newConversation() },
            onDelete: { id in
                if tab == .workflow {
                    Task { await workflowEditor.delete(id: id) }
                } else {
                    conversations.delete(id: id)
                }
            },
            onRename: { id, title in
                if tab == .workflow {
                    // Renaming the open workflow is a save; the editor owns
                    // the name and there is no rename-in-place verb.
                    guard id == workflowEditor.workflowID else { return }
                    workflowEditor.workflowName = title
                    Task { await workflowEditor.save() }
                } else {
                    conversations.rename(id: id, to: title)
                }
            },
            onFooter: openFooter
        ) {
            screen
                .id(tab)
                .transition(.opacity)
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .task(id: tab) {
            guard tab == .workflow else { return }
            await workflowEditor.refreshLibrary()
            selection = workflowEditor.workflowID
        }
        .onChange(of: selection) { _, id in
            guard !id.isEmpty else { return }
            if tab == .workflow {
                // Guard against reloading the open one, or an in-flight edit
                // is thrown away on every redraw.
                guard id != workflowEditor.workflowID else { return }
                Task { await workflowEditor.load(id: id) }
            } else if tab != .chat {
                // Picking a conversation from a footer destination is how the
                // reader gets back to chat; `ChatBindings` is not mounted yet,
                // so the transcript is adopted here rather than by its watcher.
                openConversation(id)
            }
        }
        .workflowTemplatePicker(isPresented: $isPickingWorkflowTemplate, onPick: newWorkflow)
        .fileImporter(
            isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
            allowedContentTypes: importing == .image ? AttachmentLoader.imageTypes : AttachmentLoader.documentTypes,
            allowsMultipleSelection: false
        ) { result in
            importing = nil
            handleImport(result)
        }
        .modelPicker(
            isPresented: Binding(get: { pickingPurpose != nil }, set: { if !$0 { pickingPurpose = nil } }),
            models: purposeCandidates,
            activeID: nil,
            onSelect: assignPurposeModel,
            onManage: { withAnimation(.easeInOut(duration: 0.2)) { tab = .models } }
        )
    }

    // MARK: - Screens

    @ViewBuilder
    private var screen: some View {
        switch tab {
        case .chat: chatScreen
        case .workflow: workflowScreen
        case .models: modelsScreen
        case .more: moreScreen
        case .settings: settingsScreen
        }
    }

    /// Chat is not drawn at all until something can hold a conversation; until
    /// then the download gate has the screen.
    @ViewBuilder
    private var chatScreen: some View {
        if store.hasChatCapableModel {
            liveChatScreen
        } else {
            Scaffold {
                TopBar(title: "Chat", leading: leading)
            } content: {
                ChatFirstRunView(
                    store: store,
                    shortlist: store.chatShortlist,
                    onReady: adoptDownloaded,
                    onBrowseModels: { withAnimation(.easeInOut(duration: 0.2)) { tab = .models } }
                )
            }
        }
    }

    private var liveChatScreen: some View {
        Scaffold {
            chatTopBar
        } content: {
            chatBody
        } bottomBar: {
            ChatComposer(
                model: composer,
                recording: recordingState,
                onAction: handleComposerAction,
                onSend: send
            )
        }
        .modifier(ChatBindings(
            composer: composer,
            chat: chat,
            dictation: dictation,
            conversations: conversations,
            selection: $selection,
            tab: tab,
            defaults: defaults,
            store: store
        ))
        .onChange(of: store.models.count) { _, _ in syncCapabilities() }
        .onChange(of: store.loadedLanguageModel) { _, model in adoptLoaded(model) }
        .task { adoptLoaded(store.loadedLanguageModel) }
    }

    private var chatTopBar: some View {
        TopBar(
            leading: leading,
            center: AnyView(modelBadge),
            trailing: AnyView(BarButton(systemImage: "square.and.pencil", action: newConversation))
        )
    }

    @ViewBuilder
    private var chatBody: some View {
        if chat.isEmpty {
            ChatWelcome()
        } else {
            ChatTranscript(
                turns: chat.visibleTurns,
                streamingID: chat.draft?.id,
                speakingID: chat.speakingTurnID,
                speakingProgress: chat.speakingProgress,
                onAction: handleTurnAction
            )
        }
    }

    /// The node-graph editor is a pointer-and-keyboard tool, so it ships on Mac
    /// only; `SideNavTab.libraries` already keeps the tab off iOS, which leaves
    /// the other branch unreachable rather than merely unused.
    @ViewBuilder
    private var workflowScreen: some View {
        #if os(macOS)
        WorkflowScreen(viewModel: workflowEditor)
        #else
        Scaffold {
            TopBar(title: "Workflow", leading: leading)
        } content: {
            EmptyState(
                symbol: "point.3.filled.connected.trianglepath.dotted",
                title: "Workflows run on Mac",
                detail: "The graph editor needs a pointer and a keyboard."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #endif
    }

    private var modelsScreen: some View {
        Scaffold {
            TopBar(
                title: "Manage Models",
                leading: leading,
                trailing: AnyView(
                    BarButton(systemImage: "arrow.clockwise", tint: AppColors.textSecondary) {
                        Task { await store.refresh() }
                    }
                )
            )
        } content: {
            ManageModelsView(store: store)
        }
    }

    private var moreScreen: some View {
        Scaffold {
            TopBar(title: moreDestination?.title ?? "More", leading: moreLeading)
        } content: {
            MoreHost(destination: $moreDestination)
        }
    }

    /// Inside a destination the leading slot is a way back to the hub; on the
    /// hub itself it is whatever the sidebar normally puts there.
    private var moreLeading: AnyView? {
        guard moreDestination != nil else { return leading }
        return AnyView(
            BarButton(systemImage: "chevron.left") {
                withAnimation(.easeOut(duration: 0.2)) { moreDestination = nil }
            }
        )
    }

    /// Connect is pushed from Settings rather than living in the More hub: it
    /// is the one non-chat screen a reader would go looking for, and Settings
    /// is the only place both modes can reach.
    private var settingsScreen: some View {
        Scaffold {
            TopBar(title: isConnectOpen ? "Connect" : "Settings", leading: settingsLeading)
        } content: {
            settingsContent
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        #if os(macOS)
        if isConnectOpen {
            ConnectScreen()
        } else {
            settingsForm
        }
        #else
        settingsForm
        #endif
    }

    private var settingsForm: some View {
        SettingsScreen(
            settings: settings,
            defaults: defaults,
            store: store,
            onManageModels: { withAnimation(Motion.fade) { tab = .models } },
            onOpenConnect: { withAnimation(Motion.quick) { isConnectOpen = true } },
            onOpenDeveloperTools: {
                withAnimation(Motion.fade) {
                    moreDestination = nil
                    tab = .more
                }
            }
        )
    }

    private var settingsLeading: AnyView? {
        guard isConnectOpen else { return leading }
        return AnyView(
            BarButton(systemImage: "chevron.left") {
                withAnimation(Motion.quick) { isConnectOpen = false }
            }
        )
    }

    // MARK: - Model badge

    private var modelBadge: some View {
        ModelBadge(
            state: modelState,
            style: .quiet,
            showsBackend: settings.mode == .developer
        ) { showModelPicker.toggle() }
            .modelPicker(
                isPresented: $showModelPicker,
                models: store.installed.filter { $0.purpose == .language || $0.purpose == .vision },
                activeID: activeModelID,
                onSelect: select,
                onManage: { withAnimation(.easeInOut(duration: 0.2)) { tab = .models } }
            )
    }

    private func select(_ model: InstalledModel) {
        activeModelID = model.id
        defaults.llmID = model.id
        applyCapabilities(of: model)
        withAnimation(.easeInOut(duration: 0.2)) { modelState = .loading(model.label, 0.1) }
        Task {
            do {
                try await store.load(model.id)
                withAnimation(.easeInOut(duration: 0.25)) {
                    modelState = .loaded(model.label, model.backend)
                }
                chat.loadedModelName = model.label
            } catch {
                withAnimation(.easeInOut(duration: 0.25)) { modelState = .none }
            }
        }
    }

    /// A model the reader just downloaded from the first-run gate is the one
    /// they want to talk to, so it is selected and loaded rather than left for
    /// them to find in the picker.
    private func adoptDownloaded(_ id: String) {
        guard let model = store.models.first(where: { $0.id == id }) else { return }
        select(model)
    }

    private func adoptLoaded(_ model: InstalledModel?) {
        guard let model, activeModelID == nil else { return }
        activeModelID = model.id
        applyCapabilities(of: model)
        withAnimation(.easeInOut(duration: 0.2)) {
            modelState = .loaded(model.label, model.backend)
        }
    }

    private func syncCapabilities() {
        guard let activeModelID,
              let model = store.models.first(where: { $0.id == activeModelID }) else {
            composer.thinkingSupported = false
            composer.hasModel = false
            composer.toolsSupported = false
            chat.modelIsVision = false
            return
        }
        applyCapabilities(of: model)
    }

    private func applyCapabilities(of model: InstalledModel) {
        withAnimation(.easeInOut(duration: 0.2)) {
            let isVision = model.purpose == .vision
            // A vision model answers through the VLM component, and reasoning
            // has no carrier there: rac_vlm_options_t has no thinking field and
            // the adapter never reads ReasoningOptions, so the toggle would be
            // a control that does nothing. Hide it rather than lie about it.
            composer.thinkingSupported = model.supportsThinking && !isVision
            chat.modelContextLength = model.contextLength
            chat.modelBackend = model.backend
            chat.modelIsVision = isVision
            chat.loadedModelID = model.id
            composer.hasModel = true
            composer.toolsSupported = model.supportsTools
            if !model.supportsTools {
                composer.toolsEnabled = false
                chat.toolsEnabled = false
            }
            if !composer.thinkingSupported {
                composer.thinkingEnabled = false
                chat.thinkingEnabled = false
            }
        }
    }

    // MARK: - Conversations

    private var chatEntries: [DrawerEntry] {
        conversations.conversations.map { DrawerEntry(id: $0.id, title: $0.title) }
    }

    private func pickWorkflowTemplate() {
        isPickingWorkflowTemplate = true
    }

    private func newWorkflow(from template: WorkflowTemplate?) {
        withAnimation(Motion.quick) {
            workflowEditor.newWorkflow(from: template)
            selection = workflowEditor.workflowID
        }
    }

    private func openConversation(_ id: String) {
        conversations.select(id)
        withAnimation(.easeInOut(duration: 0.2)) {
            chat.adopt(conversations.turns(for: id))
            tab = .chat
        }
    }

    private func newConversation() {
        let conversation = conversations.createConversation()
        selection = conversation.id
        withAnimation(.easeOut(duration: 0.2)) {
            chat.newConversation()
            tab = .chat
        }
    }

    private func openFooter(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch id {
            case "settings": tab = .settings
            case "models": tab = .models
            case "more":
                // Always land on the hub rather than whatever was open last;
                // a footer item that reopens a sub-screen reads as broken.
                moreDestination = nil
                tab = .more
            default: tab = .models
            }
        }
    }

    // MARK: - Composer

    private func send() {
        if chat.isGenerating {
            chat.stop()
            return
        }
        guard let reason = sendBlocker() else {
            let text = composer.draft
            let staged = composer.staged
            if staged?.isImage == true, let visionID = defaults.resolveVision(from: store.installed) {
                Task {
                    guard await defaults.prepareVision(visionID) else {
                        composer.notice = "That vision model would not load."
                        return
                    }
                    dispatchSend(text: text, staged: staged)
                }
                composer.draft = ""
                composer.staged = nil
                return
            }
            chat.attachment = composer.staged
            chat.embeddingModelID = defaults.resolveEmbedding(from: store.installed)
            composer.draft = ""
            composer.staged = nil
            composer.notice = nil
            chat.send(text)
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            composer.noticeKind = composer.staged == nil ? .general : .attachment
            composer.notice = reason
        }
    }

    private func dispatchSend(text: String, staged: ChatAttachment?) {
        chat.attachment = staged
        chat.embeddingModelID = defaults.resolveEmbedding(from: store.installed)
        composer.notice = nil
        chat.send(text)
    }

    /// Everything that must be true before a turn is worth starting, checked
    /// here rather than left to fail inside the SDK as a native error.
    private func sendBlocker() -> String? {
        guard activeModelID != nil, composer.hasModel else {
            return "Choose a model at the top of the screen before sending."
        }
        if let staged = composer.staged {
            if staged.isImage {
                guard let visionID = defaults.resolveVision(from: store.installed) else {
                    return "Asking about an image needs a vision model. Pick one in Settings, or download one in Manage Models."
                }
                let name = store.models.first { $0.id == visionID }?.name ?? visionID
                if let blocked = VisionCompatibility.blockReason(for: visionID, name: name) {
                    return blocked
                }
            } else {
                guard defaults.resolveEmbedding(from: store.installed) != nil else {
                    return "Asking about a document needs an embedding model. Pick one in Settings, or download one in Manage Models."
                }
            }
        }
        return nil
    }

    private var recordingState: RecordingState? {
        guard dictation.isListening else { return nil }
        return RecordingState(
            levels: dictation.levels,
            isPaused: dictation.isPaused,
            elapsed: dictation.elapsed,
            transcript: dictation.partial,
            diagnostics: settings.mode == .developer
                ? "\(dictation.chunks) chunks · \(dictation.bytes / 1024) KB · \(dictation.eventsSeen) events"
                : "",
            onPauseResume: { dictation.togglePause() },
            onDiscard: { withAnimation(.easeOut(duration: 0.2)) { dictation.discard() } },
            onFinish: { withAnimation(.easeOut(duration: 0.2)) { dictation.finish() } }
        )
    }

    private func handleComposerAction(_ action: ComposerAction) {
        switch action {
        case .talk:
            startDictation()
        case .attachDocument:
            importing = .document
        case .attachImage:
            importing = .image
        case .liveCamera, .resolveBlocked, .chooseModel:
            break
        }
    }

    private func startDictation() {
        guard let id = defaults.resolveSTT(from: store.installed) else {
            pickingPurpose = .speechToText
            return
        }
        composer.notice = nil
        Task {
            guard await defaults.prepareSTT(id) else {
                composer.notice = defaults.lastError
                    ?? "That speech model would not load. Try another one in Settings."
                return
            }
            withAnimation(.easeOut(duration: 0.2)) {
                dictation.start { text in
                    composer.draft = composer.draft.isEmpty ? text : composer.draft + " " + text
                }
            }
        }
    }

    // MARK: - Turn actions

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result {
                composer.notice = error.localizedDescription
            }
            return
        }
        Task {
            do {
                // Off the main actor: PDF parsing and a multi-megabyte decode
                // block the window long enough to be felt.
                let attachment = try await Task.detached(priority: .userInitiated) {
                    try await AttachmentLoader.load(from: url)
                }.value
                withAnimation(.easeInOut(duration: 0.22)) {
                    composer.staged = attachment
                    composer.indexState = .idle
                    composer.notice = nil
                }
            } catch {
                composer.noticeKind = .attachment
                composer.notice = error.localizedDescription
            }
        }
    }

    private func handleTurnAction(_ action: TurnAction, _ turn: ChatTurn) {
        switch action {
        case .copy:
            copyToPasteboard(turn.text)
        case .speak:
            speak(turn)
        case .fork:
            withAnimation(.easeInOut(duration: 0.22)) { chat.adopt(chat.fork(at: turn.id)) }
        case .retry:
            chat.retryLast()
        case .delete:
            withAnimation(.easeInOut(duration: 0.2)) { chat.delete(turn.id) }
        }
    }

    private func speak(_ turn: ChatTurn) {
        guard defaults.ttsID != nil else {
            pickingPurpose = .textToSpeech
            return
        }
        Task {
            await defaults.ensureLoaded(defaults.ttsID, category: .speechSynthesis)
            chat.speak(turn)
        }
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    // MARK: - Purpose picker

    private var purposeCandidates: [InstalledModel] {
        guard let pickingPurpose else { return [] }
        return store.installed.filter { $0.purpose == pickingPurpose }
    }

    private func assignPurposeModel(_ model: InstalledModel) {
        switch pickingPurpose {
        case .textToSpeech:
            defaults.ttsID = model.id
            Task { await defaults.ensureLoaded(model.id, category: .speechSynthesis) }
        case .speechToText:
            defaults.sttID = model.id
            Task {
                guard await defaults.prepareSTT(model.id) else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    dictation.start { text in
                        composer.draft = composer.draft.isEmpty ? text : composer.draft + " " + text
                    }
                }
            }
        default:
            break
        }
    }

    private var leading: AnyView? {
        #if os(macOS)
        nil
        #else
        AnyView(BarButton(systemImage: "line.3.horizontal") { isNavOpen = true })
        #endif
    }
}
