import Foundation
import SwiftUI

struct SuggestedSubstitution: Identifiable, Hashable {
    let id = UUID()
    let positionID: UUID
    let positionName: String
    let playerOutID: UUID
    let playerInID: UUID
    let reason: String
}

private enum PositionFamily: Int {
    case goalie = 0
    case defense = 1
    case midfield = 2
    case forward = 3
    case other = 4
}

private struct SoccerCoachBackupPayload: Codable {
    var version: Int
    var createdAt: Date
    var data: AppData
}

@MainActor
final class SoccerCoachStore: ObservableObject {
    @Published var data: AppData
    @Published var remainingSeconds: Int
    @Published var timerRunning = false
    @Published var photoPickerDrillID: UUID?
    @Published var selectedFieldPositionID: UUID?
    @Published var playerSecondsPlayed: [UUID: Int] = [:]
    @Published var currentStintSecondsPlayed: [UUID: Int] = [:]
    @Published var recentlySubbedOutPlayerID: UUID?
    @Published var suggestedSubs: [SuggestedSubstitution] = []
    @Published var newPresetName = ""
    @Published var backupStatusMessage = ""
    @Published var backupErrorMessage: String?

    private var timerTask: Task<Void, Never>?
    private var timerAnchorDate: Date?
    private var timerAnchorRemainingSeconds: Int = 0
    private var autosaveTask: Task<Void, Never>?
    private let saveURL: URL
    private var dismissedSuggestionKeys = Set<String>()

    init() {
        self.saveURL = Self.makeSaveURL()
        let initialData: AppData
        if
            let savedData = try? Data(contentsOf: saveURL),
            let decoded = try? JSONDecoder().decode(AppData.self, from: savedData)
        {
            initialData = decoded
        } else {
            initialData = .default
        }
        self.data = initialData
        self.remainingSeconds = initialData.liveRemainingSeconds ?? (initialData.gameLengthMinutes * 60)
        self.timerRunning = initialData.liveTimerRunning
        self.timerAnchorDate = initialData.liveTimerAnchorDate
        self.timerAnchorRemainingSeconds = initialData.liveTimerAnchorRemainingSeconds > 0
            ? initialData.liveTimerAnchorRemainingSeconds
            : self.remainingSeconds

        // Release rule: game is fixed at two 30-minute halves.
        if data.gameLengthMinutes != 30 {
            data.gameLengthMinutes = 30
            if !timerRunning {
                let halfSeconds = 30 * 60
                if currentHalf == 1 {
                    remainingSeconds = halfSeconds
                } else {
                    remainingSeconds = min(remainingSeconds, halfSeconds)
                }
                timerAnchorRemainingSeconds = remainingSeconds
            }
            save()
        }

        if timerRunning {
            if timerAnchorDate != nil {
                syncTimerWithWallClock()
                if remainingSeconds > 0 {
                    startTickerTask()
                } else {
                    timerRunning = false
                }
            } else {
                timerRunning = false
            }
        }
    }

    deinit {
        timerTask?.cancel()
        autosaveTask?.cancel()
    }

    var assignedPlayerIDs: Set<UUID> {
        Set(data.fieldPositions.compactMap(\.assignedPlayerID))
    }

    var unavailablePlayerIDs: Set<UUID> {
        Set(data.unavailablePlayerIDs)
    }

    var availablePlayers: [Player] {
        data.players.filter { !unavailablePlayerIDs.contains($0.id) }
    }

    var benchPlayers: [Player] {
        availablePlayers.filter { !assignedPlayerIDs.contains($0.id) }
    }

    var onFieldPlayers: [Player] {
        data.fieldPositions.compactMap { player(for: $0.assignedPlayerID) }
    }

    var currentHalf: Int {
        max(1, min(2, data.currentHalf))
    }

