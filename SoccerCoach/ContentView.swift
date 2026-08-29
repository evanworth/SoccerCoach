import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private struct DismissKeyboardOnTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        )
    }
}

private extension View {
    func dismissKeyboardOnTap() -> some View {
        modifier(DismissKeyboardOnTapModifier())
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: SoccerCoachStore

    var body: some View {
        CoachHomeView()
            .dismissKeyboardOnTap()
    }
}

struct CoachHomeView: View {
    @EnvironmentObject private var store: SoccerCoachStore

    var body: some View {
        TabView {
            GameView()
                .tabItem {
                    Label("Game", systemImage: "soccerball")
                }

            RosterView()
                .tabItem {
                    Label("Roster", systemImage: "person.3.fill")
                }

            PracticePlansView()
                .tabItem {
                    Label("Practice", systemImage: "clipboard.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(.green)
        .sheet(isPresented: Binding(
            get: { store.shouldShowCoachOnboarding },
            set: { newValue in
                if !newValue {
                    store.markCoachOnboardingSeen()
                }
            }
        )) {
            CoachOnboardingSheet()
                .environmentObject(store)
        }
    }
}

struct CoachOnboardingSheet: View {
    @EnvironmentObject private var store: SoccerCoachStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Welcome to SoccerCoach")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Quick start: set a lineup, queue next subs, and tap Sub All Queued during live play.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Game tab: manage live lineup + substitutions", systemImage: "soccerball")
                        Label("Roster tab: add players and preferred positions", systemImage: "person.3.fill")
                        Label("Practice tab: build reusable drills and plans", systemImage: "clipboard.fill")
                        Label("Settings tab: formation, sub plan, backup + restore", systemImage: "gearshape.fill")
                    }
                    .font(.headline)

                    Button("Load Sample Team Data") {
                        store.loadSampleCoachingData()
                    }
                    .buttonStyle(.bordered)

                    Button("Start Coaching") {
                        store.markCoachOnboardingSeen()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
            }
            .navigationTitle("Coach Onboarding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        store.markCoachOnboardingSeen()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: SoccerCoachStore

    @State private var backupExportURL: URL?
    @State private var isShowingBackupImporter = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    themeCard
                    backupCard
                    gameInfoCard
                    lineupPresetCard
                    positionSetupCard
                    subPlanCard
                    gameNotesCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
            .fileImporter(
                isPresented: $isShowingBackupImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let fileURL = urls.first else { return }
                    do {
                        try store.importBackup(from: fileURL)
                    } catch {
                        store.backupErrorMessage = error.localizedDescription
                    }
                case .failure(let error):
                    store.backupErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(.headline)

            Text("Pick how SoccerCoach should look on this device. System follows your phone setting.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Theme", selection: Binding(
                get: { store.data.appTheme },
                set: { store.setAppTheme($0) }
            )) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)

            Button("Show Onboarding Again") {
                store.showCoachOnboardingAgain()
            }
            .buttonStyle(.bordered)
        }
        .cardStyle()
    }

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backup & Recovery")
                .font(.headline)

            Text("Create a backup file before major changes. If anything ever disappears, restore from backup.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("Create Backup") {
                    do {
                        backupExportURL = try store.createBackupFile()
                    } catch {
                        store.backupErrorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Restore Backup") {
                    isShowingBackupImporter = true
                }
                .buttonStyle(.bordered)
            }

