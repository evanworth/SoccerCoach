import Foundation
import AuthenticationServices
import CryptoKit
import PhotosUI
import StoreKit
import SwiftUI
import UIKit

struct SuggestedSubstitution: Identifiable, Hashable {
    let id = UUID()
    let positionID: UUID
    let positionName: String
    let playerOutID: UUID
    let playerInID: UUID
    let reason: String
}

private let defaultSevenVSevenPositions: [String] = [
    "Goalie",
    "Left Defense",
    "Right Defense",
    "Left Midfield",
    "Center Midfield",
    "Right Midfield",
    "Forward",
]

private enum SoccerCoachAccessConfig {
    static let googleClientID = "REPLACE_WITH_GOOGLE_CLIENT_ID"
    static let googleRedirectScheme = "soccercoach"
    static let googleRedirectHost = "oauth"
    static let annualSubscriptionProductID = "com.evanworth.SoccerCoach.pro.yearly"

    static var googleIsConfigured: Bool {
        !googleClientID.contains("REPLACE_WITH")
    }
}

private struct PersistedAccessState: Codable {
    var account: CoachAccount?
}

private struct GoogleTokenResponse: Decodable {
    var access_token: String
    var id_token: String?
}

private struct AppleSignInPayload {
    var email: String
    var displayName: String
}

@MainActor
final class AccessController: NSObject, ObservableObject {
    @Published var signedInAccount: CoachAccount?
    @Published var hasActiveSubscription = false
    @Published var subscriptionProduct: Product?
    @Published var isWorking = false
    @Published var statusMessage = ""
    @Published var lastErrorMessage: String?

    private let saveURL: URL
    private var transactionListener: Task<Void, Never>?
    private var googleSession: ASWebAuthenticationSession?

    override init() {
        self.saveURL = Self.makeSaveURL()
        if
            let savedData = try? Data(contentsOf: saveURL),
            let decoded = try? JSONDecoder().decode(PersistedAccessState.self, from: savedData)
        {
            self.signedInAccount = decoded.account
        } else {
            self.signedInAccount = nil
        }
        super.init()

        transactionListener = listenForTransactions()

        Task {
            await refreshProducts()
            await refreshSubscriptionStatus()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    var requiresAccessSetup: Bool {
        !SoccerCoachAccessConfig.googleIsConfigured || subscriptionProduct == nil
    }

    var annualPriceLabel: String {
        subscriptionProduct?.displayPrice ?? "$10.00/year"
    }

    func signInWithGoogle() async {
        guard SoccerCoachAccessConfig.googleIsConfigured else {
            lastErrorMessage = "Add your Google OAuth client ID and redirect URL first. The button is wired, but it still needs your Google Cloud setup."
            return
        }

        isWorking = true
        lastErrorMessage = nil
        defer { isWorking = false }

        do {
            let verifier = Self.randomString(length: 64)
            let challenge = Self.codeChallenge(for: verifier)
            let state = UUID().uuidString
            let redirectURI = "\(SoccerCoachAccessConfig.googleRedirectScheme)://\(SoccerCoachAccessConfig.googleRedirectHost)"

            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: SoccerCoachAccessConfig.googleClientID),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: "openid email profile"),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "prompt", value: "select_account"),
            ]

            let callbackURL = try await startGoogleSession(
                authURL: components.url!,
                callbackScheme: SoccerCoachAccessConfig.googleRedirectScheme
            )

