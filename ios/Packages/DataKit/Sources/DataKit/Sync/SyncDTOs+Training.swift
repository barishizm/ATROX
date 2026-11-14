import Foundation

// DTOs of the training tables: routines*, workouts*, sets, personal_records.

public struct RoutineDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var name: String
    public var notes: String?
}

extension Routine: SyncableModel {
    public static var syncTable: SyncTable { .routines }

    public func makeDTO() -> RoutineDTO {
        RoutineDTO(id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, name: name, notes: notes)
    }

    public func apply(_ dto: RoutineDTO) {
        applyCommon(dto)
        name = dto.name
        notes = dto.notes
    }

    public convenience init(syncDTO dto: RoutineDTO) {
        self.init(id: dto.id, userId: dto.userId, name: dto.name, now: dto.createdAt)
        apply(dto)
    }
}

public struct RoutineDayDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var routineId: UUID
    public var position: Int
    public var name: String
}

extension RoutineDay: SyncableModel {
    public static var syncTable: SyncTable { .routineDays }

    public func makeDTO() -> RoutineDayDTO {
        RoutineDayDTO(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt,
            routineId: routineId, position: position, name: name
        )
    }

    public func apply(_ dto: RoutineDayDTO) {
        applyCommon(dto)
        routineId = dto.routineId
        position = dto.position
        name = dto.name
    }

    public convenience init(syncDTO dto: RoutineDayDTO) {
        self.init(id: dto.id, userId: dto.userId, routineId: dto.routineId, position: dto.position, name: dto.name, now: dto.createdAt)
        apply(dto)
    }
}

public struct RoutineExerciseDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var routineDayId: UUID
    public var position: Int
    public var exerciseId: String?
    public var customExerciseId: UUID?
    public var targetSets: Int
    public var targetRepsMin: Int?
    public var targetRepsMax: Int?
    public var targetRir: Int?
    public var supersetGroup: Int?
    public var restSeconds: Int?
    public var notes: String?
}

extension RoutineExercise: SyncableModel {
    public static var syncTable: SyncTable { .routineExercises }

    public func makeDTO() -> RoutineExerciseDTO {
        RoutineExerciseDTO(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt,
            routineDayId: routineDayId, position: position, exerciseId: exerciseId, customExerciseId: customExerciseId,
            targetSets: targetSets, targetRepsMin: targetRepsMin, targetRepsMax: targetRepsMax, targetRir: targetRir,
            supersetGroup: supersetGroup, restSeconds: restSeconds, notes: notes
        )
    }

    public func apply(_ dto: RoutineExerciseDTO) {
        applyCommon(dto)
        routineDayId = dto.routineDayId
        position = dto.position
        exerciseId = dto.exerciseId
        customExerciseId = dto.customExerciseId
        targetSets = dto.targetSets
        targetRepsMin = dto.targetRepsMin
        targetRepsMax = dto.targetRepsMax
        targetRir = dto.targetRir
        supersetGroup = dto.supersetGroup
        restSeconds = dto.restSeconds
        notes = dto.notes
    }

    public convenience init(syncDTO dto: RoutineExerciseDTO) {
        let ref = ExerciseRef(exerciseId: dto.exerciseId, customExerciseId: dto.customExerciseId) ?? .catalog("")
        self.init(id: dto.id, userId: dto.userId, routineDayId: dto.routineDayId, position: dto.position, ref: ref, now: dto.createdAt)
        apply(dto)
    }
}

public struct WorkoutDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var routineId: UUID?
    public var routineDayId: UUID?
    public var name: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var notes: String?
    public var source: String
    public var rating: Int?
    public var healthKitUuid: UUID?
}

extension Workout: SyncableModel {
    public static var syncTable: SyncTable { .workouts }

    public func makeDTO() -> WorkoutDTO {
        WorkoutDTO(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, routineId: routineId,
            routineDayId: routineDayId, name: name, startedAt: startedAt, endedAt: endedAt, notes: notes,
            source: sourceRaw, rating: rating, healthKitUuid: healthKitUUID
        )
    }