            if let backupExportURL {
                ShareLink(item: backupExportURL) {
                    Label("Share Backup File", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            if !store.backupStatusMessage.isEmpty {
                Text(store.backupStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let backupErrorMessage = store.backupErrorMessage {
                Text(backupErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .cardStyle()
    }

    private var gameInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Game Management")
                    .font(.headline)
                Spacer()
                Button("Reset Formation Spots") {
                    store.resetToSevenVSevenShape()
                }
                .buttonStyle(.bordered)
            }

            Picker(
                "Formation",
                selection: Binding(
                    get: { store.data.gameFormation },
                    set: { store.setGameFormation($0) }
                )
            ) {
                ForEach(GameFormation.allCases, id: \.self) { formation in
                    Text(formation.title).tag(formation)
                }
            }
            .pickerStyle(.segmented)

            Text("Half Length: 30 min (fixed)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Total Game Time: 60 min")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Stepper("Sub Interval: \(store.data.substitutionInterval) min", value: gameBinding(\.substitutionInterval), in: 3...15)

            Button("Rebuild Sub Plan") {
                store.regenerateSubWindows()
            }
            .buttonStyle(.bordered)
        }
        .cardStyle()
    }

    private var lineupPresetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lineup Presets")
                .font(.headline)

            HStack {
                TextField("Preset name", text: $store.newPresetName)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    store.saveCurrentLineupPreset()
                }
                .buttonStyle(.borderedProminent)
            }

            if store.data.lineupPresets.isEmpty {
                Text("Save a favorite starting group so you can load it in one tap.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.data.lineupPresets.indices), id: \.self) { index in
                    HStack {
                        Button(store.data.lineupPresets[index].name) {
                            store.applyLineupPreset(store.data.lineupPresets[index])
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(role: .destructive) {
                            store.deleteLineupPresets(at: IndexSet(integer: index))
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    private var positionSetupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Field Positions")
                    .font(.headline)
                Spacer()
                Button("Add Spot") {
                    store.addPosition()
                }
                .buttonStyle(.bordered)
            }

            ForEach(store.data.fieldPositions.map(\.id), id: \.self) { positionID in
                HStack {
                    TextField("Position name", text: fieldPositionNameBinding(positionID))
                    .textFieldStyle(.roundedBorder)

                    Button(role: .destructive) {
                        removeFieldPosition(positionID)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .cardStyle()
    }

    private var subPlanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sub Schedule")
                    .font(.headline)
                Spacer()
                Button("Add Window") {
                    store.addSubWindow()
                }
                .buttonStyle(.bordered)
            }

            ForEach(store.data.subWindows.map(\.id), id: \.self) { windowID in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle(isOn: subWindowCompletedBinding(windowID)) {
                            Text("Minute \(subWindowMinute(windowID))")
                                .font(.subheadline.weight(.semibold))
                        }
                        Button(role: .destructive) {
                            removeSubWindow(windowID)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    Stepper(
                        "Minute: \(subWindowMinute(windowID))",
                        value: subWindowMinuteBinding(windowID),
                        in: 1...store.data.gameLengthMinutes
                    )
                    TextField("Sub plan", text: subWindowFocusBinding(windowID), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .cardStyle()
    }

    private var gameNotesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game Notes")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("First Half")
                    .font(.subheadline.weight(.semibold))
                TextField("What to remember from the first half", text: Binding(
                    get: { store.data.firstHalfNotes },
                    set: {
                        store.data.firstHalfNotes = $0
                        store.save()
                    }
                ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Second Half")
                    .font(.subheadline.weight(.semibold))
                TextField("What to remember from the second half", text: Binding(
                    get: { store.data.secondHalfNotes },
                    set: {
                        store.data.secondHalfNotes = $0
                        store.save()
                    }
                ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
            }
        }
        .cardStyle()
    }

    private func gameBinding(_ keyPath: WritableKeyPath<AppData, Int>) -> Binding<Int> {
        Binding(
            get: { store.data[keyPath: keyPath] },
            set: {
                if keyPath == \AppData.gameLengthMinutes {
                    store.setGameLengthMinutes($0)
                    return
                }
                store.data[keyPath: keyPath] = $0
                store.save()
            }
        )
    }

    private func fieldPositionNameBinding(_ positionID: UUID) -> Binding<String> {
        Binding(
            get: {
                store.data.fieldPositions.first(where: { $0.id == positionID })?.name ?? ""
            },
            set: { newValue in
                guard let index = store.data.fieldPositions.firstIndex(where: { $0.id == positionID }) else { return }
                store.data.fieldPositions[index].name = newValue
                store.save()
            }
        )
    }

    private func removeFieldPosition(_ positionID: UUID) {
        guard let index = store.data.fieldPositions.firstIndex(where: { $0.id == positionID }) else { return }
        store.data.fieldPositions.remove(at: index)
        store.save()
    }

    private func subWindowMinute(_ windowID: UUID) -> Int {
        store.data.subWindows.first(where: { $0.id == windowID })?.minuteMark ?? 1
    }

    private func subWindowCompletedBinding(_ windowID: UUID) -> Binding<Bool> {
        Binding(
            get: {
                store.data.subWindows.first(where: { $0.id == windowID })?.completed ?? false
            },
            set: { newValue in
                guard let index = store.data.subWindows.firstIndex(where: { $0.id == windowID }) else { return }
                store.data.subWindows[index].completed = newValue
                store.save()
            }
        )
    }

    private func subWindowMinuteBinding(_ windowID: UUID) -> Binding<Int> {
        Binding(
            get: {
                store.data.subWindows.first(where: { $0.id == windowID })?.minuteMark ?? 1
            },
            set: { newValue in
                guard let index = store.data.subWindows.firstIndex(where: { $0.id == windowID }) else { return }
                store.data.subWindows[index].minuteMark = newValue
                store.save()
            }
        )
    }

    private func subWindowFocusBinding(_ windowID: UUID) -> Binding<String> {
        Binding(
            get: {
                store.data.subWindows.first(where: { $0.id == windowID })?.focus ?? ""
            },
            set: { newValue in
                guard let index = store.data.subWindows.firstIndex(where: { $0.id == windowID }) else { return }
                store.data.subWindows[index].focus = newValue
                store.save()
            }
        )
    }

    private func removeSubWindow(_ windowID: UUID) {
        guard let index = store.data.subWindows.firstIndex(where: { $0.id == windowID }) else { return }
        store.data.subWindows.remove(at: index)
        store.save()
    }
}

struct GameView: View {
    @EnvironmentObject private var store: SoccerCoachStore
    @FocusState private var focusedField: FocusField?
    @State private var isShowingAvailabilityEditor = false
    @State private var gameReportSheet: GameReportSheet?

    private enum FocusField: Hashable {
        case opponent
    }

    fileprivate enum GameReportSheet: Identifiable {
        case history
        case report(SavedGameStats)

        var id: String {
            switch self {
            case .history:
                return "history"
            case .report(let game):
                return "report-\(game.id.uuidString)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    timerCard
                    lineupCard
                    nextInCard
                    moveBoardCard
                    fairPlayCard
                    subSuggestionsCard
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("SoccerCoach")
            .sheet(item: selectedFieldPositionBinding) { position in
                PositionAssignmentView(position: position)
                    .environmentObject(store)
            }
            .sheet(isPresented: $isShowingAvailabilityEditor) {
                GameAvailabilityView()
                    .environmentObject(store)
            }
            .sheet(item: $gameReportSheet) { sheet in
                switch sheet {
                case .history:
                    GameHistoryView()
                        .environmentObject(store)
                case .report(let game):
                    GameReportView(game: game)
                        .environmentObject(store)
                }
            }
        }
    }

    private var timerCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Half \(store.currentHalf)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if store.remainingSeconds == 0 {
                    Text(store.currentHalf == 1 ? "Halftime" : "Full Time")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(store.currentHalf == 1 ? .orange : .secondary)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Clock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(store.formattedTime())
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                HStack(spacing: 8) {
                    if store.currentHalf == 1 && store.remainingSeconds == 0 && !store.timerRunning {
                        Button("Start 2nd Half") {
                            store.startSecondHalf()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    } else {
                        Button(store.timerRunning ? "Pause" : "Start") {
                            store.startPauseTimer()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.timerRunning && store.currentHalf == 2 && store.remainingSeconds == 0)
                    }

                    Button("Reset") {
                        store.resetTimer()
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 10) {
                TextField("Opponent", text: Binding(
                    get: { store.data.gameOpponentName },
                    set: {
                        store.data.gameOpponentName = $0
                        store.queueAutosave()
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .opponent)
                .submitLabel(.done)
                    .onSubmit {
                        focusedField = nil
                        store.queueAutosave()
                    }
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

                DatePicker(
                    "Game Date",
                    selection: Binding(
                        get: { store.data.gameDate },
                        set: {
                            store.data.gameDate = $0
                            store.queueAutosave()
                        }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                Button("Start Game") {
                    focusedField = nil
                    store.startGameSession()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var lineupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lineup")
                    .font(.headline)
                if !store.unavailablePlayerIDs.isEmpty {
                    Text("Unavailable: \(store.unavailablePlayerIDs.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(Capsule())
                }
                Spacer()
                Button("Availability") {
                    isShowingAvailabilityEditor = true
                }
                .buttonStyle(.bordered)
                Button("Lineup") {
                    if let first = store.data.fieldPositions.first {
                        store.selectedFieldPositionID = first.id
                    }
                }
                .buttonStyle(.bordered)
            }

            SevenVSevenFieldView(
                positions: store.data.fieldPositions,
                formation: store.data.gameFormation,
                playerName: { playerID in
                    store.player(for: playerID).map(playerRowTitle) ?? "Open"
                },
                playerDetail: { position in
                    if let playerID = position.assignedPlayerID {
                        return store.formattedPlayTime(for: playerID)
                    }
                    return "0:00"
                },
                onTapPosition: { position in
                    store.selectedFieldPositionID = position.id
                }
            )

            if !store.benchPlayers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bench")
                        .font(.subheadline.weight(.semibold))
                    ForEach(store.benchPlayers) { player in
                        HStack {
                            Text(playerRowTitle(player))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(store.formattedPlayTime(for: player.id))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var fairPlayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fair Play")
                    .font(.headline)
                Spacer()
                Button("Save Game") {
                    let saved = store.saveCurrentGameStats()
                    store.resetTimer()
                    gameReportSheet = .report(saved)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                Button("Reset Minutes") {
                    store.resetFairPlay()
                }
                .buttonStyle(.bordered)
            }

            Button {
                gameReportSheet = .history
            } label: {
                Text("Saved games this season: \(store.savedGameCount)")
                    .font(.footnote)
            }
            .disabled(store.savedGameCount == 0)

            if store.data.players.isEmpty {
                Text("Add players to track minutes.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.data.players.sorted(by: playerSort), id: \.id) { player in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playerRowTitle(player))
                            if !player.playablePositions.isEmpty {
                                Text(player.playablePositions.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Game: \(store.formattedPlayTime(for: player.id))  •  Season: \(store.formattedSeasonPlayTime(for: player.id))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(store.formattedPlayTime(for: player.id))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(store.assignedPlayerIDs.contains(player.id) ? .green : .secondary)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var moveBoardCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move Players")
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                let forwardPositions = positionsForBoardRow(["forward", "striker", "offense"])
                let midfieldPositions = positionsForBoardRow(["midfield"])
                let defensePositions = positionsForBoardRow(["defense", "defender", "back"])
                let goaliePositions = positionsForBoardRow(["goalie", "gk", "keeper"])

                if !forwardPositions.isEmpty {
                    moveBoardRow(title: "Forward", positions: forwardPositions, tint: Color(red: 0.92, green: 0.83, blue: 0.47))
                }
                if !midfieldPositions.isEmpty {
                    moveBoardRow(title: "Midfield", positions: midfieldPositions, tint: Color(red: 0.55, green: 0.80, blue: 0.61), cardWidth: 102)
                }
                if !defensePositions.isEmpty {
                    moveBoardRow(title: "Defense", positions: defensePositions, tint: Color(red: 0.49, green: 0.69, blue: 0.88))
                }
                if !goaliePositions.isEmpty {
                    moveBoardRow(title: "Goalie", positions: goaliePositions, tint: Color(red: 0.94, green: 0.65, blue: 0.47))
                }
            }

            BenchDropCard(
                players: store.benchPlayers,
                playerTitle: playerRowTitle,
                playerDetail: { player in store.formattedPlayTime(for: player.id) },
                tint: Color(red: 0.84, green: 0.84, blue: 0.84),
                onDropPlayer: { playerID in
                    store.movePlayer(playerID, to: nil)
                }
            )
        }
        .cardStyle()
    }

    private var nextInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Next In Queue")
                    .font(.headline)
                Spacer()
                Button("Sub All Queued") {
                    store.applyAllQueuedNextPlayers()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasQueuedPlayers)
            }
            Text("How it works: choose the next player for each position, then tap \"Sub Now\" when you’re ready to make that swap.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(orderedQueuePositions) { position in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(position.name)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if let queued = store.queuedNextPlayer(for: position.id) {
                            Text(playerRowTitle(queued))
                                .font(.caption)
                                .foregroundStyle(.primary)
                        } else {
                            Text("None selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Next In for \(position.name)", selection: Binding(
                        get: { store.queuedNextPlayerID(for: position.id) },
                        set: { store.setQueuedNextPlayer($0, for: position.id) }
                    )) {
                        Text("None").tag(UUID?.none)
                        ForEach(nextInCandidates(for: position)) { player in
                            Text(playerQueueLabel(player, for: position)).tag(Optional(player.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if store.queuedNextPlayerID(for: position.id) != nil {
                        Button("Sub Now") {
                            store.applyQueuedNextPlayer(for: position.id)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .cardStyle()
    }

    private var subSuggestionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sub Suggestions")
                    .font(.headline)
                Spacer()
                Button("Apply All") {
                    store.applyAllSuggestedSubs()
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.suggestedSubs.isEmpty)
                Button("Refresh") {
                    store.refreshSuggestedSubs()
                }
                .buttonStyle(.bordered)
            }

            if store.suggestedSubs.isEmpty {
                Text("Suggestions will appear once playing time starts to spread out.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.suggestedSubs) { suggestion in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(suggestion.positionName)
                            .font(.subheadline.weight(.semibold))
                        Text(suggestionSummary(suggestion))
                            .foregroundStyle(.primary)
                        Text(suggestion.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Apply Suggestion") {
                                store.applySuggestedSub(suggestion)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Dismiss") {
                                store.dismissSuggestedSub(suggestion)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .cardStyle()
    }

    private func playerRowTitle(_ player: Player) -> String {
        let jersey = player.jerseyNumber.isEmpty ? "" : " #\(player.jerseyNumber)"
        return "\(player.name)\(jersey)"
    }

    private func playerSort(_ lhs: Player, _ rhs: Player) -> Bool {
        let lhsTime = store.playerSecondsPlayed[lhs.id, default: 0]
        let rhsTime = store.playerSecondsPlayed[rhs.id, default: 0]
        if lhsTime == rhsTime {
            return lhs.name < rhs.name
        }
        return lhsTime > rhsTime
    }

    private func suggestionSummary(_ suggestion: SuggestedSubstitution) -> String {
        let outName = store.player(for: suggestion.playerOutID).map(playerRowTitle) ?? "Current player"
        let inName = store.player(for: suggestion.playerInID).map(playerRowTitle) ?? "Bench player"
        return "\(outName) out, \(inName) in"
    }

    private func moveBoardRow(title: String, positions: [FieldPosition], tint: Color, cardWidth: CGFloat = 170) -> some View {
        let assignedCount = positions.compactMap(\.assignedPlayerID).count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(assignedCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(positions) { position in
                        PositionDropCard(
                            position: position,
                            playerLabel: store.player(for: position.assignedPlayerID).map(playerRowTitle) ?? "Drop player here",
                            assignedPlayerID: position.assignedPlayerID,
                            onDropPlayer: { playerID in
                                store.movePlayer(playerID, to: position.id)
                            }
                        )
                        .frame(width: cardWidth)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(.separator).opacity(0.25), lineWidth: 1)
        )
    }

    private func positionsForBoardRow(_ names: [String]) -> [FieldPosition] {
        let normalizedTargets = names.map { $0.lowercased().replacingOccurrences(of: " ", with: "") }
        return store.data.fieldPositions.filter { position in
            let normalized = position.name.lowercased().replacingOccurrences(of: " ", with: "")
            return normalizedTargets.contains { normalized.contains($0) || $0.contains(normalized) }
        }
        .sorted { lhs, rhs in
            let lhsRank = queuePositionRank(lhs.name)
            let rhsRank = queuePositionRank(rhs.name)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.name < rhs.name
        }
    }

    private func nextInCandidates(for position: FieldPosition) -> [Player] {
        let target = position.name
        return store.availablePlayers.sorted { lhs, rhs in
            let lhsRank = positionRank(for: lhs, target: target)
            let rhsRank = positionRank(for: rhs, target: target)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            let lhsOnField = store.assignedPlayerIDs.contains(lhs.id)
            let rhsOnField = store.assignedPlayerIDs.contains(rhs.id)
            if lhsOnField != rhsOnField {
                return !lhsOnField && rhsOnField
            }
            return lhs.name < rhs.name
        }
    }

    private func playerQueueLabel(_ player: Player, for position: FieldPosition) -> String {
        let base = playerRowTitle(player)
        let isOnField = store.assignedPlayerIDs.contains(player.id)
        let queuedElsewhere = store.data.fieldPositions.first { candidate in
            candidate.id != position.id && store.queuedNextPlayerID(for: candidate.id) == player.id
        }?.name

        if isOnField, let queuedElsewhere {
            return "\(base) (On Field • Queued: \(queuedElsewhere))"
        }
        if isOnField {
            return "\(base) (On Field)"
        }
        if let queuedElsewhere {
            return "\(base) (Queued: \(queuedElsewhere))"
        }
        return base
    }

    private func positionRank(for player: Player, target: String) -> Int {
        store.bestPositionMatchRank(for: player, targetPositionName: target)
    }

    private var hasQueuedPlayers: Bool {
        orderedQueuePositions.contains { store.queuedNextPlayerID(for: $0.id) != nil }
    }

    private var orderedQueuePositions: [FieldPosition] {
        store.data.fieldPositions.sorted { lhs, rhs in
            let lhsRank = queuePositionRank(lhs.name)
            let rhsRank = queuePositionRank(rhs.name)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.name < rhs.name
        }
    }

    private func queuePositionRank(_ name: String) -> Int {
        let normalized = store.normalizePositionName(name)
        if normalized.contains("forward") {
            if normalized.contains("left") { return 0 }
            if normalized.contains("center") { return 1 }
            if normalized.contains("right") { return 2 }
            return 1
        }
        if normalized.contains("midfield") {
            if normalized.contains("left") { return 3 }
            if normalized.contains("center") { return 4 }
            if normalized.contains("right") { return 5 }
            return 4
        }
        if normalized.contains("defense") || normalized.contains("defender") || normalized.contains("back") {
            if normalized.contains("left") { return 6 }
            if normalized.contains("center") { return 7 }
            if normalized.contains("right") { return 8 }
            return 7
        }
        if normalized.contains("goalie") || normalized.contains("gk") || normalized.contains("keeper") {
            return 9
        }
        return 10
    }

    private var selectedFieldPositionBinding: Binding<FieldPosition?> {
        Binding(
            get: {
                guard let id = store.selectedFieldPositionID else { return nil }
                return store.data.fieldPositions.first { $0.id == id }
            },
            set: { newValue in
                store.selectedFieldPositionID = newValue?.id
            }
        )
    }
}

struct PositionDropCard: View {
    let position: FieldPosition
    let playerLabel: String
    let assignedPlayerID: UUID?
    let onDropPlayer: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(position.name)
                .font(.subheadline.weight(.semibold))
            if let assignedPlayerID {
                Text(playerLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(red: 0.10, green: 0.14, blue: 0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    )
                    .draggable(assignedPlayerID.uuidString)
            } else {
                Text(playerLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(red: 0.17, green: 0.20, blue: 0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let playerID = UUID(uuidString: raw) else { return false }
            onDropPlayer(playerID)
            return true
        }
    }
}

struct BenchDropCard: View {
    let players: [Player]
    let playerTitle: (Player) -> String
    let playerDetail: (Player) -> String
    let tint: Color
    let onDropPlayer: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bench")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(players.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if players.isEmpty {
                Text("Drop a player here to take them off the field.")
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ForEach(players) { player in
                    HStack {
                        Text(playerTitle(player))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(playerDetail(player))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(red: 0.10, green: 0.14, blue: 0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.20), lineWidth: 1)
                        )
                        .draggable(player.id.uuidString)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let playerID = UUID(uuidString: raw) else { return false }
            onDropPlayer(playerID)
            return true
        }
    }
}

struct SevenVSevenFieldView: View {
    let positions: [FieldPosition]
    let formation: GameFormation
    let playerName: (UUID?) -> String
    let playerDetail: (FieldPosition) -> String
    let onTapPosition: (FieldPosition) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let centerLineOffset = -size.height * 0.10
            let compact = size.width < 390
            let slotLayout = layout(for: formation, compact: compact)
            let playerBubbleWidth: CGFloat = compact ? 90 : 104
            let positionBubbleWidth: CGFloat = compact ? 84 : 98
            let fieldCenterOffset = size.height * 0.02
            let fieldHeight = size.height * 0.90
            let topEndLineOffset = fieldCenterOffset - (fieldHeight / 2)
            let bottomEndLineOffset = fieldCenterOffset + (fieldHeight / 2)
            let penaltyHeight = size.height * 0.16
            let goalAreaHeight = size.height * 0.08
            let topPenaltyOffset = topEndLineOffset + (penaltyHeight / 2)
            let topGoalAreaOffset = topEndLineOffset + (goalAreaHeight / 2)
            let bottomPenaltyOffset = bottomEndLineOffset - (penaltyHeight / 2)
            let bottomGoalAreaOffset = bottomEndLineOffset - (goalAreaHeight / 2)

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.18, green: 0.58, blue: 0.29), Color(red: 0.10, green: 0.43, blue: 0.22)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: 3)

                Rectangle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: size.width * 0.86, height: size.height * 0.90)
                    .offset(y: fieldCenterOffset)

                Rectangle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: size.width * 0.46, height: size.height * 0.16)
                    .offset(y: topPenaltyOffset)

                Rectangle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: size.width * 0.27, height: size.height * 0.08)
                    .offset(y: topGoalAreaOffset)

                Rectangle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: size.width * 0.46, height: size.height * 0.16)
                    .offset(y: bottomPenaltyOffset)

                Rectangle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: size.width * 0.27, height: size.height * 0.08)
                    .offset(y: bottomGoalAreaOffset)

                Rectangle()
                    .frame(width: size.width * 0.86, height: 2)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .offset(y: centerLineOffset)

                Circle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: min(size.width * 0.34, size.height * 0.34))
                    .offset(y: centerLineOffset)

                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 6, height: 6)
                    .offset(y: centerLineOffset)

                Rectangle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: size.width * 0.20, height: 2)
                    .offset(y: size.height * 0.23)

                ForEach(slotLayout, id: \.label) { slot in
                    let position = matchingPosition(named: slot.label)
                    Button {
                        if let position {
                            onTapPosition(position)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(playerName(position?.assignedPlayerID))
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(width: playerBubbleWidth)
                                .background(Color(red: 0.05, green: 0.08, blue: 0.14))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
                            Text(position.map(playerDetail) ?? "Fair Play 0:00")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 5)
                                .frame(width: positionBubbleWidth)
                                .background(Color(red: 0.10, green: 0.14, blue: 0.22))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                                )
                        }
                        .padding(4)
                        .background(Color(red: 0.03, green: 0.06, blue: 0.10).opacity(0.88))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(position == nil)
                    .position(x: size.width * slot.x, y: size.height * slot.y)
                }
            }
        }
        .aspectRatio(0.9, contentMode: .fit)
    }

    private func layout(for formation: GameFormation, compact: Bool) -> [(label: String, x: CGFloat, y: CGFloat)] {
        switch formation {
        case .threeThree:
            if compact {
                return [
                    ("Left Forward", 0.17, 0.48),
                    ("Center Forward", 0.5, 0.45),
                    ("Right Forward", 0.83, 0.48),
                    ("Left Defense", 0.17, 0.72),
                    ("Center Defense", 0.5, 0.69),
                    ("Right Defense", 0.83, 0.72),
                    ("Goalie", 0.5, 0.93),
                ]
            }
            return [
                ("Left Forward", 0.18, 0.47),
                ("Center Forward", 0.5, 0.44),
                ("Right Forward", 0.82, 0.47),
                ("Left Defense", 0.19, 0.71),
                ("Center Defense", 0.5, 0.68),
                ("Right Defense", 0.81, 0.71),
                ("Goalie", 0.5, 0.93),
            ]
        case .threeOneTwo:
            if compact {
                return [
                    ("Left Forward", 0.24, 0.49),
                    ("Right Forward", 0.76, 0.49),
                    ("Center Midfield", 0.5, 0.62),
                    ("Left Defense", 0.18, 0.75),
                    ("Center Defense", 0.5, 0.72),
                    ("Right Defense", 0.82, 0.75),
                    ("Goalie", 0.5, 0.93),
                ]
            }
            return [
                ("Left Forward", 0.25, 0.48),
                ("Right Forward", 0.75, 0.48),
                ("Center Midfield", 0.5, 0.61),
                ("Left Defense", 0.19, 0.74),
                ("Center Defense", 0.5, 0.71),
                ("Right Defense", 0.81, 0.74),
                ("Goalie", 0.5, 0.93),
            ]
        case .twoTwoTwo:
            if compact {
                return [
                    ("Left Forward", 0.24, 0.48),
                    ("Right Forward", 0.76, 0.48),
                    ("Left Midfield", 0.24, 0.62),
                    ("Right Midfield", 0.76, 0.62),
                    ("Left Defense", 0.24, 0.76),
                    ("Right Defense", 0.76, 0.76),
                    ("Goalie", 0.5, 0.93),
                ]
            }
            return [
                ("Left Forward", 0.25, 0.47),
                ("Right Forward", 0.75, 0.47),
                ("Left Midfield", 0.25, 0.61),
                ("Right Midfield", 0.75, 0.61),
                ("Left Defense", 0.25, 0.75),
                ("Right Defense", 0.75, 0.75),
                ("Goalie", 0.5, 0.93),
            ]
        case .twoThreeOne:
            if compact {
                return [
                    ("Forward", 0.5, 0.40),
                    ("Left Midfield", 0.16, 0.55),
                    ("Center Midfield", 0.5, 0.55),
                    ("Right Midfield", 0.84, 0.55),
                    ("Left Defense", 0.18, 0.74),
                    ("Right Defense", 0.82, 0.74),
                    ("Goalie", 0.5, 0.93),
                ]
            }
            return [
                ("Forward", 0.5, 0.40),
                ("Left Midfield", 0.17, 0.54),
                ("Center Midfield", 0.5, 0.54),
                ("Right Midfield", 0.83, 0.54),
                ("Left Defense", 0.19, 0.73),
                ("Right Defense", 0.81, 0.73),
                ("Goalie", 0.5, 0.93),
            ]
        }
    }

    private func matchingPosition(named label: String) -> FieldPosition? {
        let normalized = normalizedName(label)
        return positions.first { normalizedName($0.name) == normalized }
            ?? positions.first { normalizedName($0.name).contains(normalized) || normalized.contains(normalizedName($0.name)) }
    }

    private func normalizedName(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }
}

struct PositionAssignmentView: View {
    @EnvironmentObject private var store: SoccerCoachStore
    @Environment(\.dismiss) private var dismiss

    let position: FieldPosition
    @State private var mode: Mode = .assignNow

    private enum Mode: String, CaseIterable, Identifiable {
        case assignNow = "Assign Now"
        case queueNext = "Queue Next"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .assignNow {
                    Section("Assign \(position.name) Now") {
                        Button("Leave Open") {
                            store.assignPlayer(nil, to: position.id)
                            dismiss()
                        }
                    }
                } else {
            Section("Queue for Next Sub") {
                        Text("Tap a player below while in Queue mode to save them as the next substitution for this position.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let queued = store.queuedNextPlayer(for: position.id) {
                            Text("Queued: \(playerLabel(queued))")
                                .font(.subheadline)
                            Button("Clear Queue", role: .destructive) {
                                store.setQueuedNextPlayer(nil, for: position.id)
                            }
                        } else {
                            Text("No queued player yet.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !primaryPlayers.isEmpty {
                    Section("Primary Match") {
                        ForEach(primaryPlayers) { player in
                            playerActionRow(player)
                        }
                    }
                }

                if !additionalFitPlayers.isEmpty {
                    Section("Also Plays This Position") {
                        ForEach(additionalFitPlayers) { player in
                            playerActionRow(player)
                        }
                    }
                }

                if !otherPlayers.isEmpty {
                    Section("Other Players") {
                        ForEach(otherPlayers) { player in
                            playerActionRow(player)
                        }
                    }
                }
            }
            .navigationTitle(position.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func playerLabel(_ player: Player) -> String {
        let jersey = player.jerseyNumber.isEmpty ? "" : " #\(player.jerseyNumber)"
        return "\(player.name)\(jersey)"
    }

    @ViewBuilder
    private func playerActionRow(_ player: Player) -> some View {
        Button {
            if mode == .assignNow {
                store.assignPlayer(player.id, to: position.id)
            } else {
                store.setQueuedNextPlayer(player.id, for: position.id)
            }
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(playerSelectionLabel(player))
                    .foregroundStyle(.primary)
                if !player.playablePositions.isEmpty {
                    Text(player.playablePositions.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Game Time: \(store.formattedPlayTime(for: player.id))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var target: String {
        store.normalizePositionName(position.name)
    }

    private var sortedPlayers: [Player] {
        store.availablePlayers.sorted { lhs, rhs in
            let lhsOrder = matchOrder(for: lhs)
            let rhsOrder = matchOrder(for: rhs)
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }

            let lhsOnField = store.assignedPlayerIDs.contains(lhs.id)
            let rhsOnField = store.assignedPlayerIDs.contains(rhs.id)
            if lhsOnField != rhsOnField {
                return !lhsOnField && rhsOnField
            }
            return lhs.name < rhs.name
        }
    }

    private var primaryPlayers: [Player] {
        sortedPlayers.filter { matchOrder(for: $0) == 0 }
    }

    private var additionalFitPlayers: [Player] {
        sortedPlayers.filter {
            let order = matchOrder(for: $0)
            return order > 0 && order < Int.max
        }
    }

    private var otherPlayers: [Player] {
        sortedPlayers.filter { matchOrder(for: $0) == Int.max }
    }

    private func matchOrder(for player: Player) -> Int {
        if let index = player.playablePositions.firstIndex(where: {
            store.normalizePositionName($0) == target
        }) {
            return index
        }
        return Int.max
    }

    private func playerSelectionLabel(_ player: Player) -> String {
        let base = playerLabel(player)
        let isOnField = store.assignedPlayerIDs.contains(player.id)
        let queuedElsewhere = queuedPositionName(for: player)

        if isOnField, let queuedElsewhere {
            return "\(base) (On Field • Queued: \(queuedElsewhere))"
        }
        if isOnField {
            return "\(base) (On Field)"
        }
        if let queuedElsewhere {
            return "\(base) (Queued: \(queuedElsewhere))"
        }
        return base
    }

    private func queuedPositionName(for player: Player) -> String? {
        store.data.fieldPositions.first { candidate in
            candidate.id != position.id && store.queuedNextPlayerID(for: candidate.id) == player.id
        }?.name
    }
}

struct GameAvailabilityView: View {
    @EnvironmentObject private var store: SoccerCoachStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if store.data.players.isEmpty {
                    Text("No players in roster yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Section("Unavailable For This Game") {
                        ForEach(store.data.players.sorted { $0.name < $1.name }, id: \.id) { player in
                            Toggle(
                                isOn: Binding(
                                    get: { store.isPlayerUnavailable(player.id) },
                                    set: { store.setPlayerUnavailable(player.id, unavailable: $0) }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(player.name.isEmpty ? "New Player" : player.name)
                                    Text(store.formattedPlayTime(for: player.id))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Game Availability")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct GameReportView: View {
    @EnvironmentObject private var store: SoccerCoachStore
    @Environment(\.dismiss) private var dismiss

    let game: SavedGameStats

    private struct PlayerLine: Identifiable {
        let id: String
        let name: String
        let jerseyNumber: String
        let seconds: Int
    }

    private var totalGameSeconds: Int {
        max(game.gameLengthMinutes * 60, 1)
    }

    private var playerLines: [PlayerLine] {
        let allIDs = Set(game.playerNames.keys).union(game.playerSeconds.keys)
        return allIDs.map { id in
            PlayerLine(
                id: id,
                name: game.playerNames[id]?.isEmpty == false ? game.playerNames[id]! : "Unnamed Player",
                jerseyNumber: game.playerJerseyNumbers[id] ?? "",
                seconds: game.playerSeconds[id] ?? 0
            )
        }
        .sorted { lhs, rhs in
            lhs.seconds == rhs.seconds ? lhs.name < rhs.name : lhs.seconds > rhs.seconds
        }
    }

    private var secondsPlayedValues: [Int] {
        playerLines.map(\.seconds)
    }

    private var averageSeconds: Int {
        guard !secondsPlayedValues.isEmpty else { return 0 }
        return secondsPlayedValues.reduce(0, +) / secondsPlayedValues.count
    }

    private var spreadSeconds: Int {
        guard let lo = secondsPlayedValues.min(), let hi = secondsPlayedValues.max() else { return 0 }
        return hi - lo
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(game.opponentName.isEmpty ? "Untitled Opponent" : "vs. \(game.opponentName)")
                            .font(.title3.weight(.bold))
                        Text(game.gameDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(game.gameLengthMinutes) min game")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Average")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(store.formatDuration(averageSeconds))
                                .font(.headline)
                                .monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Spread")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(store.formatDuration(spreadSeconds))
                                .font(.headline)
                                .monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Players")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(playerLines.count)")
                                .font(.headline)
                        }
                    }
                }

                Section("Playing Time") {
                    if playerLines.isEmpty {
                        Text("No playing time was recorded for this game.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(playerLines) { line in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(line.jerseyNumber.isEmpty ? line.name : "#\(line.jerseyNumber) \(line.name)")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(store.formatDuration(line.seconds))
                                        .font(.system(.subheadline, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: Double(min(line.seconds, totalGameSeconds)), total: Double(totalGameSeconds))
                                    .tint(line.seconds == 0 ? .red : .green)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle(game.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct GameHistoryView: View {
    @EnvironmentObject private var store: SoccerCoachStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if store.data.savedGames.isEmpty {
                    Text("Save a game from the Game tab to see it here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.data.savedGames) { game in
                        NavigationLink {
                            GameReportView(game: game)
                                .environmentObject(store)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(game.opponentName.isEmpty ? game.title : "vs. \(game.opponentName)")
                                    .font(.subheadline.weight(.semibold))
                                Text(game.gameDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        store.deleteSavedGames(atOffsets: offsets)
                    }
                }
            }
            .navigationTitle("Game History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct RosterView: View {
    @EnvironmentObject private var store: SoccerCoachStore
    @State private var pendingDeletePlayerID: UUID?
    @State private var editingPlayerID: UUID?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Team Size")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(store.data.players.count) players")
                            .font(.headline.weight(.bold))
                    }

                    Button {
                        let newPlayerID = store.addPlayer()
                        editingPlayerID = newPlayerID
                    } label: {
                        Label("Add Player", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Section("Players") {
                    if store.data.players.isEmpty {
                        Text("No players yet. Tap Add Player to start your roster.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.data.players.map(\.id), id: \.self) { playerID in
                            if let player = store.player(for: playerID) {
                                Button {
                                    editingPlayerID = playerID
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(player.name.isEmpty ? "New Player" : player.name)
                                                .font(.headline)
                                                .foregroundStyle(.primary)

                                            Text(playerSubtitle(player))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDeletePlayerID = playerID
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Roster (\(store.data.players.count))")
            .sheet(item: editingTargetBinding) { target in
                RosterPlayerEditorView(playerID: target.id)
                    .environmentObject(store)
            }
            .confirmationDialog(
                "Remove this player?",
                isPresented: Binding(
                    get: { pendingDeletePlayerID != nil },
                    set: { if !$0 { pendingDeletePlayerID = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove Player", role: .destructive) {
                    if let playerID = pendingDeletePlayerID {
                        removePlayer(playerID)
                    }
                    pendingDeletePlayerID = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletePlayerID = nil
                }
            }
        }
    }

    private func playerSubtitle(_ player: Player) -> String {
        let jerseyText = player.jerseyNumber.isEmpty ? "No jersey" : "#\(player.jerseyNumber)"
        let positionsText = player.playablePositions.isEmpty ? "No positions yet" : player.playablePositions.joined(separator: ", ")
        return "\(jerseyText) • \(positionsText)"
    }

    private var editingTargetBinding: Binding<RosterEditorTarget?> {
        Binding(
            get: {
                guard let editingPlayerID else { return nil }
                return RosterEditorTarget(id: editingPlayerID)
            },
            set: { newValue in
                editingPlayerID = newValue?.id
            }
        )
    }

    private func removePlayer(_ playerID: UUID) {
        guard let index = store.data.players.firstIndex(where: { $0.id == playerID }) else { return }
        store.removePlayers(at: IndexSet(integer: index))
    }

    private struct RosterEditorTarget: Identifiable {
        let id: UUID
    }
}

struct RosterPlayerEditorView: View {
    @EnvironmentObject private var store: SoccerCoachStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: FocusField?

    let playerID: UUID

    private enum FocusField: Hashable {
        case name
        case jersey
    }

    var body: some View {
        NavigationStack {
            Form {
                if playerIndex != nil {
                    Section("Player Info") {
                        TextField("Player name", text: playerNameBinding)
                            .focused($focusedField, equals: .name)
                        TextField("Jersey", text: jerseyNumberBinding)
                            .focused($focusedField, equals: .jersey)
                    }

                    Section("Playable Positions") {
                        positionPicker(title: "Primary", selected: positionSelectionBinding(slot: 0))
                        positionPicker(title: "Secondary", selected: positionSelectionBinding(slot: 1))
                        positionPicker(title: "Tertiary", selected: positionSelectionBinding(slot: 2))
                    }
                } else {
                    Text("This player was removed.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        focusedField = nil
                        dismiss()
                    }
                }
            }
        }
    }

    private var editorTitle: String {
        guard let index = playerIndex else { return "Edit Player" }
        let name = store.data.players[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Edit Player" : name
    }

    private var playerIndex: Int? {
        store.data.players.firstIndex(where: { $0.id == playerID })
    }

    private var positionOptions: [String] {
        let defaults = [
            "Forward",
            "Left Midfield",
            "Center Midfield",
            "Right Midfield",
            "Left Defense",
            "Right Defense",
            "Goalie"
        ]
        var seen = Set<String>()
        let combined = (defaults + store.data.fieldPositions.map(\.name))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return combined.filter { seen.insert(store.normalizePositionName($0)).inserted }
    }

    private func positionPicker(title: String, selected: Binding<String>) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Picker(title, selection: selected) {
                Text("None").tag("")
                ForEach(positionOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var playerNameBinding: Binding<String> {
        Binding(
            get: {
                guard let index = playerIndex else { return "" }
                return store.data.players[index].name
            },
            set: { newValue in
                guard let index = playerIndex else { return }
                store.data.players[index].name = newValue
                store.queueAutosave()
            }
        )
    }

    private var jerseyNumberBinding: Binding<String> {
        Binding(
            get: {
                guard let index = playerIndex else { return "" }
                return store.data.players[index].jerseyNumber
            },
            set: { newValue in
                guard let index = playerIndex else { return }
                store.data.players[index].jerseyNumber = newValue
                store.queueAutosave()
            }
        )
    }

    private func positionSelectionBinding(slot: Int) -> Binding<String> {
        Binding(
            get: {
                guard let index = playerIndex else { return "" }
                let positions = store.data.players[index].playablePositions
                guard positions.indices.contains(slot) else { return "" }
                return positions[slot]
            },
            set: { newValue in
                guard let index = playerIndex else { return }
                var positions = store.data.players[index].playablePositions
                if positions.count < 3 {
                    positions += Array(repeating: "", count: max(0, 3 - positions.count))
                }
                positions[slot] = newValue
                positions = positions.filter { !$0.isEmpty }
                var unique: [String] = []
                for position in positions where !unique.contains(where: {
                    store.normalizePositionName($0) == store.normalizePositionName(position)
                }) {
                    unique.append(position)
                }
                store.data.players[index].playablePositions = unique
                store.queueAutosave()
            }
        )
    }
}

struct PracticePlansView: View {
    @EnvironmentObject private var store: SoccerCoachStore
    @State private var randomGroupSize = 3
    @State private var randomGroups: [[Player]] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Random Groups") {
                    if store.data.players.isEmpty {
                        Text("Add players to your roster to create random practice groups.")
                            .foregroundStyle(.secondary)
                    } else {
                        Stepper(
                            "Players per group: \(randomGroupSize)",
                            value: $randomGroupSize,
                            in: 2...max(2, store.data.players.count)
                        )

                        Button("Create Random Groups") {
                            randomGroups = buildRandomGroups(from: store.data.players, groupSize: randomGroupSize)
                        }
                        .buttonStyle(.borderedProminent)

                        if randomGroups.isEmpty {
                            Text("Tap Create Random Groups to split the roster.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(randomGroups.enumerated()), id: \.offset) { index, group in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Group \(index + 1)")
                                        .font(.headline)
                                    ForEach(group, id: \.id) { player in
                                        Text(playerDisplayName(player))
                                            .font(.subheadline)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                Section {
                    Button("New Practice Plan") {
                        store.addPracticePlan()
                    }
                }

                Section("Templates") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            templateButton("Passing")
                            templateButton("Shooting")
                            templateButton("Defense")
                        }
                        .padding(.vertical, 4)
                    }
                }

                ForEach(store.data.practicePlans.map(\.id), id: \.self) { planID in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("Practice title", text: planTitleBinding(planID))
                                .textFieldStyle(.roundedBorder)

                            Button(role: .destructive) {
                                removePracticePlan(planID)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        HStack {
                            TextField("Age group", text: planAgeGroupBinding(planID))
                                .textFieldStyle(.roundedBorder)
                            Stepper(
                                "\(planMinutesValue(planID)) min",
                                value: planMinutesBinding(planID),
                                in: 30...120,
                                step: 5
                            )
                        }
                        TextField("Theme", text: planThemeBinding(planID), axis: .vertical)
                            .textFieldStyle(.roundedBorder)

                        ForEach(drillsForPlan(planID).map(\.id), id: \.self) { drillID in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("Drill", text: drillTitleBinding(planID: planID, drillID: drillID))
                                        .textFieldStyle(.roundedBorder)

                                    Button(role: .destructive) {
                                        removeDrill(planID: planID, drillID: drillID)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                }
                                Stepper(
                                    "\(drillMinutesValue(planID: planID, drillID: drillID)) minutes",
                                    value: drillMinutesBinding(planID: planID, drillID: drillID),
                                    in: 5...45,
                                    step: 5
                                )
                                TextField("Drill notes", text: drillNotesBinding(planID: planID, drillID: drillID), axis: .vertical)
                                    .textFieldStyle(.roundedBorder)

                                TextField("Link to video, website, or doc", text: drillLinkBinding(planID: planID, drillID: drillID))
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()

                                DrillImagePicker(
                                    imageData: drillImageBinding(planID: planID, drillID: drillID)
                                )
                            }
                            .padding(10)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button("Add Drill") {
                            addDrill(to: planID)
                        }
                        .buttonStyle(.bordered)

                        TextField("Practice notes", text: planNotesBinding(planID), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Practice Plans")
            .onChange(of: store.data.players.count) { _, _ in
                randomGroups = []
                randomGroupSize = min(max(2, randomGroupSize), max(2, store.data.players.count))
            }
        }
    }

    private func playerDisplayName(_ player: Player) -> String {
        let name = player.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "New Player"
        }
        return name
    }

    private func buildRandomGroups(from roster: [Player], groupSize: Int) -> [[Player]] {
        guard !roster.isEmpty else { return [] }

        let size = max(2, groupSize)
        let shuffled = roster.shuffled()
        var groups: [[Player]] = []
        groups.reserveCapacity((shuffled.count + size - 1) / size)

        var index = 0
        while index < shuffled.count {
            let end = min(index + size, shuffled.count)
            groups.append(Array(shuffled[index..<end]))
            index = end
        }
        return groups
    }

    private func templateButton(_ name: String) -> some View {
        Button(name) {
            store.addPracticeTemplate(named: name)
        }
        .buttonStyle(.bordered)
    }

    private func planIndex(for planID: UUID) -> Int? {
        store.data.practicePlans.firstIndex(where: { $0.id == planID })
    }

    private func drillLocation(planID: UUID, drillID: UUID) -> (planIndex: Int, drillIndex: Int)? {
        guard let planIndex = planIndex(for: planID) else { return nil }
        guard let drillIndex = store.data.practicePlans[planIndex].drills.firstIndex(where: { $0.id == drillID }) else {
            return nil
        }
        return (planIndex, drillIndex)
    }

    private func drillsForPlan(_ planID: UUID) -> [PracticeDrill] {
        guard let planIndex = planIndex(for: planID) else { return [] }
        return store.data.practicePlans[planIndex].drills
    }

    private func removePracticePlan(_ planID: UUID) {
        guard let planIndex = planIndex(for: planID) else { return }
        store.removePracticePlans(at: IndexSet(integer: planIndex))
    }

    private func addDrill(to planID: UUID) {
        guard let planIndex = planIndex(for: planID) else { return }
        store.data.practicePlans[planIndex].drills.append(
            PracticeDrill(title: "", minutes: 10, notes: "")
        )
        store.save()
    }

    private func removeDrill(planID: UUID, drillID: UUID) {
        guard let planIndex = planIndex(for: planID) else { return }
        store.data.practicePlans[planIndex].drills.removeAll { $0.id == drillID }
        store.save()
    }

    private func planTitleBinding(_ planID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let planIndex = planIndex(for: planID) else { return "" }
                return store.data.practicePlans[planIndex].title
            },
            set: { newValue in
                guard let planIndex = planIndex(for: planID) else { return }
                store.data.practicePlans[planIndex].title = newValue
                store.save()
            }
        )
    }

    private func planAgeGroupBinding(_ planID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let planIndex = planIndex(for: planID) else { return "" }
                return store.data.practicePlans[planIndex].ageGroup
            },
            set: { newValue in
                guard let planIndex = planIndex(for: planID) else { return }
                store.data.practicePlans[planIndex].ageGroup = newValue
                store.save()
            }
        )
    }

    private func planMinutesValue(_ planID: UUID) -> Int {
        guard let planIndex = planIndex(for: planID) else { return 60 }
        return store.data.practicePlans[planIndex].totalMinutes
    }

    private func planMinutesBinding(_ planID: UUID) -> Binding<Int> {
        Binding(
            get: { planMinutesValue(planID) },
            set: { newValue in
                guard let planIndex = planIndex(for: planID) else { return }
                store.data.practicePlans[planIndex].totalMinutes = newValue
                store.save()
            }
        )
    }

    private func planThemeBinding(_ planID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let planIndex = planIndex(for: planID) else { return "" }
                return store.data.practicePlans[planIndex].theme
            },
            set: { newValue in
                guard let planIndex = planIndex(for: planID) else { return }
                store.data.practicePlans[planIndex].theme = newValue
                store.save()
            }
        )
    }

    private func planNotesBinding(_ planID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let planIndex = planIndex(for: planID) else { return "" }
                return store.data.practicePlans[planIndex].notes
            },
            set: { newValue in
                guard let planIndex = planIndex(for: planID) else { return }
                store.data.practicePlans[planIndex].notes = newValue
                store.save()
            }
        )
    }

    private func drillTitleBinding(planID: UUID, drillID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let location = drillLocation(planID: planID, drillID: drillID) else { return "" }
                return store.data.practicePlans[location.planIndex].drills[location.drillIndex].title
            },
            set: { newValue in
                guard let location = drillLocation(planID: planID, drillID: drillID) else { return }
                store.data.practicePlans[location.planIndex].drills[location.drillIndex].title = newValue
                store.save()
            }
        )
    }

    private func drillMinutesValue(planID: UUID, drillID: UUID) -> Int {
        guard let location = drillLocation(planID: planID, drillID: drillID) else { return 10 }
        return store.data.practicePlans[location.planIndex].drills[location.drillIndex].minutes
    }

    private func drillMinutesBinding(planID: UUID, drillID: UUID) -> Binding<Int> {
        Binding(
            get: { drillMinutesValue(planID: planID, drillID: drillID) },
            set: { newValue in
                guard let location = drillLocation(planID: planID, drillID: drillID) else { return }
                store.data.practicePlans[location.planIndex].drills[location.drillIndex].minutes = newValue
                store.save()
            }
        )
    }

    private func drillNotesBinding(planID: UUID, drillID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let location = drillLocation(planID: planID, drillID: drillID) else { return "" }
                return store.data.practicePlans[location.planIndex].drills[location.drillIndex].notes
            },
            set: { newValue in
                guard let location = drillLocation(planID: planID, drillID: drillID) else { return }
                store.data.practicePlans[location.planIndex].drills[location.drillIndex].notes = newValue
                store.save()
            }
        )
    }

    private func drillLinkBinding(planID: UUID, drillID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let location = drillLocation(planID: planID, drillID: drillID) else { return "" }
                return store.data.practicePlans[location.planIndex].drills[location.drillIndex].resourceLink
            },
            set: { newValue in
                guard let location = drillLocation(planID: planID, drillID: drillID) else { return }
                store.data.practicePlans[location.planIndex].drills[location.drillIndex].resourceLink = newValue
                store.save()
            }
        )
    }

    private func drillImageBinding(planID: UUID, drillID: UUID) -> Binding<Data?> {
        Binding(
            get: {
                guard let location = drillLocation(planID: planID, drillID: drillID) else { return nil }
                return store.data.practicePlans[location.planIndex].drills[location.drillIndex].imageData
            },
            set: { imageData in
                guard let location = drillLocation(planID: planID, drillID: drillID) else { return }
                store.setDrillImage(planIndex: location.planIndex, drillIndex: location.drillIndex, imageData: imageData)
            }
        )
    }
}

struct DrillImagePicker: View {
    @Binding var imageData: Data?
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label(imageData == nil ? "Add Drill Picture" : "Change Drill Picture", systemImage: "photo")
            }
            .buttonStyle(.bordered)
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            imageData = data
                        }
                    }
                }
            }

            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button("Remove Picture", role: .destructive) {
                    self.imageData = nil
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
