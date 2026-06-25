import Foundation

/// Supabase Realtime client for `player_game_snapshots` postgres_changes.
///
/// Subscribes to the caller's RLS-filtered row and delivers a ready-to-render
/// `GameStateResponse` on each UPDATE — no `/games/:id/state` pull per move.
/// Uses `URLSessionWebSocketTask` (no SDK), matching the app's raw-REST auth.
@MainActor
final class GameSignalSocket {
    static var isConfigured: Bool {
        !AppConfig.supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !AppConfig.supabaseAnonKey.isEmpty
    }

    private let gameId: String
    private let accessToken: String
    private let onSnapshot: (GameStateResponse) -> Void

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var refCounter = 0
    private var closed = false

    init(gameId: String, accessToken: String, onSnapshot: @escaping (GameStateResponse) -> Void) {
        self.gameId = gameId
        self.accessToken = accessToken
        self.onSnapshot = onSnapshot
    }

    func connect() {
        guard !closed, task == nil, let url = Self.socketURL() else { return }
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.task = task
        task.resume()
        joinChannel()
        receiveNext()
        startHeartbeat()
    }

    func disconnect() {
        closed = true
        heartbeatTask?.cancel(); heartbeatTask = nil
        reconnectTask?.cancel(); reconnectTask = nil
        task?.cancel(with: .goingAway, reason: nil); task = nil
        session?.invalidateAndCancel(); session = nil
    }

    // MARK: - Phoenix / Supabase Realtime

    private static func socketURL() -> URL? {
        guard isConfigured else { return nil }
        var base = AppConfig.supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasPrefix("https://") {
            base = "wss://" + base.dropFirst("https://".count)
        } else if base.hasPrefix("http://") {
            base = "ws://" + base.dropFirst("http://".count)
        } else {
            base = "wss://" + base
        }
        let key = AppConfig.supabaseAnonKey
        return URL(string: "\(base)/realtime/v1/websocket?apikey=\(key)&vsn=1.0.0")
    }

    private func nextRef() -> String {
        refCounter += 1
        return String(refCounter)
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }

    private func joinChannel() {
        sendJSON([
            "topic": "realtime:public:player_game_snapshots",
            "event": "phx_join",
            "payload": [
                "config": [
                    "broadcast": ["self": false],
                    "presence": ["key": ""],
                    "postgres_changes": [[
                        "event": "*",
                        "schema": "public",
                        "table": "player_game_snapshots",
                        "filter": "game_id=eq.\(gameId)",
                    ]],
                ],
                "access_token": accessToken,
            ],
            "ref": nextRef(),
        ])
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard let self, !self.closed else { return }
                self.sendJSON(["topic": "phoenix", "event": "heartbeat", "payload": [:], "ref": self.nextRef()])
            }
        }
    }

    private func receiveNext() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                switch result {
                case .failure:
                    self.scheduleReconnect()
                case .success(let message):
                    switch message {
                    case .string(let text): self.handle(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) { self.handle(text) }
                    @unknown default: break
                    }
                    self.receiveNext()
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["event"] as? String) == "postgres_changes",
              let payload = obj["payload"] as? [String: Any] else { return }

        let inner = (payload["data"] as? [String: Any]) ?? payload
        let record = (inner["record"] as? [String: Any])
            ?? (inner["new"] as? [String: Any])
        guard let record,
              let recordData = try? JSONSerialization.data(withJSONObject: record),
              let dto = try? JSONDecoder().decode(PlayerGameSnapshotDTO.self, from: recordData) else { return }

        onSnapshot(dto.asGameStateResponse())
    }

    private func scheduleReconnect() {
        guard !closed else { return }
        heartbeatTask?.cancel(); heartbeatTask = nil
        task = nil
        session?.invalidateAndCancel(); session = nil
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !self.closed else { return }
            self.connect()
        }
    }
}
