import Foundation

/// Facts about a finished workout that the comment is written from (P083). Only summary numbers: no notes, no ids.
public struct WorkoutDigest: Sendable, Equatable, Encodable {
    public struct Exercise: Sendable, Equatable, Encodable {
        public let name: String
        public let sets: Int
        public let topSet: String?

        public init(name: String, sets: Int, topSet: String? = nil) {
            self.name = name
            self.sets = sets
            self.topSet = topSet
        }
    }

    public struct Previous: Sendable, Equatable, Encodable {
        public let sets: Int
        public let volumeKg: Double
        public let durationMin: Int

        public init(sets: Int, volumeKg: Double, durationMin: Int) {
            self.sets = sets
            self.volumeKg = volumeKg
            self.durationMin = durationMin
        }
    }

    public let durationMin: Int
    public let sets: Int
    public let volumeKg: Double
    public let exercises: [Exercise]
    public let records: [DigestRecord]
    public let previous: Previous?

    public init(durationMin: Int, sets: Int, volumeKg: Double, exercises: [Exercise], records: [DigestRecord], previous: Previous? = nil) {
        self.durationMin = max(0, durationMin)
        self.sets = max(0, sets)
        self.volumeKg = max(0, volumeKg)
        self.exercises = Array(exercises.prefix(30))
        self.records = Array(records.prefix(20))
        self.previous = previous
    }
}

public struct DigestRecord: Sendable, Equatable, Encodable {
    public let exercise: String
    public let kind: String

    public init(exercise: String, kind: String) {
        self.exercise = exercise
        self.kind = kind
    }
}

/// The weekly summary (P070) reduced to what the comment needs.
public struct WeeklyDigest: Sendable, Equatable, Encodable {
    public let workouts: Int
    public let goal: Int
    public let totalSets: Int
    public let volumeChangePct: Double?
    public let records: [DigestRecord]
    public let overallScore: Double?
    public let overallChange: Double?
    public let topGroup: String?
    public let neglectedGroups: [String]

    public init(
        workouts: Int, goal: Int, totalSets: Int, volumeChangePct: Double?, records: [DigestRecord], overallScore: Double?,
        overallChange: Double?, topGroup: String?, neglectedGroups: [String]
    ) {
        self.workouts = max(0, workouts)
        self.goal = max(0, min(goal, 14))
        self.totalSets = max(0, totalSets)
        self.volumeChangePct = volumeChangePct
        self.records = Array(records.prefix(20))
        self.overallScore = overallScore.map { min(max($0, 0), 100) }
        self.overallChange = overallChange.map { min(max($0, -100), 100) }
        self.topGroup = topGroup
        self.neglectedGroups = Array(neglectedGroups.prefix(10))
    }
}

public struct CoachDigestRequest: Sendable, Equatable {
    public enum Payload: Sendable, Equatable {
        case workout(WorkoutDigest)
        case weekly(WeeklyDigest)
    }

    public let payload: Payload
    /// "tr" or "en".
    public let locale: String
    public let timeZone: String

    public init(_ payload: Payload, locale: String, timeZone: String = TimeZone.current.identifier) {
        self.payload = payload
        self.locale = locale
        self.timeZone = timeZone
    }

    private struct Envelope: Encodable {
        let kind: String
        let locale: String
        let timeZone: String
        let workout: WorkoutDigest.Body?
        let previous: WorkoutDigest.Previous?
        let week: WeeklyDigest?
    }

    var jsonBody: Data {
        let envelope: Envelope
        switch payload {
        case .workout(let digest):
            envelope = Envelope(kind: "workout", locale: locale, timeZone: timeZone, workout: digest.body, previous: digest.previous, week: nil)
        case .weekly(let digest):
            envelope = Envelope(kind: "weekly", locale: locale, timeZone: timeZone, workout: nil, previous: nil, week: digest)
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(envelope)) ?? Data()
    }
}

extension WorkoutDigest {
    /// The workout without `previous`, which the server reads next to it.
    struct Body: Encodable {
        let durationMin: Int
        let sets: Int
        let volumeKg: Double
        let exercises: [Exercise]
        let records: [DigestRecord]
    }

    var body: Body { Body(durationMin: durationMin, sets: sets, volumeKg: volumeKg, exercises: exercises, records: records) }
}

/// One proactive comment from the server (Pro). Any error means "show nothing".
public protocol CoachDigestService: Sendable {
    func comment(for request: CoachDigestRequest) async throws -> String
}

/// `coach-digest` Edge Function. A 401 refreshes the token and tries once more.
public struct SupabaseCoachDigestService: CoachDigestService {
    public typealias Token = @Sendable () async -> String?
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let baseURL: URL
    private let anonKey: String
    private let accessToken: Token
    private let refreshedToken: Token
    private let send: Send

    public init(baseURL: URL, anonKey: String, accessToken: @escaping Token, refreshedToken: @escaping Token, send: @escaping Send = Self.urlSession) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.refreshedToken = refreshedToken
        self.send = send
    }

    public static let urlSession: Send = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CoachError.invalidResponse }
        return (data, http)
    }

    public func comment(for request: CoachDigestRequest) async throws -> String {
        var token = await accessToken()
        for attempt in 0..<2 {
            guard let current = token else { throw CoachError.unauthorized }
            do {
                return try await attemptOnce(request, token: current)
            } catch CoachError.unauthorized where attempt == 0 {
                token = await refreshedToken()
            } catch {
                throw CoachError.from(error)
            }
        }
        throw CoachError.unauthorized
    }

    private func attemptOnce(_ digest: CoachDigestRequest, token: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/coach-digest"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = digest.jsonBody
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else { throw CoachError.from(status: response.statusCode, body: data) }
        guard let text = (try? JSONDecoder().decode(CoachJSON.self, from: data))?["text"]?.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw CoachError.invalidResponse }
        return text
    }
}