    public func apply(_ dto: WorkoutDTO) {
        applyCommon(dto)
        routineId = dto.routineId
        routineDayId = dto.routineDayId
        name = dto.name
        startedAt = dto.startedAt
        endedAt = dto.endedAt
        notes = dto.notes
        sourceRaw = dto.source
        rating = dto.rating
        healthKitUUID = dto.healthKitUuid
    }

    public convenience init(syncDTO dto: WorkoutDTO) {
        self.init(id: dto.id, userId: dto.userId, startedAt: dto.startedAt, now: dto.createdAt)
        apply(dto)
    }
}

public struct WorkoutExerciseDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var workoutId: UUID
    public var position: Int
    public var exerciseId: String?
    public var customExerciseId: UUID?
    public var supersetGroup: Int?
    public var notes: String?
}

extension WorkoutExercise: SyncableModel {
    public static var syncTable: SyncTable { .workoutExercises }

    public func makeDTO() -> WorkoutExerciseDTO {
        WorkoutExerciseDTO(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, workoutId: workoutId,
            position: position, exerciseId: exerciseId, customExerciseId: customExerciseId, supersetGroup: supersetGroup,
            notes: notes
        )
    }

    public func apply(_ dto: WorkoutExerciseDTO) {
        applyCommon(dto)
        workoutId = dto.workoutId
        position = dto.position
        exerciseId = dto.exerciseId
        customExerciseId = dto.customExerciseId
        supersetGroup = dto.supersetGroup
        notes = dto.notes
    }

    public convenience init(syncDTO dto: WorkoutExerciseDTO) {
        let ref = ExerciseRef(exerciseId: dto.exerciseId, customExerciseId: dto.customExerciseId) ?? .catalog("")
        self.init(id: dto.id, userId: dto.userId, workoutId: dto.workoutId, position: dto.position, ref: ref, now: dto.createdAt)
        apply(dto)
    }
}

public struct SetDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var workoutExerciseId: UUID
    public var position: Int
    public var weightKg: Double
    public var reps: Int
    public var rpe: Double?
    public var rir: Int?
    public var setType: String
    public var isCompleted: Bool
}

extension SetEntry: SyncableModel {
    public static var syncTable: SyncTable { .sets }

    public func makeDTO() -> SetDTO {
        SetDTO(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt,
            workoutExerciseId: workoutExerciseId, position: position, weightKg: weightKg, reps: reps, rpe: rpe, rir: rir,
            setType: setTypeRaw, isCompleted: isCompleted
        )
    }

    public func apply(_ dto: SetDTO) {
        applyCommon(dto)
        workoutExerciseId = dto.workoutExerciseId
        position = dto.position
        weightKg = dto.weightKg
        reps = dto.reps
        rpe = dto.rpe
        rir = dto.rir
        setTypeRaw = dto.setType
        isCompleted = dto.isCompleted
    }

    public convenience init(syncDTO dto: SetDTO) {
        self.init(id: dto.id, userId: dto.userId, workoutExerciseId: dto.workoutExerciseId, position: dto.position, now: dto.createdAt)
        apply(dto)
    }
}

public struct PersonalRecordDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var exerciseId: String?
    public var customExerciseId: UUID?
    public var kind: String
    public var value: Double
    public var setId: UUID?
    public var date: String
}

extension PersonalRecord: SyncableModel {
    public static var syncTable: SyncTable { .personalRecords }

    public func makeDTO() -> PersonalRecordDTO {
        PersonalRecordDTO(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, exerciseId: exerciseId,
            customExerciseId: customExerciseId, kind: kindRaw, value: value, setId: setId, date: SyncTime.day(date)
        )
    }

