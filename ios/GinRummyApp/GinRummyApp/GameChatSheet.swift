import SwiftUI

struct GameChatSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    private static let emptyCursorIso = "1970-01-01T00:00:00.000Z"

    let gameId: String
    let opponentDisplayName: String
    @Binding var opponentUserId: String?
    @Binding var messages: [GameChatMessageDTO]
    @Binding var chatWatermarkIso: String?
    @Binding var composeError: String?

    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool
    @State private var reportTarget: GameChatMessageDTO?
    @State private var blockTarget: GameChatMessageDTO?
    @State private var actionFeedback = ""
    @State private var actionFeedbackIsError = false
    @State private var unblockBusy = false

    private var visibleMessages: [GameChatMessageDTO] {
        messages.filter { !app.isBlocked($0.userId) }
    }

    private var blockedOpponentName: String {
        if let id = opponentUserId,
           let name = messages.first(where: { $0.userId == id })?.displayName,
           !name.isEmpty {
            return name
        }
        return opponentDisplayName
    }

    private var isOpponentBlocked: Bool {
        guard let id = opponentUserId else { return false }
        return app.isBlocked(id)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !actionFeedback.isEmpty {
                    FeedbackLine(text: actionFeedback, isError: actionFeedbackIsError, privateClubStyle: false)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                if let composeError, !composeError.isEmpty {
                    Text(composeError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }
                if isOpponentBlocked {
                    blockedOpponentBanner
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(visibleMessages) { m in
                                GameChatBubble(message: m) {
                                    reportTarget = m
                                } onBlock: {
                                    blockTarget = m
                                }
                                .id(m.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: visibleMessages.count) { _, _ in
                        if let last = visibleMessages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .focused($fieldFocused)
                    Button("Send") { Task { await send() } }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if isOpponentBlocked {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("\(blockedOpponentName) is blocked") {}
                                .disabled(true)
                            Button("Unblock") {
                                Task { await submitUnblock() }
                            }
                            .disabled(unblockBusy)
                        } label: {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(.secondary)
                        }
                        .disabled(unblockBusy)
                    }
                }
            }
            .task {
                await resolveOpponentUserIdIfNeeded()
                await refresh()
            }
            .onChange(of: messages) { _, msgs in
                noteOpponentUserId(from: msgs)
            }
            .confirmationDialog(
                "Report this message?",
                isPresented: Binding(
                    get: { reportTarget != nil },
                    set: { if !$0 { reportTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Harassment or bullying") {
                    Task { await submitReport(reason: "harassment") }
                }
                Button("Hate speech") {
                    Task { await submitReport(reason: "hate") }
                }
                Button("Spam") {
                    Task { await submitReport(reason: "spam") }
                }
                Button("Inappropriate content") {
                    Task { await submitReport(reason: "inappropriate") }
                }
                Button("Other") {
                    Task { await submitReport(reason: "other") }
                }
                Button("Cancel", role: .cancel) {
                    reportTarget = nil
                }
            } message: {
                if let target = reportTarget {
                    Text("We review reports within 24 hours. Message from \(target.displayName): \"\(target.body)\"")
                }
            }
            .confirmationDialog(
                blockTarget.map { "Block \($0.displayName)?" } ?? "Block player?",
                isPresented: Binding(
                    get: { blockTarget != nil },
                    set: { if !$0 { blockTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Block", role: .destructive) {
                    Task { await submitBlock() }
                }
                Button("Cancel", role: .cancel) {
                    blockTarget = nil
                }
            } message: {
                Text("You won't see their chat messages anymore. You can unblock them later in Account settings.")
            }
        }
    }

    private var blockedOpponentBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(blockedOpponentName) is blocked")
                    .font(.subheadline.weight(.semibold))
                Text("You won't see their messages. The game continues as normal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(unblockBusy ? "Unblocking…" : "Unblock") {
                Task { await submitUnblock() }
            }
            .buttonStyle(.bordered)
            .disabled(unblockBusy)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.06))
    }

    private func noteOpponentUserId(from msgs: [GameChatMessageDTO]) {
        guard opponentUserId == nil,
              let id = msgs.first(where: { !$0.fromSelf })?.userId else { return }
        opponentUserId = id
    }

    private func resolveOpponentUserIdIfNeeded() async {
        noteOpponentUserId(from: messages)
        guard opponentUserId == nil, let token = app.accessToken else { return }
        do {
            let r = try await app.api.fetchBlockedUsers(token: token)
            if let match = r.users.first(where: { $0.displayName == opponentDisplayName }) {
                opponentUserId = match.userId
            }
        } catch {}
    }

    private func refresh() async {
        guard let token = app.accessToken else { return }
        await MainActor.run { composeError = nil }
        do {
            let r = try await app.api.fetchGameChat(gameId: gameId, token: token, after: nil)
            await MainActor.run {
                messages = r.messages.sorted { $0.createdAt < $1.createdAt }
                noteOpponentUserId(from: messages)
                chatWatermarkIso = messages.map(\.createdAt).max() ?? Self.emptyCursorIso
            }
        } catch {
            await MainActor.run {
                composeError = UserFeedback.from(error)
            }
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let token = app.accessToken else { return }
        await MainActor.run { composeError = nil }
        do {
            let r = try await app.api.sendGameChat(gameId: gameId, token: token, text: text)
            await MainActor.run {
                draft = ""
                if !messages.contains(where: { $0.id == r.message.id }) {
                    messages.append(r.message)
                    messages.sort { $0.createdAt < $1.createdAt }
                }
                chatWatermarkIso = messages.map(\.createdAt).max() ?? Self.emptyCursorIso
            }
        } catch {
            await MainActor.run {
                if case APIError.badStatus(let code, let body) = error {
                    if code == 429 {
                        composeError = "Slow down — try again in a moment."
                    } else if code == 400,
                              body.contains("moderation_rejected") || body.contains("not allowed") || body.contains("too long") {
                        composeError = "That message wasn't sent. Try different wording."
                    } else {
                        composeError = UserFeedback.from(error)
                    }
                } else {
                    composeError = UserFeedback.from(error)
                }
            }
        }
    }

    private func submitReport(reason: String) async {
        guard let target = reportTarget, let token = app.accessToken else { return }
        defer { Task { @MainActor in reportTarget = nil } }
        await MainActor.run {
            actionFeedback = ""
            actionFeedbackIsError = false
        }
        do {
            _ = try await app.api.reportChatMessage(
                gameId: gameId,
                messageId: target.id,
                token: token,
                reason: reason
            )
            await MainActor.run {
                actionFeedback = "Report submitted. We'll review it within 24 hours."
                actionFeedbackIsError = false
            }
        } catch {
            await MainActor.run {
                actionFeedback = UserFeedback.from(error)
                actionFeedbackIsError = true
            }
        }
    }

    private func submitBlock() async {
        guard let target = blockTarget else { return }
        defer { Task { @MainActor in blockTarget = nil } }
        await MainActor.run {
            actionFeedback = ""
            actionFeedbackIsError = false
        }
        do {
            try await app.blockUser(target.userId)
            await MainActor.run {
                opponentUserId = target.userId
                actionFeedback = "\(target.displayName) is blocked."
                actionFeedbackIsError = false
            }
        } catch {
            await MainActor.run {
                actionFeedback = UserFeedback.from(error)
                actionFeedbackIsError = true
            }
        }
    }

    private func submitUnblock() async {
        guard let id = opponentUserId else { return }
        unblockBusy = true
        defer { Task { @MainActor in unblockBusy = false } }
        await MainActor.run {
            actionFeedback = ""
            actionFeedbackIsError = false
        }
        do {
            try await app.unblockUser(id)
            await refresh()
            await MainActor.run {
                actionFeedback = "\(blockedOpponentName) unblocked."
                actionFeedbackIsError = false
            }
        } catch {
            await MainActor.run {
                actionFeedback = UserFeedback.from(error)
                actionFeedbackIsError = true
            }
        }
    }
}

private struct GameChatBubble: View {
    let message: GameChatMessageDTO
    let onReport: () -> Void
    let onBlock: () -> Void

    var body: some View {
        HStack {
            if message.fromSelf { Spacer(minLength: 40) }
            VStack(alignment: message.fromSelf ? .trailing : .leading, spacing: 4) {
                Text(message.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .padding(10)
            .background(
                message.fromSelf ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contextMenu {
                if !message.fromSelf {
                    Button("Report Message", systemImage: "exclamationmark.bubble") {
                        onReport()
                    }
                    Button("Block \(message.displayName)", systemImage: "hand.raised") {
                        onBlock()
                    }
                }
            }
            if !message.fromSelf { Spacer(minLength: 40) }
        }
    }
}
