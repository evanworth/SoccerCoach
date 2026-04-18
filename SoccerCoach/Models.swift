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

struct CoachAccount: Codable, Equatable {
    var provider: String
    var email: String
    var displayName: String
}

struct AppData: Codable, Equatable {
    var players: [Player]
    var fieldPositions: [FieldPosition]
    var lineupPresets: [LineupPreset]
    var subWindows: [SubWindow]
    var practicePlans: [PracticePlan]
    var gameLengthMinutes: Int
    var substitutionInterval: Int
    var firstHalfNotes: String
    var secondHalfNotes: String

    static let `default` = AppData(
        players: [
            Player(name: "Mia", jerseyNumber: "7", playablePositions: ["Forward", "Left Midfield", "Right Midfield"]),
            Player(name: "Ava", jerseyNumber: "4", playablePositions: ["Center Midfield", "Left Midfield", "Right Midfield"]),
            Player(name: "Ella", jerseyNumber: "2", playablePositions: ["Left Defense", "Right Defense", "Center Midfield"]),
            Player(name: "Sofia", jerseyNumber: "1", playablePositions: ["Goalie"])
        ],
        fieldPositions: [
            FieldPosition(name: "Goalie"),
            FieldPosition(name: "Left Defense"),
            FieldPosition(name: "Right Defense"),
            FieldPosition(name: "Left Midfield"),
            FieldPosition(name: "Center Midfield"),
            FieldPosition(name: "Right Midfield"),
            FieldPosition(name: "Forward")
        ],
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
        gameLengthMinutes: 60,
        substitutionInterval: 5,
        firstHalfNotes: "",
        secondHalfNotes: ""
    )
}
