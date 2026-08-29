import Foundation

struct Player: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var jerseyNumber: String
    var playablePositions: [String]

    init(
        id: UUID = UUID(),
        name: String,
        jerseyNumber: String,
        playablePositions: [String] = []
    ) {
        self.id = id
        self.name = name
        self.jerseyNumber = jerseyNumber
        self.playablePositions = playablePositions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        jerseyNumber = try container.decodeIfPresent(String.self, forKey: .jerseyNumber) ?? ""
        if let playablePositions = try container.decodeIfPresent([String].self, forKey: .playablePositions) {
            self.playablePositions = playablePositions
        } else {
            self.playablePositions = []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case jerseyNumber
        case playablePositions
    }
}

struct FieldPosition: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var assignedPlayerID: UUID?
}

struct SubWindow: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var minuteMark: Int
    var focus: String
    var completed: Bool
}

struct PracticeDrill: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var minutes: Int
    var notes: String
    var resourceLink: String
    var imageData: Data?

    init(
        id: UUID = UUID(),
        title: String,
        minutes: Int,
        notes: String,
        resourceLink: String = "",
        imageData: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.minutes = minutes
        self.notes = notes
        self.resourceLink = resourceLink
        self.imageData = imageData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes) ?? 10
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
            ?? container.decodeIfPresent(String.self, forKey: .coachingPoints)
            ?? ""
        resourceLink = try container.decodeIfPresent(String.self, forKey: .resourceLink) ?? ""
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(minutes, forKey: .minutes)
        try container.encode(notes, forKey: .notes)
        try container.encode(resourceLink, forKey: .resourceLink)
        try container.encodeIfPresent(imageData, forKey: .imageData)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case minutes
        case notes
        case coachingPoints
        case resourceLink
        case imageData
    }
}

struct PracticePlan: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var ageGroup: String
    var totalMinutes: Int
    var theme: String
    var drills: [PracticeDrill]
    var notes: String
}

struct LineupPreset: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var assignments: [String: UUID?]
}

enum GameFormation: String, Codable, CaseIterable, Hashable {
    case threeThree = "3-3"
    case twoThreeOne = "2-3-1"
    case twoTwoTwo = "2-2-2"
    case threeOneTwo = "3-1-2"

    var title: String { rawValue }

    var positionNames: [String] {
        switch self {
        case .threeThree:
            return [
                "Goalie",
                "Left Defense",
                "Center Defense",
                "Right Defense",
                "Left Forward",
                "Center Forward",
                "Right Forward",
            ]
        case .twoThreeOne:
            return [
                "Goalie",
                "Left Defense",
                "Right Defense",
                "Left Midfield",
                "Center Midfield",
                "Right Midfield",
                "Forward",
            ]
        case .twoTwoTwo:
            return [
                "Goalie",
                "Left Defense",
                "Right Defense",
                "Left Midfield",
                "Right Midfield",
                "Left Forward",
                "Right Forward",
            ]
        case .threeOneTwo:
            return [
                "Goalie",
                "Left Defense",
                "Center Defense",
                "Right Defense",
                "Center Midfield",
                "Left Forward",
                "Right Forward",
            ]
        }
    }
}

enum AppTheme: String, Codable, CaseIterable, Hashable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

struct SavedGameStats: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var savedAt: Date = .now
    var title: String
    var opponentName: String
    var gameDate: Date
    var gameLengthMinutes: Int
    var playerSeconds: [String: Int]
    var playerNames: [String: String]
    var playerJerseyNumbers: [String: String]

    init(
        id: UUID = UUID(),
        savedAt: Date = .now,
        title: String,
        opponentName: String = "",
        gameDate: Date = .now,
        gameLengthMinutes: Int = 30,
        playerSeconds: [String: Int],
        playerNames: [String: String] = [:],
        playerJerseyNumbers: [String: String] = [:]
    ) {
        self.id = id
        self.savedAt = savedAt
        self.title = title
        self.opponentName = opponentName
        self.gameDate = gameDate
        self.gameLengthMinutes = gameLengthMinutes
        self.playerSeconds = playerSeconds
        self.playerNames = playerNames
        self.playerJerseyNumbers = playerJerseyNumbers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? .now
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        opponentName = try container.decodeIfPresent(String.self, forKey: .opponentName) ?? ""
        gameDate = try container.decodeIfPresent(Date.self, forKey: .gameDate) ?? .now
        gameLengthMinutes = try container.decodeIfPresent(Int.self, forKey: .gameLengthMinutes) ?? 30
        playerSeconds = try container.decodeIfPresent([String: Int].self, forKey: .playerSeconds) ?? [:]
        playerNames = try container.decodeIfPresent([String: String].self, forKey: .playerNames) ?? [:]
        playerJerseyNumbers = try container.decodeIfPresent([String: String].self, forKey: .playerJerseyNumbers) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case savedAt
        case title
        case opponentName
        case gameDate
        case gameLengthMinutes
        case playerSeconds
        case playerNames
        case playerJerseyNumbers
    }
}

