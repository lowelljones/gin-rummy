import SwiftUI

/// In-person score sheet: tap a cell, enter score; hands auto-fill the other side with 0 and advance.
struct ManualScorecardView: View {
    @StateObject private var store = ManualScoreStore()

    @FocusState private var focusedField: FocusField?
    @State private var editText: String = ""
    @State private var showResetConfirm = false
    @State private var showNameEditor = false
    @State private var draftWeName = ""
    @State private var draftTheyName = ""

    private let contentInset: CGFloat = 16
    private let minDisplayGameColumns = 4
    private let cellPaddingH: CGFloat = 6

    private struct DisplayColumn: Identifiable {
        let id: Int
        let game: ManualScoreGame?
        var isPlaceholder: Bool { game == nil }
        var title: String { "Game \((game?.number ?? id + 1))" }
        var isLive: Bool { game?.isLive ?? false }
    }

    enum FocusField: Hashable {
        case hand(gameId: UUID, handId: UUID, side: Side)
        case box(gameId: UUID, side: Side)

        enum Side: String { case we, they }

        var allowsNegative: Bool {
            if case .box = self { return true }
            return false
        }
    }

    var body: some View {
        scorecardLayout
            .navigationTitle("Score a game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit player names") {
                        draftWeName = store.session.weName
                        draftTheyName = store.session.theyName
                        showNameEditor = true
                    }
                    Button("New game") { store.addGame() }
                    Button("Reset sheet", role: .destructive) { showResetConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(GinRummyPalette.gold)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                if let field = focusedField {
                    Text(editingPrompt)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GinRummyPalette.sage)
                    Spacer()
                    Button("Next") {
                        advanceFrom(field)
                    }
                    .foregroundStyle(GinRummyPalette.gold)
                } else {
                    Spacer()
                }
                Button("Done") {
                    finishEditing()
                }
                .foregroundStyle(GinRummyPalette.gold)
            }
        }
        .onChange(of: focusedField) { old, new in
            // Commit the cell we just left, then load the buffer for the new one.
            if let old { commit(old, text: editText) }
            editText = new.map { editableText(for: $0) } ?? ""
        }
        .sheet(isPresented: $showNameEditor) {
            nameEditorSheet
        }
        .alert("Reset this score sheet?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { store.resetSession() }
        } message: {
            Text("Clears all games, hands, and box totals. This can't be undone.")
        }
    }

    private var scorecardLayout: some View {
        GeometryReader { geo in
            let columns = displayColumns()
            let contentWidth = max(0, geo.size.width - contentInset * 2)
            let handRows = store.maxHandRows()
            let sectionRows: CGFloat = 3 + 2 + 1 + CGFloat(handRows) + 3
            let metrics = GridMetrics(
                contentWidth: contentWidth,
                gridHeight: max(0, geo.size.height - 96),
                columnCount: columns.count,
                sectionRows: sectionRows
            )

            VStack(spacing: 0) {
                headerBlock
                    .padding(.horizontal, contentInset)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                scoreGrid(columns: columns, metrics: metrics, handRows: handRows)
                    .padding(.horizontal, contentInset)

                actionBar
                    .padding(.horizontal, contentInset)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    private var editingPrompt: String {
        guard let field = focusedField else { return "Score" }
        switch field {
        case let .hand(_, _, side):
            return side == .we ? store.session.weName : store.session.theyName
        case let .box(_, side):
            return side == .we ? "\(store.session.weName) total" : "\(store.session.theyName) total"
        }
    }

    // MARK: - Header & actions

    private var headerBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GIN RUMMY")
                    .font(GinRummyPalette.titleFont(size: 24))
                    .foregroundStyle(GinRummyPalette.cream)
                    .tracking(2.5)
                Text("\(store.session.weName) vs \(store.session.theyName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
            }
            Spacer(minLength: 8)
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(GinRummyPalette.gold)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                if let live = store.session.games.first(where: \.isLive) {
                    store.addHand(to: live.id)
                } else if let last = store.session.games.last {
                    store.addHand(to: last.id)
                }
            } label: {
                Label("Add hand", systemImage: "plus")
            }
            .buttonStyle(GinGhostButtonStyle())

            Button {
                store.addGame()
            } label: {
                Label("New game", systemImage: "square.grid.3x1.folder.fill.badge.plus")
            }
            .buttonStyle(GinPrimaryButtonStyle())
        }
    }

    // MARK: - Grid

    private func displayColumns() -> [DisplayColumn] {
        let count = max(store.session.games.count, minDisplayGameColumns)
        return (0 ..< count).map { i in
            DisplayColumn(id: i, game: i < store.session.games.count ? store.session.games[i] : nil)
        }
    }

    @ViewBuilder
    private func scoreGrid(columns: [DisplayColumn], metrics: GridMetrics, handRows: Int) -> some View {
        VStack(spacing: 0) {
            boxSection(columns: columns, metrics: metrics)
            sectionDivider
            handSection(columns: columns, metrics: metrics, handRows: handRows)
            Spacer(minLength: 0)
            sectionDivider
            totalsSection(columns: columns, metrics: metrics)
        }
        .frame(width: metrics.gridWidth, height: metrics.gridHeight, alignment: .top)
        .overlay(gridOuterBorder)
    }

    @ViewBuilder
    private func boxSection(columns: [DisplayColumn], metrics: GridMetrics) -> some View {
        let h = metrics.rowHeight
        gridRow(height: h) {
            labelCell("Players", width: metrics.labelWidth, height: h, bold: true)
            valueCell("Game Totals", width: metrics.gamesWidth, height: h, alignment: .leading, style: .muted, uppercase: true)
        }
        gridRow(height: h) {
            labelCell(store.session.weName, width: metrics.labelWidth, height: h, bold: true)
            boxStrip(side: .we, columns: columns, metrics: metrics, height: h)
        }
        gridRow(height: h) {
            labelCell(store.session.theyName, width: metrics.labelWidth, height: h, bold: true)
            boxStrip(side: .they, columns: columns, metrics: metrics, height: h)
        }
    }

    @ViewBuilder
    private func boxStrip(side: FocusField.Side, columns: [DisplayColumn], metrics: GridMetrics, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(store.session.games.enumerated()), id: \.element.id) { idx, game in
                let slotW = slotWidth(index: idx, count: store.session.games.count, totalWidth: metrics.gamesWidth)
                let display = boxText(game: game, side: side)
                numericText(display, style: scoreStyle(for: display))
                    .frame(width: slotW, height: height, alignment: .center)
                    .background(game.isLive ? liveColumnTint : nil)
                    .overlay(cellBorder(right: true))
            }
            if store.session.games.isEmpty {
                numericText("…", style: .muted)
                    .frame(width: metrics.gamesWidth, height: height, alignment: .center)
            }
        }
        .frame(width: metrics.gamesWidth, height: height)
        .overlay(cellBorder(right: true).allowsHitTesting(false))
    }

    /// Running box tally (who's up): each hand won is a box; we show the signed
    /// net so a glance tells you who leads and by how much.
    private func boxText(game: ManualScoreGame, side: FocusField.Side) -> String {
        guard game.hasScoredHand else { return game.isLive ? "…" : "—" }
        let net = side == .we ? game.netBoxes() : -game.netBoxes()
        if net > 0 { return "+\(net)" }
        if net < 0 { return "\(net)" }
        return "0"
    }

    @ViewBuilder
    private func handSection(columns: [DisplayColumn], metrics: GridMetrics, handRows: Int) -> some View {
        let h = metrics.rowHeight
        let gcw = metrics.gameColumnWidth
        let hcw = metrics.halfColumnWidth

        gridRow(height: h) {
            labelCell("", width: metrics.labelWidth, height: h)
            ForEach(Array(columns.enumerated()), id: \.element.id) { idx, col in
                gameHeaderCell(column: col, width: colW(idx, columns, gcw, metrics.gamesWidth), height: h)
            }
        }
        gridRow(height: h) {
            labelCell("", width: metrics.labelWidth, height: h)
            ForEach(Array(columns.enumerated()), id: \.element.id) { idx, col in
                let w = colW(idx, columns, gcw, metrics.gamesWidth)
                weTheyHeader(column: col, width: w, halfWidth: hcw, height: h)
            }
        }
        ForEach(0 ..< handRows, id: \.self) { row in
            gridRow(height: h) {
                labelCell(handLabel(row: row), width: metrics.labelWidth, height: h)
                ForEach(Array(columns.enumerated()), id: \.element.id) { idx, col in
                    let w = colW(idx, columns, gcw, metrics.gamesWidth)
                    if let game = col.game, row < game.hands.count {
                        let hand = game.hands[row]
                        if col.isLive {
                            weTheyEditablePair(
                                game: game,
                                hand: hand,
                                width: w,
                                halfWidth: hcw,
                                height: h
                            )
                        } else {
                            weTheyDataPair(
                                we: handCellDisplay(hand: hand, side: .we),
                                they: handCellDisplay(hand: hand, side: .they),
                                width: w,
                                halfWidth: hcw,
                                height: h,
                                live: false
                            )
                        }
                    } else {
                        emptyWeTheyPair(width: w, halfWidth: hcw, height: h)
                    }
                }
            }
        }
    }

    private func handLabel(row: Int) -> String {
        let hasMultipleHands = store.maxHandRows() > 1
        let allEmpty = store.session.games.allSatisfy { game in
            game.hands.allSatisfy { $0.wePoints == nil && $0.theyPoints == nil }
        }
        if row == 0, !hasMultipleHands, allEmpty {
            return "Hands"
        }
        return "Hand \(row + 1)"
    }

    @ViewBuilder
    private func totalsSection(columns: [DisplayColumn], metrics: GridMetrics) -> some View {
        let h = metrics.rowHeight
        let gcw = metrics.gameColumnWidth
        let hcw = metrics.halfColumnWidth
        let weNet = store.netBox(forWePlayer: true)
        let theyNet = store.netBox(forWePlayer: false)

        gridRow(height: h) {
            labelCell("Total", width: metrics.labelWidth, height: h, bold: true)
            ForEach(Array(columns.enumerated()), id: \.element.id) { idx, col in
                let w = colW(idx, columns, gcw, metrics.gamesWidth)
                if let game = col.game {
                    weTheyDataPair(
                        we: String(game.totalWe()),
                        they: String(game.totalThey()),
                        width: w,
                        halfWidth: hcw,
                        height: h,
                        live: col.isLive,
                        emphasized: true
                    )
                } else {
                    emptyWeTheyPair(width: w, halfWidth: hcw, height: h)
                }
            }
        }
        gridRow(height: h) {
            labelCell("Box", width: metrics.labelWidth, height: h, bold: true)
            ForEach(Array(columns.enumerated()), id: \.element.id) { idx, col in
                let w = colW(idx, columns, gcw, metrics.gamesWidth)
                if let game = col.game {
                    let scored = game.hasScoredHand
                    valueCell(
                        scored ? signed(game.netBoxes()) : (game.isLive ? "…" : "—"),
                        width: w,
                        height: h,
                        style: scored ? .score : .muted,
                        live: col.isLive
                    )
                } else {
                    valueCell("", width: w, height: h, style: .placeholder, placeholder: true)
                }
            }
        }
        gridRow(height: h) {
            labelCell("Net", width: metrics.labelWidth, height: h, bold: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(store.session.weName)  \(signed(weNet))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(scoreColor(for: signed(weNet)))
                Text("\(store.session.theyName)  \(signed(theyNet))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(scoreColor(for: signed(theyNet)))
                if let bet = bettingSummary {
                    if bet.tied {
                        Text("Betting · even")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(GinRummyPalette.sage.opacity(0.9))
                    } else {
                        let name = bet.leaderIsWe ? store.session.weName : store.session.theyName
                        Text("Betting · \(name) +\(bet.points) · box \(bet.bucket)")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(GinRummyPalette.gold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                } else {
                    Text("\(store.session.games.count) game\(store.session.games.count == 1 ? "" : "s") · saved on device")
                        .font(.caption2)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.85))
                }
            }
            .padding(.horizontal, cellPaddingH + 2)
            .frame(width: metrics.gamesWidth, height: h, alignment: .leading)
            .overlay(cellBorder(right: true))
        }
    }

    private var nameEditorSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("We (your side)", text: $draftWeName)
                    .ginOutlinedField()
                TextField("They (opponent)", text: $draftTheyName)
                    .ginOutlinedField()
                Spacer()
            }
            .padding(20)
            .background(GinRummyPalette.bgDeep)
            .navigationTitle("Player names")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showNameEditor = false }
                        .foregroundStyle(GinRummyPalette.sage)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateNames(we: draftWeName, they: draftTheyName)
                        showNameEditor = false
                    }
                    .foregroundStyle(GinRummyPalette.gold)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    // MARK: - Inline editing

    /// Live, in-cell numeric field. Tap the cell and type immediately — no extra
    /// step or bottom bar. The shared `editText` buffer is bound only while this
    /// cell is focused; committing happens when focus moves away.
    @ViewBuilder
    private func inlineNumericCell(
        field: FocusField,
        width: CGFloat,
        height: CGFloat,
        display: String,
        placeholder: String? = nil
    ) -> some View {
        let isEditing = focusedField == field
        let shown = display == "…" || display == "—" ? "" : display
        let promptText: String = {
            guard let placeholder else { return "·" }
            return (placeholder == "…" || placeholder == "—") ? "·" : placeholder
        }()
        let currentText = isEditing ? editText : shown

        TextField(
            "",
            text: cellBinding(field: field, committed: shown),
            prompt: Text(promptText).foregroundColor(CellTextStyle.placeholder.color)
        )
        .keyboardType(field.allowsNegative ? .numbersAndPunctuation : .numberPad)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .multilineTextAlignment(.center)
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(currentText.isEmpty ? CellTextStyle.placeholder.color : scoreColor(for: currentText))
        .tint(GinRummyPalette.gold)
        .focused($focusedField, equals: field)
        .submitLabel(.next)
        .onSubmit { advanceFrom(field) }
        .frame(width: max(width, 1), height: max(height, 1))
        .contentShape(Rectangle())
        .overlay(cellBorder(right: true))
        .background(isEditing ? GinRummyPalette.gold.opacity(0.12) : Color.clear)
    }

    /// Binding that surfaces the live edit buffer only for the focused cell, and
    /// the committed value otherwise (so other cells keep showing their scores).
    private func cellBinding(field: FocusField, committed: String) -> Binding<String> {
        Binding(
            get: { focusedField == field ? editText : committed },
            set: { newValue in
                if focusedField == field { editText = newValue }
            }
        )
    }

    @ViewBuilder
    private func weTheyEditablePair(
        game: ManualScoreGame,
        hand: ManualScoreHand,
        width: CGFloat,
        halfWidth: CGFloat,
        height: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            inlineNumericCell(
                field: .hand(gameId: game.id, handId: hand.id, side: .we),
                width: halfWidth,
                height: height,
                display: handCellDisplay(hand: hand, side: .we)
            )
            inlineNumericCell(
                field: .hand(gameId: game.id, handId: hand.id, side: .they),
                width: max(0, width - halfWidth),
                height: height,
                display: handCellDisplay(hand: hand, side: .they)
            )
        }
        .frame(width: width, height: height)
        .overlay(cellBorder(right: true))
        .background(liveColumnTint)
    }

    private func handIsEntered(_ hand: ManualScoreHand) -> Bool {
        hand.wePoints != nil || hand.theyPoints != nil
    }

    /// Empty string → dot placeholder; scored hands show 0 on the non-scoring side.
    private func handCellDisplay(hand: ManualScoreHand, side: FocusField.Side) -> String {
        guard handIsEntered(hand) else { return "" }
        switch side {
        case .we: return String(hand.wePoints ?? 0)
        case .they: return String(hand.theyPoints ?? 0)
        }
    }

    private func editableText(for field: FocusField) -> String {
        var text = displayText(for: field)
        if text.hasPrefix("+") { text = String(text.dropFirst()) }
        return text
    }

    private func finishEditing() {
        // Setting focus to nil triggers the commit in the focus onChange handler.
        focusedField = nil
    }

    private func commit(_ field: FocusField, text: String) {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if raw.isEmpty {
            clear(field)
            return
        }

        guard let value = parseScore(raw, allowsNegative: field.allowsNegative) else { return }

        switch field {
        case let .hand(gameId, handId, side):
            switch side {
            case .we: store.setHandPoints(gameId: gameId, handId: handId, we: value, they: 0)
            case .they: store.setHandPoints(gameId: gameId, handId: handId, we: 0, they: value)
            }
        case let .box(gameId, side):
            let game = store.session.games.first(where: { $0.id == gameId })
            switch side {
            case .we: store.setBox(gameId: gameId, we: value, they: game?.theyBox)
            case .they: store.setBox(gameId: gameId, we: game?.weBox, they: value)
            }
        }
    }

    private func clear(_ field: FocusField) {
        switch field {
        case let .hand(gameId, handId, _):
            store.setHandPoints(gameId: gameId, handId: handId, we: nil, they: nil)
        case let .box(gameId, side):
            let game = store.session.games.first(where: { $0.id == gameId })
            switch side {
            case .we: store.setBox(gameId: gameId, we: nil, they: game?.theyBox)
            case .they: store.setBox(gameId: gameId, we: game?.weBox, they: nil)
            }
        }
    }

    private func displayText(for field: FocusField) -> String {
        switch field {
        case let .hand(gameId, handId, side):
            guard let game = store.session.games.first(where: { $0.id == gameId }),
                  let hand = game.hands.first(where: { $0.id == handId }) else { return "" }
            return handCellDisplay(hand: hand, side: side)
        case let .box(gameId, side):
            guard let game = store.session.games.first(where: { $0.id == gameId }) else { return "" }
            let t = boxText(game: game, side: side)
            return t == "…" || t == "—" ? "" : t
        }
    }

    private func advanceFrom(_ field: FocusField) {
        // The focus onChange handler commits the current cell and loads the next.
        // `nextField` may append a new hand row, so defer focusing until the new
        // cell exists in the hierarchy.
        guard let next = nextField(after: field) else {
            focusedField = nil
            return
        }
        Task { @MainActor in
            focusedField = next
        }
    }

    private func nextField(after field: FocusField) -> FocusField? {
        switch field {
        case let .hand(gameId, handId, side):
            guard let gameIdx = store.session.games.firstIndex(where: { $0.id == gameId }) else { return nil }
            guard let handIdx = store.session.games[gameIdx].hands.firstIndex(where: { $0.id == handId }) else { return nil }
            let nextIdx = handIdx + 1
            if nextIdx >= store.session.games[gameIdx].hands.count {
                store.addHand(to: gameId)
            }
            let nextHand = store.session.games[gameIdx].hands[nextIdx]
            return .hand(gameId: gameId, handId: nextHand.id, side: side)

        case let .box(gameId, side):
            if let idx = store.session.games.firstIndex(where: { $0.id == gameId }),
               idx + 1 < store.session.games.count {
                let nextGame = store.session.games[idx + 1]
                return .box(gameId: nextGame.id, side: side)
            }
            if let game = store.session.games.first(where: { $0.id == gameId }),
               let firstHand = game.hands.first {
                return .hand(gameId: game.id, handId: firstHand.id, side: .we)
            }
            return nil
        }
    }

    private func parseScore(_ raw: String, allowsNegative: Bool) -> Int? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("+") { t = String(t.dropFirst()) }
        guard !t.isEmpty, let n = Int(t) else { return nil }
        if !allowsNegative, n < 0 { return nil }
        return n
    }

    // MARK: - Editable cells (removed sheet flow)

    private struct GridMetrics {
        let gridWidth: CGFloat
        let gridHeight: CGFloat
        let labelWidth: CGFloat
        let gamesWidth: CGFloat
        let gameColumnWidth: CGFloat
        let halfColumnWidth: CGFloat
        let rowHeight: CGFloat

        init(contentWidth: CGFloat, gridHeight: CGFloat, columnCount: Int, sectionRows: CGFloat) {
            let safeWidth = max(0, contentWidth)
            let safeHeight = max(0, gridHeight)
            gridWidth = safeWidth
            self.gridHeight = safeHeight
            labelWidth = max(0, floor(safeWidth * 0.26))
            gamesWidth = max(0, safeWidth - labelWidth)
            gameColumnWidth = max(0, floor(gamesWidth / CGFloat(max(columnCount, 1))))
            halfColumnWidth = max(0, floor(gameColumnWidth / 2))
            rowHeight = max(36, floor(safeHeight / max(sectionRows, 1)))
        }
    }

    private enum CellTextStyle {
        case label, muted, score, placeholder
        var color: Color {
            switch self {
            case .label: GinRummyPalette.cream.opacity(0.95)
            case .muted: GinRummyPalette.sage.opacity(0.9)
            case .score: GinRummyPalette.cream.opacity(0.95)
            case .placeholder: GinRummyPalette.sage.opacity(0.25)
            }
        }
    }

    private func colW(_ index: Int, _ columns: [DisplayColumn], _ base: CGFloat, _ gamesWidth: CGFloat) -> CGFloat {
        let remainder = gamesWidth - base * CGFloat(columns.count)
        return index == columns.count - 1 ? base + remainder : base
    }

    private func slotWidth(index: Int, count: Int, totalWidth: CGFloat) -> CGFloat {
        guard count > 0 else { return totalWidth }
        let base = floor(totalWidth / CGFloat(count))
        let remainder = totalWidth - base * CGFloat(count)
        return index == count - 1 ? base + remainder : base
    }

    private func signed(_ v: Int) -> String { v >= 0 ? "+\(v)" : "\(v)" }

    private struct ManualBetting {
        let leaderIsWe: Bool
        let points: Int
        let bucket: Int
        let tied: Bool
    }

    /// Quick betting settlement across the whole sheet, mirroring the in-app
    /// betting math: point margin + 100 game bonus + 100 shutout + 25 per net box.
    private var bettingSummary: ManualBetting? {
        let games = store.session.games
        guard games.contains(where: { $0.hasScoredHand }) else { return nil }
        let weTotal = games.map { $0.totalWe() }.reduce(0, +)
        let theyTotal = games.map { $0.totalThey() }.reduce(0, +)
        if weTotal == theyTotal {
            return ManualBetting(leaderIsWe: true, points: 0, bucket: 0, tied: true)
        }
        let weBoxes = games.map { $0.weBoxesWon() }.reduce(0, +)
        let theyBoxes = games.map { $0.theyBoxesWon() }.reduce(0, +)
        let leaderIsWe = weTotal > theyTotal
        let leadPts = leaderIsWe ? weTotal : theyTotal
        let loserPts = leaderIsWe ? theyTotal : weTotal
        let leaderBoxes = leaderIsWe ? weBoxes : theyBoxes
        let loserBoxes = leaderIsWe ? theyBoxes : weBoxes
        let shutout = (loserPts == 0 && leadPts > 0) ? 100 : 0
        let netBoxes = max(0, leaderBoxes - loserBoxes)
        let raw = (leadPts - loserPts) + 100 + shutout + 25 * netBoxes
        return ManualBetting(
            leaderIsWe: leaderIsWe,
            points: raw,
            bucket: BettingSettlementBreakdown.bettingBucket(forRaw: raw),
            tied: false
        )
    }

    private func scoreStyle(for text: String) -> CellTextStyle {
        if text == "…" || text == "—" || text == "·" { return .muted }
        return .score
    }

    private func scoreColor(for text: String) -> Color {
        if text.hasPrefix("+") { return GinRummyPalette.gold }
        if text.hasPrefix("-") { return Color(red: 0.95, green: 0.55, blue: 0.52) }
        return GinRummyPalette.cream.opacity(0.95)
    }

    @ViewBuilder private func gridRow(height: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 0) { content() }
            .frame(height: height)
            .overlay(rowDivider, alignment: .bottom)
    }

    @ViewBuilder private func labelCell(_ text: String, width: CGFloat, height: CGFloat, bold: Bool = false) -> some View {
        Text(text)
            .font(bold ? .caption.weight(.semibold) : .caption2)
            .foregroundStyle(bold ? CellTextStyle.label.color : CellTextStyle.muted.color)
            .lineLimit(2).minimumScaleFactor(0.75)
            .padding(.horizontal, cellPaddingH)
            .frame(width: width, height: height, alignment: .leading)
            .overlay(cellBorder(right: true))
    }

    @ViewBuilder private func valueCell(
        _ text: String, width: CGFloat, height: CGFloat,
        alignment: Alignment = .center, style: CellTextStyle = .score,
        uppercase: Bool = false, live: Bool = false, placeholder: Bool = false
    ) -> some View {
        ZStack {
            if live { liveColumnTint }
            Text(uppercase ? text.uppercased() : (text.isEmpty ? " " : text))
                .font(.caption2.weight(style == .muted ? .bold : .regular))
                .foregroundStyle(placeholder ? CellTextStyle.placeholder.color : style.color)
                .padding(.horizontal, cellPaddingH)
                .frame(width: width, height: height, alignment: alignment)
        }
        .frame(width: width, height: height)
        .overlay(cellBorder(right: true))
    }

    @ViewBuilder private func numericText(_ text: String, style: CellTextStyle) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(style == .score ? scoreColor(for: text) : style.color)
    }

    @ViewBuilder private func gameHeaderCell(column: DisplayColumn, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            if column.isLive, !column.isPlaceholder { liveColumnTint }
            VStack(spacing: 2) {
                Text(column.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(column.isPlaceholder ? CellTextStyle.placeholder.color : CellTextStyle.label.color)
                if column.isLive, !column.isPlaceholder {
                    Text("LIVE").font(.system(size: 8, weight: .heavy)).tracking(0.5).foregroundStyle(GinRummyPalette.gold)
                }
            }
            .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
        .overlay(cellBorder(right: true))
    }

    @ViewBuilder private func weTheyHeader(column: DisplayColumn, width: CGFloat, halfWidth: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            subHeaderCell("We", width: halfWidth, height: height, muted: column.isPlaceholder)
            subHeaderCell("They", width: max(0, width - halfWidth), height: height, muted: column.isPlaceholder)
        }
        .frame(width: width, height: height)
        .overlay(cellBorder(right: true))
        .background(column.isLive && !column.isPlaceholder ? liveColumnTint : nil)
    }

    @ViewBuilder private func subHeaderCell(_ title: String, width: CGFloat, height: CGFloat, muted: Bool) -> some View {
        Text(title).font(.caption2.weight(.semibold))
            .foregroundStyle(muted ? CellTextStyle.placeholder.color : CellTextStyle.muted.color)
            .frame(width: width, height: height)
            .overlay(cellBorder(right: true))
    }

    @ViewBuilder private func weTheyDataPair(
        we: String, they: String, width: CGFloat, halfWidth: CGFloat, height: CGFloat,
        live: Bool, emphasized: Bool = false
    ) -> some View {
        HStack(spacing: 0) {
            dataCell(we, width: halfWidth, height: height, emphasized: emphasized)
            dataCell(they, width: max(0, width - halfWidth), height: height, emphasized: emphasized)
        }
        .frame(width: width, height: height)
        .overlay(cellBorder(right: true))
        .background(live ? liveColumnTint : nil)
    }

    @ViewBuilder private func emptyWeTheyPair(width: CGFloat, halfWidth: CGFloat, height: CGFloat) -> some View {
        weTheyDataPair(we: "", they: "", width: width, halfWidth: halfWidth, height: height, live: false)
            .opacity(0.55)
    }

    @ViewBuilder private func dataCell(_ text: String, width: CGFloat, height: CGFloat, emphasized: Bool = false) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(emphasized ? .caption.weight(.bold).monospacedDigit() : .caption.monospacedDigit())
            .foregroundStyle(scoreColor(for: text))
            .frame(width: width, height: height, alignment: .center)
            .overlay(cellBorder(right: true))
    }

    private var liveColumnTint: Color { GinRummyPalette.gold.opacity(0.06) }
    private var lineColor: Color { GinRummyPalette.cream }

    @ViewBuilder private func cellBorder(right: Bool) -> some View {
        if right {
            Rectangle().fill(lineColor.opacity(0.32)).frame(width: 1)
                .frame(maxHeight: .infinity).frame(maxWidth: .infinity, alignment: .trailing)
                .allowsHitTesting(false)
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(lineColor.opacity(0.28)).frame(height: 1).allowsHitTesting(false)
    }
    private var sectionDivider: some View {
        Rectangle().fill(lineColor.opacity(0.42)).frame(height: 1.5).allowsHitTesting(false)
    }
    private var gridOuterBorder: some View {
        Rectangle().strokeBorder(lineColor.opacity(0.5), lineWidth: 1.5).allowsHitTesting(false)
    }
}
