import AuthenticationServices
import SwiftUI
import PhotosUI

struct ContentView: View {
    @EnvironmentObject private var accessController: AccessController

    var body: some View {
        Group {
            if accessController.signedInAccount == nil {
                AccessGateView()
            } else if !accessController.hasActiveSubscription {
                SubscriptionGateView()
            } else {
                CoachHomeView()
            }
        }
        .animation(.easeInOut, value: accessController.signedInAccount != nil)
        .animation(.easeInOut, value: accessController.hasActiveSubscription)
    }
}

struct CoachHomeView: View {
    @EnvironmentObject private var accessController: AccessController

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
                    Label("Practice", systemImage: "clipboard.text.fill")
                }
        }
        .tint(.green)
        .overlay(alignment: .topTrailing) {
            Menu {
                if let account = accessController.signedInAccount {
                    Text(account.displayName)
                    Text(account.email)
                }
                Button("Restore Purchases") {
                    Task {
                        await accessController.restorePurchases()
                    }
                }
                Button("Sign Out", role: .destructive) {
                    accessController.signOut()
                }
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.green)
                    .padding(.trailing, 18)
                    .padding(.top, 10)
            }
        }
    }
}

struct AccessGateView: View {
    @EnvironmentObject private var accessController: AccessController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SoccerCoach")
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                        Text("Quick sideline tools for grade 3/4 soccer, now with a protected coach account.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Plan 7v7 lineups and subs fast", systemImage: "figure.soccer")
                        Label("Run the game timer and track fair play", systemImage: "timer")
                        Label("Save reusable practice plans with notes, links, and pictures", systemImage: "clipboard.text")
                    }
                    .font(.headline)

                    if let message = accessController.lastErrorMessage {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            Task {
                                await accessController.signInWithGoogle()
                            }
                        } label: {
                            Label("Continue With Google", systemImage: "globe")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(accessController.isWorking)

                        SignInWithAppleButton(.signIn) { _ in
                            Task {
                                await accessController.signInWithApple()
                            }
                        } onCompletion: { _ in }
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .disabled(accessController.isWorking)

                        Text("Apple requires Sign in with Apple to be offered alongside Google for public App Store apps, so both options are here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if accessController.requiresAccessSetup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Before release")
                                .font(.headline)
                            Text("Add your Google OAuth client ID, register the callback URL `soccercoach://oauth` in Google Cloud, and create the yearly App Store subscription product.")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

struct SubscriptionGateView: View {
    @EnvironmentObject private var accessController: AccessController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Yearly Coach Plan")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    if let account = accessController.signedInAccount {
                        Text("Signed in as \(account.displayName)")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        featureRow("Live game timer and sub windows", systemImage: "timer")
                        featureRow("Field-based lineup planning", systemImage: "sportscourt")
                        featureRow("Practice plan library", systemImage: "list.bullet.clipboard")
                        featureRow("Fair-play tracking and sub suggestions", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Text("\(accessController.annualPriceLabel) billed yearly")
                        .font(.title2.weight(.semibold))

                    if let message = accessController.lastErrorMessage {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Button("Start Yearly Plan") {
                        Task {
                            await accessController.purchaseAnnualSubscription()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(accessController.isWorking || accessController.subscriptionProduct == nil)

                    Button("Restore Purchases") {
                        Task {
                            await accessController.restorePurchases()
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Use a different account") {
                        accessController.signOut()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    if accessController.subscriptionProduct == nil {
                        Text("The yearly product is not loading yet. Create `com.evanworth.SoccerCoach.pro.yearly` in App Store Connect to activate billing.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private func featureRow(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.green)
            Text(text)
        }
        .font(.headline)
    }
}

struct GameView: View {
    @EnvironmentObject private var store: SoccerCoachStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    timerCard
                    settingsCard
                    lineupCard
                    moveBoardCard
                    fairPlayCard
                    subSuggestionsCard
                    gameNotesCard
                    subPlanCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("SoccerCoach")
            .sheet(item: selectedFieldPositionBinding) { position in
                PositionAssignmentView(position: position)
                    .environmentObject(store)
            }
        }
    }

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game Timer")
                .font(.headline)
            Text(store.formattedTime())
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .center)
            HStack {
                Button(store.timerRunning ? "Pause" : "Start") {
                    store.startPauseTimer()
                }
                .buttonStyle(.borderedProminent)

                Button("Reset") {
                    store.resetTimer()
                }
                .buttonStyle(.bordered)
            }
        }
        .cardStyle()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Setup")
                    .font(.headline)
                Spacer()
                Button("Reset to 7v7") {
                    store.resetToSevenVSevenShape()
                }
                .buttonStyle(.bordered)
                Button("Build Sub Plan") {
                    store.regenerateSubWindows()
                }
                .buttonStyle(.bordered)
            }

            Stepper("Game Length: \(store.data.gameLengthMinutes) min", value: binding(\.gameLengthMinutes), in: 20...90, step: 5)
            Stepper("Sub Interval: \(store.data.substitutionInterval) min", value: binding(\.substitutionInterval), in: 3...15)

            Divider()

            Text("Lineup Presets")
                .font(.subheadline.weight(.semibold))

            HStack {
                TextField("Preset name", text: $store.newPresetName)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    store.saveCurrentLineupPreset()
                }
                .buttonStyle(.borderedProminent)
            }

            if store.data.lineupPresets.isEmpty {
                Text("Save a favorite starting group so you can load it later.")
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

    private var lineupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Position Groupings")
                    .font(.headline)
                Spacer()
                Button("Add Spot") {
                    store.addPosition()
                }
                .buttonStyle(.bordered)
            }

            SevenVSevenFieldView(
                positions: store.data.fieldPositions,
                playerName: { playerID in
                    store.player(for: playerID).map(playerRowTitle) ?? "Open"
                },
                onTapPosition: { position in
                    store.selectedFieldPositionID = position.id
                }
            )

            Text("Quick Assign")
                .font(.subheadline.weight(.semibold))

            ForEach(Array(store.data.fieldPositions.indices), id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Position name", text: Binding(
                            get: { store.data.fieldPositions[index].name },
                            set: {
                                store.data.fieldPositions[index].name = $0
                                store.save()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button(role: .destructive) {
                            store.data.fieldPositions.remove(at: index)
                            store.save()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }

                    Picker("Player", selection: Binding(
                        get: { store.data.fieldPositions[index].assignedPlayerID },
                        set: {
                            store.data.fieldPositions[index].assignedPlayerID = $0
                            store.save()
                        }
                    )) {
                        Text("Open").tag(UUID?.none)
                        ForEach(store.data.players) { player in
                            Text(playerRowTitle(player)).tag(Optional(player.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if !store.benchPlayers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bench")
                        .font(.subheadline.weight(.semibold))
                    ForEach(store.benchPlayers) { player in
                        Text(playerRowTitle(player))
                            .foregroundStyle(.secondary)
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

            ForEach(Array(store.data.subWindows.indices), id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle(isOn: Binding(
                            get: { store.data.subWindows[index].completed },
                            set: {
                                store.data.subWindows[index].completed = $0
                                store.save()
                            }
                        )) {
                            Text("Minute \(store.data.subWindows[index].minuteMark)")
                                .font(.subheadline.weight(.semibold))
                        }
                        Button(role: .destructive) {
                            store.data.subWindows.remove(at: index)
                            store.save()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    Stepper(
                        "Minute: \(store.data.subWindows[index].minuteMark)",
                        value: Binding(
                            get: { store.data.subWindows[index].minuteMark },
                            set: {
                                store.data.subWindows[index].minuteMark = $0
                                store.save()
                            }
                        ),
                        in: 1...store.data.gameLengthMinutes
                    )
                    TextField("Sub plan", text: Binding(
                        get: { store.data.subWindows[index].focus },
                        set: {
                            store.data.subWindows[index].focus = $0
                            store.save()
                        }
                    ), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
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
                Button("Reset Minutes") {
                    store.resetFairPlay()
                }
                .buttonStyle(.bordered)
            }

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
                moveBoardRow(title: "Forward", positions: positionsForBoardRow(["forward"]), tint: Color(red: 0.92, green: 0.83, blue: 0.47))
                moveBoardRow(title: "Midfield", positions: positionsForBoardRow(["leftmidfield", "centermidfield", "rightmidfield"]), tint: Color(red: 0.55, green: 0.80, blue: 0.61))
                moveBoardRow(title: "Defense", positions: positionsForBoardRow(["leftdefense", "rightdefense"]), tint: Color(red: 0.49, green: 0.69, blue: 0.88))
                moveBoardRow(title: "Goalie", positions: positionsForBoardRow(["goalie", "gk"]), tint: Color(red: 0.94, green: 0.65, blue: 0.47))
            }

            BenchDropCard(
                players: store.benchPlayers,
                playerTitle: playerRowTitle,
                tint: Color(red: 0.84, green: 0.84, blue: 0.84),
                onDropPlayer: { playerID in
                    store.movePlayer(playerID, to: nil)
                }
            )
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

    private var subSuggestionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sub Suggestions")
                    .font(.headline)
                Spacer()
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
                        Button("Apply Suggestion") {
                            store.applySuggestedSub(suggestion)
                        }
                        .buttonStyle(.borderedProminent)
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

    private func moveBoardRow(title: String, positions: [FieldPosition], tint: Color) -> some View {
        let assignedCount = positions.compactMap(\.assignedPlayerID).count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.72))
                Spacer()
                Text("\(assignedCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.black.opacity(0.72))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.55))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.75), tint.opacity(0.42)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(positions) { position in
                        PositionDropCard(
                            position: position,
                            playerLabel: store.player(for: position.assignedPlayerID).map(playerRowTitle) ?? "Drop player here",
                            assignedPlayerID: position.assignedPlayerID,
                            onDropPlayer: { playerID in
                                store.movePlayer(playerID, to: position.id)
                            }
                        )
                        .frame(width: 170)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }

    private func positionsForBoardRow(_ names: [String]) -> [FieldPosition] {
        let normalizedTargets = names.map { $0.lowercased().replacingOccurrences(of: " ", with: "") }
        let matches = store.data.fieldPositions.filter { position in
            let normalized = position.name.lowercased().replacingOccurrences(of: " ", with: "")
            return normalizedTargets.contains(normalized)
        }

        if !matches.isEmpty {
            return normalizedTargets.compactMap { target in
                matches.first {
                    $0.name.lowercased().replacingOccurrences(of: " ", with: "") == target
                }
            }
        }

        return store.data.fieldPositions.filter { position in
            let normalized = position.name.lowercased().replacingOccurrences(of: " ", with: "")
            return normalizedTargets.contains { normalized.contains($0) || $0.contains(normalized) }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<AppData, Int>) -> Binding<Int> {
        Binding(
            get: { store.data[keyPath: keyPath] },
            set: {
                store.data[keyPath: keyPath] = $0
                if keyPath == \AppData.gameLengthMinutes {
                    store.resetTimer()
                }
                store.save()
            }
        )
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
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .draggable(assignedPlayerID.uuidString)
            } else {
                Text(playerLabel)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground))
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
    let tint: Color
    let onDropPlayer: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bench")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.7))
                Spacer()
                Text("\(players.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.black.opacity(0.72))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.55))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.8), tint.opacity(0.45)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
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
                    Text(playerTitle(player))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .draggable(player.id.uuidString)
                }
            }
        }
        .padding(12)
        .background(tint.opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
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
    let playerName: (UUID?) -> String
    let onTapPosition: (FieldPosition) -> Void

    private let layout: [(label: String, x: CGFloat, y: CGFloat)] = [
        ("Forward", 0.5, 0.14),
        ("Left Midfield", 0.2, 0.35),
        ("Center Midfield", 0.5, 0.38),
        ("Right Midfield", 0.8, 0.35),
        ("Left Defense", 0.25, 0.67),
        ("Right Defense", 0.75, 0.67),
        ("Goalie", 0.5, 0.88),
    ]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

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
                    .frame(width: size.width * 0.82, height: size.height * 0.78)

                Rectangle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: size.width * 0.38, height: size.height * 0.16)
                    .offset(y: size.height * 0.31)

                Rectangle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: size.width * 0.24, height: size.height * 0.09)
                    .offset(y: size.height * 0.345)

                Circle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: size.width * 0.18, height: size.width * 0.18)
                    .offset(y: -size.height * 0.02)

                Rectangle()
                    .frame(width: size.width * 0.004, height: size.height * 0.78)
                    .foregroundStyle(Color.white.opacity(0.85))

                ForEach(layout, id: \.label) { slot in
                    let position = matchingPosition(named: slot.label)
                    Button {
                        if let position {
                            onTapPosition(position)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(position?.name ?? slot.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            Text(playerName(position?.assignedPlayerID))
                                .font(.caption2)
                                .foregroundStyle(Color.white.opacity(0.92))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(width: 104)
                                .background(Color.black.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding(6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(position == nil)
                    .position(x: size.width * slot.x, y: size.height * slot.y)
                }
            }
        }
        .aspectRatio(0.75, contentMode: .fit)
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

    var body: some View {
        NavigationStack {
            List {
                Section("Recommended for \(position.name)") {
                    Button("Leave Open") {
                        store.assignPlayer(nil, to: position.id)
                        dismiss()
                    }

                    ForEach(store.recommendedPlayers(for: position)) { player in
                        Button {
                            store.assignPlayer(player.id, to: position.id)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(playerLabel(player))
                                    .foregroundStyle(.primary)
                                if !player.playablePositions.isEmpty {
                                    Text(player.playablePositions.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
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
}

struct RosterView: View {
    @EnvironmentObject private var store: SoccerCoachStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Add Player") {
                        store.addPlayer()
                    }
                }

                ForEach(Array(store.data.players.indices), id: \.self) { index in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("Player name", text: Binding(
                                get: { store.data.players[index].name },
                                set: {
                                    store.data.players[index].name = $0
                                    store.save()
                                }
                            ))
                            .textFieldStyle(.roundedBorder)

                            Button(role: .destructive) {
                                store.removePlayers(at: IndexSet(integer: index))
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        HStack {
                            TextField("Jersey", text: Binding(
                                get: { store.data.players[index].jerseyNumber },
                                set: {
                                    store.data.players[index].jerseyNumber = $0
                                    store.save()
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        TextField("Playable positions separated by commas", text: Binding(
                            get: { store.data.players[index].playablePositions.joined(separator: ", ") },
                            set: {
                                store.data.players[index].playablePositions = $0
                                    .split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty }
                                store.save()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Roster")
        }
    }
}

struct PracticePlansView: View {
    @EnvironmentObject private var store: SoccerCoachStore

    var body: some View {
        NavigationStack {
            List {
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

                ForEach(Array(store.data.practicePlans.indices), id: \.self) { planIndex in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("Practice title", text: Binding(
                                get: { store.data.practicePlans[planIndex].title },
                                set: {
                                    store.data.practicePlans[planIndex].title = $0
                                    store.save()
                                }
                            ))
                            .textFieldStyle(.roundedBorder)

                            Button(role: .destructive) {
                                store.removePracticePlans(at: IndexSet(integer: planIndex))
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        HStack {
                            TextField("Age group", text: Binding(
                                get: { store.data.practicePlans[planIndex].ageGroup },
                                set: {
                                    store.data.practicePlans[planIndex].ageGroup = $0
                                    store.save()
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            Stepper(
                                "\(store.data.practicePlans[planIndex].totalMinutes) min",
                                value: Binding(
                                    get: { store.data.practicePlans[planIndex].totalMinutes },
                                    set: {
                                        store.data.practicePlans[planIndex].totalMinutes = $0
                                        store.save()
                                    }
                                ),
                                in: 30...120,
                                step: 5
                            )
                        }
                        TextField("Theme", text: Binding(
                            get: { store.data.practicePlans[planIndex].theme },
                            set: {
                                store.data.practicePlans[planIndex].theme = $0
                                store.save()
                            }
                        ), axis: .vertical)
                            .textFieldStyle(.roundedBorder)

                        ForEach(Array(store.data.practicePlans[planIndex].drills.indices), id: \.self) { drillIndex in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("Drill", text: Binding(
                                        get: { store.data.practicePlans[planIndex].drills[drillIndex].title },
                                        set: {
                                            store.data.practicePlans[planIndex].drills[drillIndex].title = $0
                                            store.save()
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)

                                    Button(role: .destructive) {
                                        store.data.practicePlans[planIndex].drills.remove(at: drillIndex)
                                        store.save()
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                }
                                Stepper(
                                    "\(store.data.practicePlans[planIndex].drills[drillIndex].minutes) minutes",
                                    value: Binding(
                                        get: { store.data.practicePlans[planIndex].drills[drillIndex].minutes },
                                        set: {
                                            store.data.practicePlans[planIndex].drills[drillIndex].minutes = $0
                                            store.save()
                                        }
                                    ),
                                    in: 5...45,
                                    step: 5
                                )
                                TextField("Drill notes", text: Binding(
                                    get: { store.data.practicePlans[planIndex].drills[drillIndex].notes },
                                    set: {
                                        store.data.practicePlans[planIndex].drills[drillIndex].notes = $0
                                        store.save()
                                    }
                                ), axis: .vertical)
                                    .textFieldStyle(.roundedBorder)

                                TextField("Link to video, website, or doc", text: Binding(
                                    get: { store.data.practicePlans[planIndex].drills[drillIndex].resourceLink },
                                    set: {
                                        store.data.practicePlans[planIndex].drills[drillIndex].resourceLink = $0
                                        store.save()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                                DrillImagePicker(
                                    imageData: Binding(
                                        get: { store.data.practicePlans[planIndex].drills[drillIndex].imageData },
                                        set: {
                                            store.setDrillImage(planIndex: planIndex, drillIndex: drillIndex, imageData: $0)
                                        }
                                    )
                                )
                            }
                            .padding(10)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button("Add Drill") {
                            store.data.practicePlans[planIndex].drills.append(
                                PracticeDrill(title: "", minutes: 10, notes: "")
                            )
                            store.save()
                        }
                        .buttonStyle(.bordered)

                        TextField("Practice notes", text: Binding(
                            get: { store.data.practicePlans[planIndex].notes },
                            set: {
                                store.data.practicePlans[planIndex].notes = $0
                                store.save()
                            }
                        ), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Practice Plans")
        }
    }

    private func templateButton(_ name: String) -> some View {
        Button(name) {
            store.addPracticeTemplate(named: name)
        }
        .buttonStyle(.bordered)
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
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
    }
}