struct AppData: Codable, Equatable {
    var players: [Player]
    var fieldPositions: [FieldPosition]
    var lineupPresets: [LineupPreset]
    var subWindows: [SubWindow]
    var practicePlans: [PracticePlan]
    var unavailablePlayerIDs: [UUID]
    var gameLengthMinutes: Int
    var substitutionInterval: Int
    var liveRemainingSeconds: Int?
    var liveTimerRunning: Bool
    var liveTimerAnchorDate: Date?
    var liveTimerAnchorRemainingSeconds: Int
    var currentHalf: Int
    var gameOpponentName: String
    var gameDate: Date
    var firstHalfNotes: String
    var secondHalfNotes: String
    var nextPlayerByPositionID: [String: UUID]
    var savedGames: [SavedGameStats]
    var appTheme: AppTheme
    var gameFormation: GameFormation
    var hasSeenCoachOnboarding: Bool

    init(
        players: [Player],
        fieldPositions: [FieldPosition],
        lineupPresets: [LineupPreset],
        subWindows: [SubWindow],
        practicePlans: [PracticePlan],
        unavailablePlayerIDs: [UUID] = [],
        gameLengthMinutes: Int,
        substitutionInterval: Int,
        liveRemainingSeconds: Int? = nil,
        liveTimerRunning: Bool = false,
        liveTimerAnchorDate: Date? = nil,
        liveTimerAnchorRemainingSeconds: Int = 0,
        currentHalf: Int = 1,
        gameOpponentName: String = "",
        gameDate: Date = .now,
        firstHalfNotes: String,
        secondHalfNotes: String,
        nextPlayerByPositionID: [String: UUID] = [:],
        savedGames: [SavedGameStats] = [],
        appTheme: AppTheme = .system,
        gameFormation: GameFormation = .twoThreeOne,
        hasSeenCoachOnboarding: Bool = false
    ) {
        self.players = players
        self.fieldPositions = fieldPositions
        self.lineupPresets = lineupPresets
        self.subWindows = subWindows
        self.practicePlans = practicePlans
        self.unavailablePlayerIDs = unavailablePlayerIDs
        self.gameLengthMinutes = gameLengthMinutes
        self.substitutionInterval = substitutionInterval
        self.liveRemainingSeconds = liveRemainingSeconds
        self.liveTimerRunning = liveTimerRunning
        self.liveTimerAnchorDate = liveTimerAnchorDate
        self.liveTimerAnchorRemainingSeconds = liveTimerAnchorRemainingSeconds
        self.currentHalf = currentHalf
        self.gameOpponentName = gameOpponentName
        self.gameDate = gameDate
        self.firstHalfNotes = firstHalfNotes
        self.secondHalfNotes = secondHalfNotes
        self.nextPlayerByPositionID = nextPlayerByPositionID
        self.savedGames = savedGames
        self.appTheme = appTheme
        self.gameFormation = gameFormation
        self.hasSeenCoachOnboarding = hasSeenCoachOnboarding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        players = try container.decodeIfPresent([Player].self, forKey: .players) ?? []
        fieldPositions = try container.decodeIfPresent([FieldPosition].self, forKey: .fieldPositions) ?? []
        lineupPresets = try container.decodeIfPresent([LineupPreset].self, forKey: .lineupPresets) ?? []
        subWindows = try container.decodeIfPresent([SubWindow].self, forKey: .subWindows) ?? []
        practicePlans = try container.decodeIfPresent([PracticePlan].self, forKey: .practicePlans) ?? []
        unavailablePlayerIDs = try container.decodeIfPresent([UUID].self, forKey: .unavailablePlayerIDs) ?? []
        gameLengthMinutes = try container.decodeIfPresent(Int.self, forKey: .gameLengthMinutes) ?? 30
        substitutionInterval = try container.decodeIfPresent(Int.self, forKey: .substitutionInterval) ?? 5
        liveRemainingSeconds = try container.decodeIfPresent(Int.self, forKey: .liveRemainingSeconds)
        liveTimerRunning = try container.decodeIfPresent(Bool.self, forKey: .liveTimerRunning) ?? false
        liveTimerAnchorDate = try container.decodeIfPresent(Date.self, forKey: .liveTimerAnchorDate)
        liveTimerAnchorRemainingSeconds = try container.decodeIfPresent(Int.self, forKey: .liveTimerAnchorRemainingSeconds) ?? 0
        currentHalf = try container.decodeIfPresent(Int.self, forKey: .currentHalf) ?? 1
        gameOpponentName = try container.decodeIfPresent(String.self, forKey: .gameOpponentName) ?? ""
        gameDate = try container.decodeIfPresent(Date.self, forKey: .gameDate) ?? .now
        firstHalfNotes = try container.decodeIfPresent(String.self, forKey: .firstHalfNotes) ?? ""
        secondHalfNotes = try container.decodeIfPresent(String.self, forKey: .secondHalfNotes) ?? ""
        nextPlayerByPositionID = try container.decodeIfPresent([String: UUID].self, forKey: .nextPlayerByPositionID) ?? [:]
        savedGames = try container.decodeIfPresent([SavedGameStats].self, forKey: .savedGames) ?? []
        appTheme = try container.decodeIfPresent(AppTheme.self, forKey: .appTheme) ?? .system
        gameFormation = try container.decodeIfPresent(GameFormation.self, forKey: .gameFormation) ?? .twoThreeOne
        hasSeenCoachOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasSeenCoachOnboarding) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case players
        case fieldPositions
        case lineupPresets
        case subWindows
        case practicePlans
        case unavailablePlayerIDs
        case gameLengthMinutes
        case substitutionInterval
        case liveRemainingSeconds
        case liveTimerRunning
        case liveTimerAnchorDate
        case liveTimerAnchorRemainingSeconds
        case currentHalf
        case gameOpponentName
        case gameDate
        case firstHalfNotes
        case secondHalfNotes
        case nextPlayerByPositionID
        case savedGames
        case appTheme
        case gameFormation
        case hasSeenCoachOnboarding
    }

    static let `default` = AppData(
        players: [
            Player(name: "Mia", jerseyNumber: "7", playablePositions: ["Forward", "Left Midfield", "Right Midfield"]),
            Player(name: "Ava", jerseyNumber: "4", playablePositions: ["Center Midfield", "Left Midfield", "Right Midfield"]),
            Player(name: "Ella", jerseyNumber: "2", playablePositions: ["Left Defense", "Right Defense", "Center Midfield"]),
            Player(name: "Sofia", jerseyNumber: "1", playablePositions: ["Goalie"])
        ],
        fieldPositions: GameFormation.twoThreeOne.positionNames.map { FieldPosition(name: $0) },
        lineupPresets: [],
        subWindows: [
            SubWindow(minuteMark: 5, focus: "Swap two midfielders", completed: false),
            SubWindow(minuteMark: 10, focus: "Rest striker and right back", completed: false),
            SubWindow(minuteMark: 15, focus: "Fresh legs in midfield", completed: false),
            SubWindow(minuteMark: 20, focus: "Final push lineup", completed: false)
        ],
        practicePlans: [
            PracticePlan(
                title: "Passing and Spacing",
                ageGroup: "Grade 3/4 Girls",
                totalMinutes: 60,
                theme: "First touch and moving after the pass",
                drills: [
                    PracticeDrill(title: "Ball Mastery Warmup", minutes: 10, notes: "Soft touches, keep head up, lots of little taps."),
                    PracticeDrill(title: "Triangle Passing", minutes: 15, notes: "Pass and move right away. Open body to receive."),
                    PracticeDrill(title: "3v2 to Goal", minutes: 20, notes: "Spread wide and attack the open channel before defenders recover."),
                    PracticeDrill(title: "Scrimmage", minutes: 15, notes: "Freeze play to coach spacing between defense, midfield, and forward.")
                ],
                notes: "Keep lines short and rotate partners often."
            )
        ],
        unavailablePlayerIDs: [],
        gameLengthMinutes: 30,
        substitutionInterval: 5,
        liveRemainingSeconds: nil,
        liveTimerRunning: false,
        liveTimerAnchorDate: nil,
        liveTimerAnchorRemainingSeconds: 0,
        currentHalf: 1,
        gameOpponentName: "",
        gameDate: .now,
        firstHalfNotes: "",
        secondHalfNotes: "",
        nextPlayerByPositionID: [:],
        savedGames: [],
        appTheme: .system,
        gameFormation: .twoThreeOne,
        hasSeenCoachOnboarding: false
    )
}
