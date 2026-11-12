import Foundation
import SwiftData

/// A server row in Swift form. Property names are the camelCase of the column names, so a snake_case coder maps them
/// one to one (docs/02-MIMARI.md §3.1). Timestamps are `Date`; Postgres `date` columns are `String` (`yyyy-MM-dd`).
public protocol SyncDTO: Codable, Sendable, Equatable {
    var id: UUID { get }
    var userId: UUID { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var deletedAt: Date? { get }
}

/// A SwiftData model that the sync engine pushes and pulls (P044).
public protocol SyncableModel: PersistentModel, SyncableRecord {
    associatedtype DTO: SyncDTO
    var createdAt: Date { get set }
    static var syncTable: SyncTable { get }
    /// The row as it should be stored on the server.
    func makeDTO() -> DTO
    /// Overwrites every field (including the timestamps) with the server's version.
    func apply(_ dto: DTO)
    /// A new local row from a server row.
    init(syncDTO dto: DTO)
    static func syncDescriptor(_ filter: SyncFilter) -> FetchDescriptor<Self>
}

/// The row sets the sync engine fetches (see `SyncDescriptors.swift`).
public enum SyncFilter: Sendable {
    case state(SyncState, userId: UUID)
    case id(UUID)
    case user(UUID)
    case all
}

extension SyncTable {
    /// The local model of each table.
    var modelType: any SyncableModel.Type {
        switch self {
        case .profiles: UserProfile.self
        case .userSettings: UserSettings.self
        case .bodyMeasurements: BodyMeasurement.self
        case .customExercises: CustomExercise.self
        case .routines: Routine.self
        case .routineDays: RoutineDay.self
        case .routineExercises: RoutineExercise.self
        case .workouts: Workout.self
        case .workoutExercises: WorkoutExercise.self
        case .sets: SetEntry.self
        case .personalRecords: PersonalRecord.self
        }
    }
}

extension SyncableModel {
    /// Shared bookkeeping of `apply`.
    func applyCommon(_ dto: some SyncDTO) {
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        deletedAt = dto.deletedAt
        syncState = .synced
    }
}

/// JSON (de)coding between DTOs and PostgREST rows.
enum SyncCoding {
    static func encode(_ dto: some SyncDTO) throws -> JSONObject {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SyncTime.timestamp(date))
        }
        let data = try encoder.encode(dto)
        var row = try JSONDecoder().decode(JSONObject.self, from: data)
        // Optional fields that are nil are left out by the encoder; PostgREST needs them as null to clear a column.
        for key in Mirror(reflecting: dto).children.compactMap(\.label).map(snakeCase) where row[key] == nil {
            row[key] = .null
        }
        return row
    }

    static func decode<DTO: SyncDTO>(_ type: DTO.Type, from row: JSONObject) throws -> DTO {
        let data = try JSONEncoder().encode(row)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = SyncTime.parseTimestamp(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "bad timestamp \(text)")
            }
            return date
        }
        return try decoder.decode(type, from: data)
    }

    static func snakeCase(_ name: String) -> String {
        var result = ""
        var previousWasUpper = false
        for (index, char) in name.enumerated() {
            if char.isUppercase {
                if index > 0 && !previousWasUpper { result.append("_") }
                result.append(Character(char.lowercased()))
                previousWasUpper = true
            } else {
                result.append(char)
                previousWasUpper = false
            }
        }
        return result
    }
}