    var preferredColorScheme: ColorScheme? {
        switch data.appTheme {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var savedGameCount: Int {
        data.savedGames.count
    }

    var shouldShowCoachOnboarding: Bool {
        !data.hasSeenCoachOnboarding
    }

    func player(for id: UUID?) -> Player? {
        guard let id else { return nil }
        return data.players.first { $0.id == id }
    }

    func position(for id: UUID) -> FieldPosition? {
        data.fieldPositions.first { $0.id == id }
    }

    func createBackupFile() throws -> URL {
        backupErrorMessage = nil
        let backup = SoccerCoachBackupPayload(
            version: 1,
            createdAt: .now,
            data: data
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let backupData = try encoder.encode(backup)
        let timestamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "soccercoach-backup-\(timestamp).json"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try backupData.write(to: destination, options: .atomic)
        backupStatusMessage = "Backup created."
        return destination
    }

    func importBackup(from sourceURL: URL) throws {
        backupErrorMessage = nil
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let importedData = try Data(contentsOf: sourceURL)
        let decoder = JSONDecoder()
        let restoredData: AppData
        if let envelope = try? decoder.decode(SoccerCoachBackupPayload.self, from: importedData) {
            restoredData = envelope.data
        } else {
            restoredData = try decoder.decode(AppData.self, from: importedData)
        }

        timerTask?.cancel()
        timerTask = nil
        timerRunning = false
        timerAnchorDate = nil
        timerAnchorRemainingSeconds = restoredData.gameLengthMinutes * 60
        data = restoredData
        remainingSeconds = restoredData.gameLengthMinutes * 60
        cleanupInvalidPlayerReferences()
        refreshSuggestedSubs()
        save()
        backupStatusMessage = "Backup restored with \(data.players.count) player(s)."
    }

    @discardableResult
    func addPlayer() -> UUID {
        let player = Player(name: "", jerseyNumber: "", playablePositions: [])
        data.players.insert(player, at: 0)
        save()
        return player.id
    }

    func assignPlayer(_ playerID: UUID?, to positionID: UUID) {
        guard let index = data.fieldPositions.firstIndex(where: { $0.id == positionID }) else { return }
        if let playerID, unavailablePlayerIDs.contains(playerID) { return }
        let wasOnFieldBefore = playerID.map { assignedPlayerIDs.contains($0) } ?? false
        let previousPlayerInSpot = data.fieldPositions[index].assignedPlayerID
        if let playerID, let existingIndex = data.fieldPositions.firstIndex(where: { $0.assignedPlayerID == playerID && $0.id != positionID }) {
            data.fieldPositions[existingIndex].assignedPlayerID = data.fieldPositions[index].assignedPlayerID
        }
        data.fieldPositions[index].assignedPlayerID = playerID
        if let previousPlayerInSpot, previousPlayerInSpot != playerID {
            recentlySubbedOutPlayerID = previousPlayerInSpot
            currentStintSecondsPlayed[previousPlayerInSpot] = 0
        }
        if let playerID, !wasOnFieldBefore {
            currentStintSecondsPlayed[playerID] = 0
        }
        data.nextPlayerByPositionID[positionID.uuidString] = nil
        refreshSuggestedSubs()
        save()
    }

    func benchPlayer(_ playerID: UUID) {
        guard let index = data.fieldPositions.firstIndex(where: { $0.assignedPlayerID == playerID }) else { return }
        data.fieldPositions[index].assignedPlayerID = nil
        recentlySubbedOutPlayerID = playerID
        currentStintSecondsPlayed[playerID] = 0
        refreshSuggestedSubs()
        save()
    }

    func movePlayer(_ playerID: UUID, to positionID: UUID?) {
        if let positionID {
            assignPlayer(playerID, to: positionID)
        } else {
            benchPlayer(playerID)
        }
    }

    func queuedNextPlayerID(for positionID: UUID) -> UUID? {
        data.nextPlayerByPositionID[positionID.uuidString]
    }

    func queuedNextPlayer(for positionID: UUID) -> Player? {
        guard let playerID = queuedNextPlayerID(for: positionID) else { return nil }
        return player(for: playerID)
    }

    func setQueuedNextPlayer(_ playerID: UUID?, for positionID: UUID) {
        if let playerID, unavailablePlayerIDs.contains(playerID) { return }
        data.nextPlayerByPositionID[positionID.uuidString] = playerID
        save()
    }

    func applyQueuedNextPlayer(for positionID: UUID) {
        guard let playerID = queuedNextPlayerID(for: positionID) else { return }
        if unavailablePlayerIDs.contains(playerID) { return }
        assignPlayer(playerID, to: positionID)
    }

    func applyAllQueuedNextPlayers() {
        let queue = data.nextPlayerByPositionID
        guard !queue.isEmpty else { return }

        for position in data.fieldPositions {
            guard let queuedID = queue[position.id.uuidString] else { continue }
            if unavailablePlayerIDs.contains(queuedID) { continue }
            assignPlayer(queuedID, to: position.id)
        }
        refreshSuggestedSubs()
        save()
    }

    func recommendedPlayers(for position: FieldPosition) -> [Player] {
        let targetName = position.name
        return availablePlayers.sorted { lhs, rhs in
            let lhsRank = bestPositionMatchRank(for: lhs, targetPositionName: targetName)
            let rhsRank = bestPositionMatchRank(for: rhs, targetPositionName: targetName)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            if lhsRank == Int.max {
                return lhs.name < rhs.name
            }
            let lhsTime = playerSecondsPlayed[lhs.id, default: 0]
            let rhsTime = playerSecondsPlayed[rhs.id, default: 0]
            if lhsTime != rhsTime {
                return lhsTime < rhsTime
            }
            return lhs.name < rhs.name
        }
    }

    func isPlayerUnavailable(_ playerID: UUID) -> Bool {
        unavailablePlayerIDs.contains(playerID)
    }

    func setPlayerUnavailable(_ playerID: UUID, unavailable: Bool) {
        var set = unavailablePlayerIDs
        if unavailable {
            set.insert(playerID)
        } else {
            set.remove(playerID)
        }
        data.unavailablePlayerIDs = Array(set)

        if unavailable {
            for index in data.fieldPositions.indices where data.fieldPositions[index].assignedPlayerID == playerID {
                data.fieldPositions[index].assignedPlayerID = nil
            }
            data.nextPlayerByPositionID = data.nextPlayerByPositionID.filter { _, queuedID in
                queuedID != playerID
            }
            if recentlySubbedOutPlayerID == playerID {
                recentlySubbedOutPlayerID = nil
            }
        }

        refreshSuggestedSubs()
        save()
    }

    func formattedPlayTime(for playerID: UUID) -> String {
        let totalSeconds = playerSecondsPlayed[playerID, default: 0]
        return formatDuration(totalSeconds)
    }

    func formattedSeasonPlayTime(for playerID: UUID) -> String {
        formatDuration(seasonSeconds(for: playerID))
    }

    func seasonSeconds(for playerID: UUID) -> Int {
        let key = playerID.uuidString
        return data.savedGames.reduce(0) { partial, game in
            partial + (game.playerSeconds[key] ?? 0)
        }
    }

    @discardableResult
    func saveCurrentGameStats() -> SavedGameStats {
        let title = "Game \(data.savedGames.count + 1)"
        let secondsByPlayerID = Dictionary(
            uniqueKeysWithValues: playerSecondsPlayed.map { ($0.key.uuidString, $0.value) }
        )
        let namesByPlayerID = Dictionary(
            uniqueKeysWithValues: data.players.map { ($0.id.uuidString, $0.name) }
        )
        let jerseyNumbersByPlayerID = Dictionary(
            uniqueKeysWithValues: data.players.map { ($0.id.uuidString, $0.jerseyNumber) }
        )
        let saved = SavedGameStats(
            title: title,
            opponentName: data.gameOpponentName,
            gameDate: data.gameDate,
            gameLengthMinutes: data.gameLengthMinutes,
            playerSeconds: secondsByPlayerID,
            playerNames: namesByPlayerID,
            playerJerseyNumbers: jerseyNumbersByPlayerID
        )
        data.savedGames.insert(saved, at: 0)
        save()
        return saved
    }

    func deleteSavedGames(atOffsets offsets: IndexSet) {
        data.savedGames.remove(atOffsets: offsets)
        save()
    }

    func setAppTheme(_ theme: AppTheme) {
        data.appTheme = theme
        save()
    }

    func markCoachOnboardingSeen() {
        data.hasSeenCoachOnboarding = true
        save()
    }

    func showCoachOnboardingAgain() {
        data.hasSeenCoachOnboarding = false
        save()
    }

    func loadSampleCoachingData() {
        let samplePlayers = AppData.default.players.map { player in
            Player(
                id: UUID(),
                name: player.name,
                jerseyNumber: player.jerseyNumber,
                playablePositions: player.playablePositions
            )
        }

        data.players = samplePlayers
        data.gameFormation = .twoThreeOne
        data.fieldPositions = AppData.default.fieldPositions.map { position in
            FieldPosition(
                id: UUID(),
                name: position.name,
                assignedPlayerID: nil
            )
        }
        data.practicePlans = AppData.default.practicePlans
        data.subWindows = AppData.default.subWindows
        data.lineupPresets = []
        data.nextPlayerByPositionID = [:]
        data.unavailablePlayerIDs = []
        data.gameOpponentName = ""
        data.gameDate = .now
        resetTimer()
        save()
    }

    func formatDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func resetFairPlay() {
        playerSecondsPlayed = [:]
        currentStintSecondsPlayed = [:]
        recentlySubbedOutPlayerID = nil
        refreshSuggestedSubs()
    }

    func applySuggestedSub(_ suggestion: SuggestedSubstitution) {
        assignPlayer(suggestion.playerInID, to: suggestion.positionID)
        dismissedSuggestionKeys.remove(suggestionKey(for: suggestion))
        refreshSuggestedSubs()
        save()
    }

    func applyAllSuggestedSubs() {
        let queuedSuggestions = suggestedSubs
        guard !queuedSuggestions.isEmpty else { return }

        for suggestion in queuedSuggestions {
            assignPlayer(suggestion.playerInID, to: suggestion.positionID)
            dismissedSuggestionKeys.remove(suggestionKey(for: suggestion))
        }
        refreshSuggestedSubs()
        save()
    }

    func dismissSuggestedSub(_ suggestion: SuggestedSubstitution) {
        dismissedSuggestionKeys.insert(suggestionKey(for: suggestion))
        suggestedSubs.removeAll { $0.id == suggestion.id }
    }

    func addPracticeTemplate(named name: String) {
        let template: PracticePlan
        switch name {
        case "Passing":
            template = PracticePlan(
                title: "Passing Template",
                ageGroup: "Grade 3/4 Girls",
                totalMinutes: 60,
                theme: "Passing and support angles",
                drills: [
                    PracticeDrill(title: "Partner Passing", minutes: 10, notes: "Focus on soft first touch and passing with the inside of the foot."),
                    PracticeDrill(title: "Triangle Passing", minutes: 15, notes: "Pass and move to a new cone after every pass."),
                    PracticeDrill(title: "Keep Away", minutes: 15, notes: "Create space quickly and give the player on the ball two passing options."),
                    PracticeDrill(title: "Scrimmage", minutes: 20, notes: "Praise players for finding a pass before dribbling into traffic.")
                ],
                notes: "Keep the field small enough to encourage lots of touches."
            )
        case "Shooting":
            template = PracticePlan(
                title: "Shooting Template",
                ageGroup: "Grade 3/4 Girls",
                totalMinutes: 60,
                theme: "Quick shots and finishing confidence",
                drills: [
                    PracticeDrill(title: "Dribble and Shoot", minutes: 10, notes: "Small touches into space, then strike with laces."),
                    PracticeDrill(title: "Pass to Finish", minutes: 15, notes: "First touch out of feet and shoot early."),
                    PracticeDrill(title: "Numbers to Goal", minutes: 15, notes: "Attack with speed and shoot when a lane opens."),
                    PracticeDrill(title: "Scrimmage to End Zones", minutes: 20, notes: "Reward shots taken after smart buildup.")
                ],
                notes: "Rotate goalkeepers often if needed."
            )
        default:
            template = PracticePlan(
                title: "\(name) Template",
                ageGroup: "Grade 3/4 Girls",
                totalMinutes: 60,
                theme: name,
                drills: [
                    PracticeDrill(title: "Warmup", minutes: 10, notes: ""),
                    PracticeDrill(title: "Main Activity", minutes: 20, notes: ""),
                    PracticeDrill(title: "Game", minutes: 20, notes: "")
                ],
                notes: ""
            )
        }

        data.practicePlans.insert(template, at: 0)
        save()
    }

    func refreshSuggestedSubs() {
        var suggestions: [SuggestedSubstitution] = []
        var usedBenchPlayers = Set<UUID>()

        for position in data.fieldPositions {
            guard
                let currentPlayerID = position.assignedPlayerID,
                let currentPlayer = player(for: currentPlayerID)
            else { continue }

            if isGoaliePositionName(position.name) {
                continue
            }
            let rankedCandidates = benchPlayers
                .filter { !usedBenchPlayers.contains($0.id) }
                .map { player in
                    (player, bestPositionMatchRank(for: player, targetPositionName: position.name))
                }
                .filter { $0.1 < Int.max }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 {
                        return lhs.1 < rhs.1
                    }
                    let lhsTime = playerSecondsPlayed[lhs.0.id, default: 0]
                    let rhsTime = playerSecondsPlayed[rhs.0.id, default: 0]
                    if lhsTime != rhsTime {
                        return lhsTime < rhsTime
                    }
                    return lhs.0.name < rhs.0.name
                }

            guard let playerIn = rankedCandidates.first?.0 else { continue }

            let currentStint = currentStintSecondsPlayed[currentPlayerID, default: 0]
            guard currentStint >= 300 else { continue }

            let suggestion = SuggestedSubstitution(
                positionID: position.id,
                positionName: position.name,
                playerOutID: currentPlayer.id,
                playerInID: playerIn.id,
                reason: "\(currentPlayer.name) has been in for \(formatDuration(currentStint))."
            )
            if dismissedSuggestionKeys.contains(suggestionKey(for: suggestion)) {
                continue
            }
            suggestions.append(suggestion)
            usedBenchPlayers.insert(playerIn.id)
        }

        suggestedSubs = suggestions.sorted {
            playerSecondsPlayed[$0.playerOutID, default: 0] > playerSecondsPlayed[$1.playerOutID, default: 0]
        }
    }

    func normalizePositionName(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private func positionFamily(for positionName: String) -> PositionFamily {
        let normalized = normalizePositionName(positionName)
        if normalized.contains("goalie") || normalized == "gk" || normalized.contains("keeper") {
            return .goalie
        }
        if normalized.contains("defense") || normalized.contains("defender") || normalized.contains("back") {
            return .defense
        }
        if normalized.contains("midfield") || normalized.contains("mid") {
            return .midfield
        }
        if normalized.contains("forward") || normalized.contains("striker") || normalized.contains("offense") || normalized.contains("attack") || normalized.contains("wing") {
            return .forward
        }
        return .other
    }

    func isGoaliePositionName(_ positionName: String) -> Bool {
        positionFamily(for: positionName) == .goalie
    }

    func positionMatchRank(playerPositionName: String, targetPositionName: String) -> Int {
        let normalizedPlayer = normalizePositionName(playerPositionName)
        let normalizedTarget = normalizePositionName(targetPositionName)
        if normalizedPlayer == normalizedTarget {
            return 0
        }
        let playerFamily = positionFamily(for: playerPositionName)
        let targetFamily = positionFamily(for: targetPositionName)
        if playerFamily != .other, playerFamily == targetFamily {
            return 1
        }
        if normalizedPlayer.contains(normalizedTarget) || normalizedTarget.contains(normalizedPlayer) {
            return 2
        }
        return Int.max
    }

    func bestPositionMatchRank(for player: Player, targetPositionName: String) -> Int {
        player.playablePositions
            .map { positionMatchRank(playerPositionName: $0, targetPositionName: targetPositionName) }
            .min() ?? Int.max
    }

    func removePlayers(at offsets: IndexSet) {
        let removedIDs = Set(offsets.map { data.players[$0].id })
        data.players.remove(atOffsets: offsets)
        data.unavailablePlayerIDs.removeAll { removedIDs.contains($0) }
        for index in data.fieldPositions.indices {
            if let assignedID = data.fieldPositions[index].assignedPlayerID, removedIDs.contains(assignedID) {
                data.fieldPositions[index].assignedPlayerID = nil
            }
        }
        data.nextPlayerByPositionID = data.nextPlayerByPositionID.filter { _, queuedPlayerID in
            !removedIDs.contains(queuedPlayerID)
        }
        removedIDs.forEach { playerSecondsPlayed.removeValue(forKey: $0) }
        refreshSuggestedSubs()
        save()
    }

    func addPosition() {
        data.fieldPositions.append(FieldPosition(name: "New Position"))
        refreshSuggestedSubs()
        save()
    }

    func setGameFormation(_ formation: GameFormation) {
        guard data.gameFormation != formation else { return }
        data.gameFormation = formation
        rebuildFieldPositions(for: formation)
        refreshSuggestedSubs()
        save()
    }

    func resetToSevenVSevenShape() {
        rebuildFieldPositions(for: data.gameFormation)
        refreshSuggestedSubs()
        save()
    }

    private func rebuildFieldPositions(for formation: GameFormation) {
        var oldPositions = data.fieldPositions
        var usedOldIDs = Set<UUID>()
        var rebuilt: [FieldPosition] = []
        var newQueueByPositionID: [String: UUID] = [:]

        for name in formation.positionNames {
            let normalizedTarget = normalizePositionName(name)
            let exactMatch = oldPositions.first {
                !usedOldIDs.contains($0.id) && normalizePositionName($0.name) == normalizedTarget
            }
            let roleMatch = oldPositions.first {
                !usedOldIDs.contains($0.id) && positionMatchRank(playerPositionName: $0.name, targetPositionName: name) <= 1
            }
            let fallbackMatch = oldPositions.first { !usedOldIDs.contains($0.id) }
            let source = exactMatch ?? roleMatch ?? fallbackMatch

            let id = source?.id ?? UUID()
            let assignedPlayerID = source?.assignedPlayerID
            let queuedPlayerID = source.flatMap { data.nextPlayerByPositionID[$0.id.uuidString] }

            rebuilt.append(
                FieldPosition(
                    id: id,
                    name: name,
                    assignedPlayerID: assignedPlayerID
                )
            )
            if let queuedPlayerID {
                newQueueByPositionID[id.uuidString] = queuedPlayerID
            }
            if let source {
                usedOldIDs.insert(source.id)
            }
        }

        oldPositions.removeAll { usedOldIDs.contains($0.id) }

        for leftover in oldPositions where leftover.assignedPlayerID != nil {
            let leftoverFamily = positionFamily(for: leftover.name)
            guard
                let targetIndex = rebuilt.firstIndex(where: { position in
                    position.assignedPlayerID == nil && positionFamily(for: position.name) == leftoverFamily
                })
            else { continue }
            rebuilt[targetIndex].assignedPlayerID = leftover.assignedPlayerID
        }

        data.fieldPositions = rebuilt
        data.nextPlayerByPositionID = newQueueByPositionID.filter { _, playerID in
            !unavailablePlayerIDs.contains(playerID)
        }
    }

    func saveCurrentLineupPreset() {
        let trimmedName = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let assignments = Dictionary(uniqueKeysWithValues: data.fieldPositions.map {
            (normalizePositionName($0.name), $0.assignedPlayerID)
        })

        if let existingIndex = data.lineupPresets.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            data.lineupPresets[existingIndex].assignments = assignments
        } else {
            data.lineupPresets.insert(
                LineupPreset(name: trimmedName, assignments: assignments),
                at: 0
            )
        }

        newPresetName = ""
        save()
    }

    func applyLineupPreset(_ preset: LineupPreset) {
        for index in data.fieldPositions.indices {
            let key = normalizePositionName(data.fieldPositions[index].name)
            if let assignment = preset.assignments[key] {
                data.fieldPositions[index].assignedPlayerID = assignment
            }
        }
        refreshSuggestedSubs()
        save()
    }

    func deleteLineupPresets(at offsets: IndexSet) {
        data.lineupPresets.remove(atOffsets: offsets)
        save()
    }

    func removePositions(at offsets: IndexSet) {
        let removedPositionIDs = Set(offsets.map { data.fieldPositions[$0].id.uuidString })
        data.fieldPositions.remove(atOffsets: offsets)
        data.nextPlayerByPositionID = data.nextPlayerByPositionID.filter { key, _ in
            !removedPositionIDs.contains(key)
        }
        refreshSuggestedSubs()
        save()
    }

    func addPracticePlan() {
        data.practicePlans.insert(
            PracticePlan(
                title: "New Practice",
                ageGroup: "Grade 3/4 Girls",
                totalMinutes: 60,
                theme: "",
                drills: [
                    PracticeDrill(title: "Warmup", minutes: 10, notes: ""),
                    PracticeDrill(title: "Main Activity", minutes: 20, notes: "")
                ],
                notes: ""
            ),
            at: 0
        )
        save()
    }

    func setDrillImage(planIndex: Int, drillIndex: Int, imageData: Data?) {
        guard data.practicePlans.indices.contains(planIndex) else { return }
        guard data.practicePlans[planIndex].drills.indices.contains(drillIndex) else { return }
        data.practicePlans[planIndex].drills[drillIndex].imageData = imageData
        save()
    }

    func removePracticePlans(at offsets: IndexSet) {
        data.practicePlans.remove(atOffsets: offsets)
        save()
    }

    func addSubWindow() {
        let nextMinute = (data.subWindows.map(\.minuteMark).max() ?? 0) + data.substitutionInterval
        data.subWindows.append(SubWindow(minuteMark: nextMinute, focus: "", completed: false))
        save()
    }

    func removeSubWindows(at offsets: IndexSet) {
        data.subWindows.remove(atOffsets: offsets)
        save()
    }

    func regenerateSubWindows() {
        let total = max(data.gameLengthMinutes, data.substitutionInterval)
        let interval = max(data.substitutionInterval, 1)
        data.subWindows = stride(from: interval, to: total, by: interval).map {
            SubWindow(minuteMark: $0, focus: "Plan subs", completed: false)
        }
        remainingSeconds = total * 60
        save()
    }

    func startPauseTimer() {
        if timerRunning {
            syncTimerWithWallClock()
            timerRunning = false
            timerAnchorDate = nil
            timerAnchorRemainingSeconds = remainingSeconds
            timerTask?.cancel()
            timerTask = nil
            save()
            return
        }

        if remainingSeconds <= 0 {
            if currentHalf == 1 {
                data.currentHalf = 2
                remainingSeconds = data.gameLengthMinutes * 60
                timerAnchorRemainingSeconds = remainingSeconds
            } else {
                return
            }
        }

        timerRunning = true
        timerAnchorDate = .now
        timerAnchorRemainingSeconds = remainingSeconds
        startTickerTask()
        save()
    }

    func startSecondHalf() {
        guard currentHalf == 1 else { return }

        timerRunning = false
        timerTask?.cancel()
        timerTask = nil
        timerAnchorDate = nil

        data.currentHalf = 2
        data.gameLengthMinutes = 30
        remainingSeconds = 30 * 60
        timerAnchorRemainingSeconds = remainingSeconds
        save()

        startPauseTimer()
    }

    private func startTickerTask() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled && remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    syncTimerWithWallClock()
                }
            }
        }
    }

    private func syncTimerWithWallClock() {
        guard timerRunning, let anchorDate = timerAnchorDate else { return }

        let elapsed = max(Int(Date().timeIntervalSince(anchorDate)), 0)
        let updatedRemaining = max(timerAnchorRemainingSeconds - elapsed, 0)
        let delta = max(remainingSeconds - updatedRemaining, 0)

        if delta > 0 {
            for playerID in assignedPlayerIDs {
                playerSecondsPlayed[playerID, default: 0] += delta
                currentStintSecondsPlayed[playerID, default: 0] += delta
            }
            if delta >= 10 || updatedRemaining % 10 == 0 {
                refreshSuggestedSubs()
            }
            if updatedRemaining % 5 == 0 {
                // Persist often so per-player game minutes survive interruptions.
                save()
            }
        }

        remainingSeconds = updatedRemaining

        if remainingSeconds == 0 {
            timerRunning = false
            timerAnchorDate = nil
            timerAnchorRemainingSeconds = 0
            timerTask?.cancel()
            timerTask = nil
            save()
        }
    }

    func resetTimer() {
        timerRunning = false
        timerAnchorDate = nil
        timerAnchorRemainingSeconds = 0
        timerTask?.cancel()
        timerTask = nil
        data.currentHalf = 1
        remainingSeconds = data.gameLengthMinutes * 60
        resetFairPlay()
        save()
    }

    func setGameLengthMinutes(_ minutes: Int) {
        _ = minutes
        data.gameLengthMinutes = 30
        if !timerRunning && currentHalf == 1 {
            remainingSeconds = 30 * 60
            timerAnchorRemainingSeconds = remainingSeconds
        }
        save()
    }

    func startGameSession() {
        data.gameDate = .now
        save()
        let hasStartedClock = timerRunning || remainingSeconds < data.gameLengthMinutes * 60
        if !hasStartedClock {
            data.currentHalf = 1
            resetTimer()
        }
        if !timerRunning {
            startPauseTimer()
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .active {
            if timerRunning {
                syncTimerWithWallClock()
                startTickerTask()
            }
            return
        }

        if timerRunning {
            syncTimerWithWallClock()
            timerTask?.cancel()
            timerTask = nil
        }

        if phase == .inactive || phase == .background {
            flushAutosave()
        }
    }

    private func cleanupInvalidPlayerReferences() {
        let validPlayerIDs = Set(data.players.map(\.id))
        data.unavailablePlayerIDs = data.unavailablePlayerIDs.filter { validPlayerIDs.contains($0) }
        for index in data.fieldPositions.indices {
            if let assignedID = data.fieldPositions[index].assignedPlayerID, !validPlayerIDs.contains(assignedID) {
                data.fieldPositions[index].assignedPlayerID = nil
            } else if let assignedID = data.fieldPositions[index].assignedPlayerID, unavailablePlayerIDs.contains(assignedID) {
                data.fieldPositions[index].assignedPlayerID = nil
            }
        }
        data.nextPlayerByPositionID = data.nextPlayerByPositionID.filter { _, playerID in
            validPlayerIDs.contains(playerID) && !unavailablePlayerIDs.contains(playerID)
        }
        if let recentlySubbedOutPlayerID, !validPlayerIDs.contains(recentlySubbedOutPlayerID) {
            self.recentlySubbedOutPlayerID = nil
        } else if let recentlySubbedOutPlayerID, unavailablePlayerIDs.contains(recentlySubbedOutPlayerID) {
            self.recentlySubbedOutPlayerID = nil
        }
        playerSecondsPlayed = playerSecondsPlayed.filter { validPlayerIDs.contains($0.key) }
        currentStintSecondsPlayed = currentStintSecondsPlayed.filter { validPlayerIDs.contains($0.key) }
    }

    func formattedTime() -> String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func save() {
        autosaveTask?.cancel()
        autosaveTask = nil
        do {
            data.liveRemainingSeconds = remainingSeconds
            data.liveTimerRunning = timerRunning
            data.liveTimerAnchorDate = timerAnchorDate
            data.liveTimerAnchorRemainingSeconds = timerAnchorRemainingSeconds
            let folder = saveURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: saveURL, options: .atomic)
        } catch {
            print("Failed to save SoccerCoach data: \(error)")
        }
    }

    func queueAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.save()
            }
        }
    }

    func flushAutosave() {
        save()
    }

    private static func makeSaveURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("SoccerCoach", isDirectory: true)
            .appendingPathComponent("soccercoach-data.json")
    }

    private func suggestionKey(for suggestion: SuggestedSubstitution) -> String {
        "\(suggestion.positionID.uuidString)|\(suggestion.playerOutID.uuidString)|\(suggestion.playerInID.uuidString)"
    }

}