            guard let urlComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
                throw AccessError.invalidCallback
            }

            let returnedState = urlComponents.queryItems?.first(where: { $0.name == "state" })?.value
            guard returnedState == state else {
                throw AccessError.invalidState
            }

            if let error = urlComponents.queryItems?.first(where: { $0.name == "error" })?.value {
                throw AccessError.providerError(error)
            }

            guard let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
                throw AccessError.missingAuthorizationCode
            }

            let tokenResponse = try await exchangeGoogleCodeForTokens(
                code: code,
                codeVerifier: verifier,
                redirectURI: redirectURI
            )
            let account = try Self.accountFromGoogleToken(tokenResponse.id_token)
            signedInAccount = account
            save()
            statusMessage = "Signed in as \(account.displayName)."
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func signInWithApple() async {
        isWorking = true
        lastErrorMessage = nil
        defer { isWorking = false }

        do {
            let payload = try await startAppleSignIn()
            let account = CoachAccount(
                provider: "Apple",
                email: payload.email,
                displayName: payload.displayName
            )
            signedInAccount = account
            save()
            statusMessage = "Signed in as \(account.displayName)."
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func purchaseAnnualSubscription() async {
        guard let subscriptionProduct else {
            lastErrorMessage = "The yearly subscription product is not available yet. Add it in App Store Connect and try again."
            return
        }

        isWorking = true
        lastErrorMessage = nil
        defer { isWorking = false }

        do {
            let result = try await subscriptionProduct.purchase()
            switch result {
            case .success(let verificationResult):
                let transaction = try Self.checkVerified(verificationResult)
                await refreshSubscriptionStatus()
                await transaction.finish()
                statusMessage = "Your yearly plan is active."
            case .userCancelled:
                break
            case .pending:
                statusMessage = "Purchase is pending approval."
            @unknown default:
                lastErrorMessage = "The purchase did not complete."
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isWorking = true
        lastErrorMessage = nil
        defer { isWorking = false }

        do {
            try await AppStore.sync()
            await refreshSubscriptionStatus()
            if hasActiveSubscription {
                statusMessage = "Your subscription was restored."
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshProducts() async {
        do {
            let products = try await Product.products(for: [SoccerCoachAccessConfig.annualSubscriptionProductID])
            subscriptionProduct = products.first
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshSubscriptionStatus() async {
        var isActive = false

        for await entitlement in Transaction.currentEntitlements {
            guard
                let transaction = try? Self.checkVerified(entitlement),
                transaction.productID == SoccerCoachAccessConfig.annualSubscriptionProductID,
                transaction.revocationDate == nil,
                (transaction.expirationDate ?? .distantFuture) > .now
            else { continue }

            isActive = true
            break
        }

        hasActiveSubscription = isActive
    }

    func signOut() {
        signedInAccount = nil
        hasActiveSubscription = false
        statusMessage = ""
        lastErrorMessage = nil
        save()
    }

    private func startGoogleSession(authURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                self?.googleSession = nil

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: AccessError.invalidCallback)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            googleSession = session

            if !session.start() {
                googleSession = nil
                continuation.resume(throwing: AccessError.unableToStartSession)
            }
        }
    }

    private func exchangeGoogleCodeForTokens(code: String, codeVerifier: String, redirectURI: String) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyItems = [
            URLQueryItem(name: "client_id", value: SoccerCoachAccessConfig.googleClientID),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
        ]

        var components = URLComponents()
        components.queryItems = bodyItems
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw AccessError.tokenExchangeFailed
        }

        return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
    }

    private func startAppleSignIn() async throws -> AppleSignInPayload {
        try await withCheckedThrowingContinuation { continuation in
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            let delegate = AppleSignInDelegate { result in
                continuation.resume(with: result)
            }

            objc_setAssociatedObject(controller, "appleDelegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            controller.performRequests()
        }
    }

    private func save() {
        let payload = PersistedAccessState(account: signedInAccount)

        do {
            let folder = saveURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoded = try JSONEncoder().encode(payload)
            try encoded.write(to: saveURL, options: .atomic)
        } catch {
            print("Failed to save SoccerCoach access data: \(error)")
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? AccessController.checkVerified(result) {
                    await transaction.finish()
                }
                await self?.refreshSubscriptionStatus()
            }
        }
    }

    nonisolated private static func makeSaveURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("SoccerCoach", isDirectory: true)
            .appendingPathComponent("soccercoach-access.json")
    }

    nonisolated private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw AccessError.unverifiedTransaction
        }
    }

    nonisolated private static func accountFromGoogleToken(_ idToken: String?) throws -> CoachAccount {
        guard
            let idToken,
            let payload = decodeJWTPayload(idToken),
            let email = payload["email"] as? String
        else {
            throw AccessError.missingIdentity
        }

        let displayName = (payload["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CoachAccount(
            provider: "Google",
            email: email,
            displayName: displayName?.isEmpty == false ? displayName! : email
        )
    }

    nonisolated private static func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = 4 - (base64.count % 4)
        if padding < 4 {
            base64 += String(repeating: "=", count: padding)
        }

        guard
            let data = Data(base64Encoded: base64),
            let object = try? JSONSerialization.jsonObject(with: data),
            let payload = object as? [String: Any]
        else {
            return nil
        }

        return payload
    }

    nonisolated private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    nonisolated private static func randomString(length: Int) -> String {
        let charset = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).compactMap { _ in charset.randomElement() })
    }
}

