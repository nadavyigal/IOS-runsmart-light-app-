import Foundation

enum FlexWeekServiceSupport {
    private static let cacheKeyPrefix = "runsmart.flexWeek.response."

    static func buildRequestDTO(from request: FlexWeekRequest) -> RunSmartDTO.FlexWeekRequestDTO {
        let reasonPayload = reasonPayload(for: request.reason)
        return RunSmartDTO.FlexWeekRequestDTO(
            reason: reasonPayload.reason,
            currentWeek: request.currentWeek.map(workoutDTO(from:)),
            readinessContext: request.readinessContext.map(readinessDTO(from:)),
            blockedDays: reasonPayload.blockedDays,
            missedWorkoutID: reasonPayload.missedWorkoutID,
            sickDaysOut: reasonPayload.sickDaysOut
        )
    }

    static func deterministicOutcome(
        for request: FlexWeekRequest,
        source: FlexWeekOutcomeSource = .deterministicFallback
    ) -> FlexWeekOutcome {
        let (week, changes) = DeterministicFlexWeekBuilder.restructure(
            week: request.currentWeek,
            reason: request.reason
        )
        return FlexWeekOutcome(
            restructuredWeek: week,
            changes: changes,
            safetyWarnings: source == .deterministicFallback
                ? ["Coach is taking a careful path — here's a safe adjustment based on standard recovery rules."]
                : [],
            source: source
        )
    }

    static func outcome(
        from response: RunSmartDTO.FlexWeekResponseDTO,
        originalWeek: [PlannedWorkout]
    ) -> FlexWeekOutcome? {
        let originalsByID = Dictionary(uniqueKeysWithValues: originalWeek.map { ($0.id.uuidString.lowercased(), $0) })
        var mappedWeek: [PlannedWorkout] = []

        for dto in response.restructuredWeek {
            guard let workout = workout(from: dto, originalsByID: originalsByID) else { return nil }
            mappedWeek.append(workout)
        }

        guard mappedWeek.count == originalWeek.count else { return nil }

        let changes = response.changes.compactMap { changeDTO(from: $0) }
        guard !changes.isEmpty else { return nil }

        let source: FlexWeekOutcomeSource = response.source == "live_ai" ? .ai : .deterministicFallback
        return FlexWeekOutcome(
            restructuredWeek: mappedWeek,
            changes: changes,
            safetyWarnings: response.safetyWarnings ?? [],
            source: source
        )
    }

    static func cacheResponse(_ response: RunSmartDTO.FlexWeekResponseDTO, for request: FlexWeekRequest, userID: UUID?) {
        guard let userID else { return }
        let key = cacheKey(for: request, userID: userID)
        if let data = try? JSONEncoder().encode(response) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func cachedOutcome(for request: FlexWeekRequest, userID: UUID?) -> FlexWeekOutcome? {
        guard let userID else { return nil }
        let key = cacheKey(for: request, userID: userID)
        guard let data = UserDefaults.standard.data(forKey: key),
              let response = try? JSONDecoder().decode(RunSmartDTO.FlexWeekResponseDTO.self, from: data) else {
            return nil
        }
        return outcome(from: response, originalWeek: request.currentWeek)?.settingSource(.offlineQueued)
    }

    private static func cacheKey(for request: FlexWeekRequest, userID: UUID) -> String {
        let weekKey = request.currentWeek
            .map { ISO8601DateFormatter.shortDate.string(from: $0.scheduledDate) }
            .sorted()
            .joined(separator: "|")
        return cacheKeyPrefix + userID.uuidString + "." + request.reason.kind.rawValue + "." + weekKey
    }

    private static func reasonPayload(for reason: FlexWeekReason) -> (
        reason: String,
        blockedDays: [String]?,
        missedWorkoutID: String?,
        sickDaysOut: Int?
    ) {
        switch reason {
        case .tired:
            return ("tired", nil, nil, nil)
        case .traveling(let blockedDays):
            return (
                "traveling",
                blockedDays.map { ISO8601DateFormatter.shortDate.string(from: $0) },
                nil,
                nil
            )
        case .missedWorkout(let workoutID):
            return ("missed_workout", nil, workoutID.uuidString, nil)
        case .sick(let daysOut):
            return ("sick", nil, nil, daysOut)
        }
    }

    private static func workoutDTO(from workout: PlannedWorkout) -> RunSmartDTO.FlexWeekWorkoutDTO {
        RunSmartDTO.FlexWeekWorkoutDTO(
            workoutID: workout.id.uuidString,
            scheduledDate: ISO8601DateFormatter.shortDate.string(from: workout.scheduledDate),
            weekday: workout.weekday,
            dateLabel: workout.date,
            kind: workout.kind.rawValue,
            title: workout.title,
            distanceLabel: workout.distance,
            detailLabel: workout.detail,
            intensity: workout.intensity,
            trainingPhase: workout.trainingPhase,
            isToday: workout.isToday,
            isComplete: workout.isComplete,
            originalWorkoutID: nil
        )
    }

    private static func readinessDTO(from context: ReadinessContext) -> RunSmartDTO.FlexWeekReadinessContextDTO {
        RunSmartDTO.FlexWeekReadinessContextDTO(
            readiness: context.readiness,
            readinessLabel: context.readinessLabel,
            bodyBattery: context.bodyBattery,
            hrv: context.hrv,
            sleep: context.sleep,
            recommendation: context.recommendation
        )
    }

    private static func workout(
        from dto: RunSmartDTO.FlexWeekWorkoutDTO,
        originalsByID: [String: PlannedWorkout]
    ) -> PlannedWorkout? {
        let lookupID = dto.workoutID.lowercased()
        guard var workout = originalsByID[lookupID] else { return nil }

        guard let scheduledDate = ISO8601DateFormatter.shortDate.date(from: dto.scheduledDate) else {
            return nil
        }

        workout.scheduledDate = scheduledDate
        workout.weekday = dto.weekday
        workout.date = dto.dateLabel
        workout.kind = WorkoutKind(rawValue: dto.kind) ?? workout.kind
        workout.title = dto.title
        workout.distance = dto.distanceLabel
        workout.detail = dto.detailLabel
        workout.intensity = dto.intensity
        workout.trainingPhase = dto.trainingPhase
        workout.isToday = dto.isToday
        workout.isComplete = dto.isComplete
        return workout
    }

    private static func changeDTO(from dto: RunSmartDTO.FlexWeekChangeDTO) -> FlexWeekChange? {
        guard let workoutID = UUID(uuidString: dto.workoutID),
              let changeType = FlexWeekChangeType(rawValue: dto.changeType) else {
            return nil
        }
        let rationale = dto.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rationale.isEmpty else { return nil }
        return FlexWeekChange(
            workoutID: workoutID,
            changeType: changeType,
            rationale: rationale,
            originalWorkoutID: dto.originalWorkoutID.flatMap(UUID.init(uuidString:))
        )
    }
}

private extension FlexWeekOutcome {
    func settingSource(_ source: FlexWeekOutcomeSource) -> FlexWeekOutcome {
        FlexWeekOutcome(
            restructuredWeek: restructuredWeek,
            changes: changes,
            safetyWarnings: safetyWarnings,
            source: source
        )
    }
}