    public func apply(_ dto: PersonalRecordDTO) {
        applyCommon(dto)
        exerciseId = dto.exerciseId
        customExerciseId = dto.customExerciseId
        kindRaw = dto.kind
        value = dto.value
        setId = dto.setId
        if SyncTime.day(date) != dto.date { date = SyncTime.parseDay(dto.date) ?? date }
    }

    public convenience init(syncDTO dto: PersonalRecordDTO) {
        let ref = ExerciseRef(exerciseId: dto.exerciseId, customExerciseId: dto.customExerciseId) ?? .catalog("")
        let kind = RecordKind(rawValue: dto.kind) ?? .weight
        self.init(id: dto.id, userId: dto.userId, ref: ref, kind: kind, value: dto.value, date: dto.createdAt, now: dto.createdAt)
        apply(dto)
    }
}

public struct ScoreSnapshotDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var scope: String
    public var key: String
    public var referenceGroup: String
    public var score: Double
    public var z: Double
    public var confidence: String
    public var modelVersion: String
    public var date: String
}

extension ScoreSnapshot: SyncableModel {
    public static var syncTable: SyncTable { .scoreSnapshots }

    public func makeDTO() -> ScoreSnapshotDTO {
        ScoreSnapshotDTO(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, scope: scopeRaw, key: key,
            referenceGroup: referenceGroupRaw, score: score, z: z, confidence: confidenceRaw, modelVersion: modelVersion,
            date: SyncTime.day(date)
        )
    }

    public func apply(_ dto: ScoreSnapshotDTO) {
        applyCommon(dto)
        scopeRaw = dto.scope
        key = dto.key
        referenceGroupRaw = dto.referenceGroup
        score = dto.score
        z = dto.z
        confidenceRaw = dto.confidence
        modelVersion = dto.modelVersion
        if SyncTime.day(date) != dto.date { date = SyncTime.parseDay(dto.date) ?? date }
    }

    public convenience init(syncDTO dto: ScoreSnapshotDTO) {
        self.init(
            userId: dto.userId, scope: SnapshotScope(rawValue: dto.scope) ?? .exercise, key: dto.key,
            referenceGroup: dto.referenceGroup, score: dto.score, z: dto.z, confidence: dto.confidence,
            modelVersion: dto.modelVersion, date: SyncTime.parseDay(dto.date) ?? dto.createdAt, now: dto.createdAt
        )
        id = dto.id
        apply(dto)
    }
}

public struct InsightDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var kind: String
    public var subject: String
    public var severity: String
    public var priority: Double
    public var action: String
    public var payload: String
    public var isActive: Bool
    public var detectedAt: Date
    public var lastShownAt: Date?
    public var dismissedAt: Date?
}

extension InsightRecord: SyncableModel {
    public static var syncTable: SyncTable { .insights }

    public func makeDTO() -> InsightDTO {
        InsightDTO(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, kind: kindRaw, subject: subject,
            severity: severityRaw, priority: priority, action: actionRaw, payload: payload, isActive: isActive, detectedAt: detectedAt,
            lastShownAt: lastShownAt, dismissedAt: dismissedAt
        )
    }

    public func apply(_ dto: InsightDTO) {
        applyCommon(dto)
        kindRaw = dto.kind
        subject = dto.subject
        severityRaw = dto.severity
        priority = dto.priority
        actionRaw = dto.action
        payload = dto.payload
        isActive = dto.isActive
        detectedAt = dto.detectedAt
        lastShownAt = dto.lastShownAt
        dismissedAt = dto.dismissedAt
    }

    public convenience init(syncDTO dto: InsightDTO) {
        self.init(
            userId: dto.userId, kind: InsightKind(rawValue: dto.kind) ?? .imbalance, subject: dto.subject,
            severity: InsightSeverity(rawValue: dto.severity) ?? .mild, priority: dto.priority,
            action: InsightAction(rawValue: dto.action) ?? .askCoach, payload: InsightPayload(json: dto.payload),
            detectedAt: dto.detectedAt, now: dto.createdAt
        )
        id = dto.id
        apply(dto)
    }
}