extension AccessController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let completion: (Result<AppleSignInPayload, Error>) -> Void

    init(completion: @escaping (Result<AppleSignInPayload, Error>) -> Void) {
        self.completion = completion
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            completion(.failure(AccessError.missingIdentity))
            return
        }

        let email = credential.email ?? ""
        let formatter = PersonNameComponentsFormatter()
        let displayName = formatter.string(from: credential.fullName ?? PersonNameComponents())

        if email.isEmpty && displayName.isEmpty {
            completion(.failure(AccessError.appleProfileUnavailable))
            return
        }

        completion(
            .success(
                AppleSignInPayload(
                    email: email.isEmpty ? "Apple Account" : email,
                    displayName: displayName.isEmpty ? (email.isEmpty ? "Apple Coach" : email) : displayName
                )
            )
        )
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion(.failure(error))
    }
}

private enum AccessError: LocalizedError {
    case unableToStartSession
    case invalidCallback
    case invalidState
    case missingAuthorizationCode
    case tokenExchangeFailed
    case providerError(String)
    case missingIdentity
    case unverifiedTransaction
    case appleProfileUnavailable

    var errorDescription: String? {
        switch self {
        case .unableToStartSession:
            return "The sign-in window could not be opened."
        case .invalidCallback:
            return "Google sign-in did not return a valid callback."
        case .invalidState:
            return "Google sign-in could not be verified."
        case .missingAuthorizationCode:
            return "Google sign-in did not return an authorization code."
        case .tokenExchangeFailed:
            return "Google sign-in could not finish the token exchange."
        case .providerError(let message):
            return message
        case .missingIdentity:
            return "The login provider did not return profile information."
        case .unverifiedTransaction:
            return "The App Store transaction could not be verified."
        case .appleProfileUnavailable:
            return "Apple only shares name and email on the first sign-in for each app. To test again, remove the app from Sign in with Apple settings on your device."
        }
    }
}

@MainActor
final class SoccerCoachStore: ObservableObject {
    @Published var data: AppData
    @Published var remainingSeconds: Int
    @Published var timerRunning = false
    @Published var photoPickerDrillID: UUID?
    @Published var selectedFieldPositionID: UUID?
    @Published var playerSecondsPlayed: [UUID: Int] = [:]
    @Published var suggestedSubs: [SuggestedSubstitution] = []
    @Published var newPresetName = ""

