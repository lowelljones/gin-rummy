import SwiftUI

struct GameChatSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    private static let emptyCursorIso = "1970-01-01T00:00:00.000Z"

    let gameId: String
    @Binding var messages: [GameChatMessageDTO]
    @Binding var chatWatermarkIso: String?
    @Binding var composeError: String?

    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let composeError, !composeError.isEmpty {
                    Text(composeError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { m in
                                GameChatBubble(message: m)
                                    .id(m.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
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
            }
            .task { await refresh() }
        }
    }

    private func refresh() async {
        guard let token = app.accessToken else { return }
        await MainActor.run { composeError = nil }
        do {
            let r = try await app.api.fetchGameChat(gameId: gameId, token: token, after: nil)
            await MainActor.run {
                messages = r.messages.sorted { $0.createdAt < $1.createdAt }
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
}

private struct GameChatBubble: View {
    let message: GameChatMessageDTO

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
            if !message.fromSelf { Spacer(minLength: 40) }
        }
    }
}