    private var timerTask: Task<Void, Never>?
    private let saveURL: URL

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
        self.remainingSeconds = initialData.gameLengthMinutes * 60
    }

    deinit {
        timerTask?.cancel()
    }

    var assignedPlayerIDs: Set<UUID> {
        Set(data.fieldPositions.compactMap(\.assignedPlayerID))
    }

    var benchPlayers: [Player] {
        data.players.filter { !assignedPlayerIDs.contains($0.id) }
    }

    var onFieldPlayers: [Player] {
        data.fieldPositions.compactMap { player(for: $0.assignedPlayerID) }
    }

    func player(for id: UUID?) -> Player? {
        guard let id else { return nil }
        return data.players.first { $0.id == id }
    }

    func position(for id: UUID) -> FieldPosition? {
        data.fieldPositions.first { $0.id == id }
    }

    func addPlayer() {
        data.players.append(Player(name: "", jerseyNumber: "", playablePositions: []))
        save()
    }

    func assignPlayer(_ playerID: UUID?, to positionID: UUID) {
        guard let index = data.fieldPositions.firstIndex(where: { $0.id == positionID }) else { return }
        if let playerID, let existingIndex = data.fieldPositions.firstIndex(where: { $0.assignedPlayerID == playerID && $0.id != positionID }) {
            data.fieldPositions[existingIndex].assignedPlayerID = data.fieldPositions[index].assignedPlayerID
        }
        data.fieldPositions[index].assignedPlayerID = playerID
        refreshSuggestedSubs()
        save()
    }

    func benchPlayer(_ playerID: UUID) {
        guard let index = data.fieldPositions.firstIndex(where: { $0.assignedPlayerID == playerID }) else { return }
        data.fieldPositions[index].assignedPlayerID = nil
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

    func recommendedPlayers(for position: FieldPosition) -> [Player] {
        let target = normalizePositionName(position.name)
        return data.players.sorted { lhs, rhs in
            let lhsMatches = lhs.playablePositions.contains { normalizePositionName($0) == target }
            let rhsMatches = rhs.playablePositions.contains { normalizePositionName($0) == target }
            if lhsMatches == rhsMatches {
                return lhs.name < rhs.name
            }
            return lhsMatches && !rhsMatches
        }
    }

    func formattedPlayTime(for playerID: UUID) -> String {
        let totalSeconds = playerSecondsPlayed[playerID, default: 0]
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func resetFairPlay() {
        playerSecondsPlayed = [:]
        refreshSuggestedSubs()
    }

    func applySuggestedSub(_ suggestion: SuggestedSubstitution) {
        assignPlayer(suggestion.playerInID, to: suggestion.positionID)
        refreshSuggestedSubs()
        save()
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

            let target = normalizePositionName(position.name)
            let candidates = benchPlayers.filter { player in
                !usedBenchPlayers.contains(player.id) &&
                player.playablePositions.contains { normalizePositionName($0) == target }
            }
            .sorted {
                let lhsTime = playerSecondsPlayed[$0.id, default: 0]
                let rhsTime = playerSecondsPlayed[$1.id, default: 0]
                if lhsTime == rhsTime {
                    return $0.name < $1.name
                }
                return lhsTime < rhsTime
            }

            guard let playerIn = candidates.first else { continue }

            let currentPlayerTime = playerSecondsPlayed[currentPlayerID, default: 0]
            let benchPlayerTime = playerSecondsPlayed[playerIn.id, default: 0]
            guard currentPlayerTime - benchPlayerTime >= 120 else { continue }

            suggestions.append(
                SuggestedSubstitution(
                    positionID: position.id,
                    positionName: position.name,
                    playerOutID: currentPlayer.id,
                    playerInID: playerIn.id,
                    reason: "\(playerIn.name) fits \(position.name) and has played less."
                )
            )
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

    func removePlayers(at offsets: IndexSet) {
        let removedIDs = Set(offsets.map { data.players[$0].id })
        data.players.remove(atOffsets: offsets)
        for index in data.fieldPositions.indices {
            if let assignedID = data.fieldPositions[index].assignedPlayerID, removedIDs.contains(assignedID) {
                data.fieldPositions[index].assignedPlayerID = nil
            }
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

    func resetToSevenVSevenShape() {
        var rebuilt: [FieldPosition] = []

        for name in defaultSevenVSevenPositions {
            let existing = data.fieldPositions.first { normalizePositionName($0.name) == normalizePositionName(name) }
            rebuilt.append(
                FieldPosition(
                    id: existing?.id ?? UUID(),
                    name: name,
                    assignedPlayerID: existing?.assignedPlayerID
                )
            )
        }

        data.fieldPositions = rebuilt
        refreshSuggestedSubs()
        save()
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
        data.fieldPositions.remove(atOffsets: offsets)
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
            timerRunning = false
            timerTask?.cancel()
            timerTask = nil
            return
        }

        timerRunning = true
        timerTask = Task {
            while !Task.isCancelled && remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if timerRunning && remainingSeconds > 0 {
                        remainingSeconds -= 1
                        for playerID in assignedPlayerIDs {
                            playerSecondsPlayed[playerID, default: 0] += 1
                        }
                        if remainingSeconds % 10 == 0 {
                            refreshSuggestedSubs()
                        }
                    }
                    if remainingSeconds == 0 {
                        timerRunning = false
                    }
                }
            }
        }
    }

    func resetTimer() {
        timerRunning = false
        timerTask?.cancel()
        timerTask = nil
        remainingSeconds = data.gameLengthMinutes * 60
        resetFairPlay()
    }

    func formattedTime() -> String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func save() {
        do {
            let folder = saveURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: saveURL, options: .atomic)
        } catch {
            print("Failed to save SoccerCoach data: \(error)")
        }
    }

    private static func makeSaveURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("SoccerCoach", isDirectory: true)
            .appendingPathComponent("soccercoach-data.json")
    }
}
