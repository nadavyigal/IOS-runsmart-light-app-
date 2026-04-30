import SwiftUI

struct MomentumSnapshotCard: View {
    var runs: [RecordedRun]
    var plannedWorkouts: [WorkoutSummary]

    private var weeklyDistanceKm: Double {
        runs.filter { Calendar.current.isDate($0.startedAt, equalTo: Date(), toGranularity: .weekOfYear) }
            .reduce(0.0) { $0 + $1.distanceMeters / 1_000 }
    }

    private var weeklyRuns: Int {
        runs.filter { Calendar.current.isDate($0.startedAt, equalTo: Date(), toGranularity: .weekOfYear) }.count
    }

    private var consistency: Int {
        let planned = max(1, plannedWorkouts.filter { $0.kind != .recovery && $0.kind != .strength }.count)
        return min(100, Int((Double(weeklyRuns) / Double(planned) * 100).rounded()))
    }

    private var totalDistanceKm: Double {
        runs.reduce(0.0) { $0 + $1.distanceMeters / 1_000 }
    }

    private var momentumStreak: Int {
        let runDays = Set(runs.map { Calendar.current.startOfDay(for: $0.startedAt) })
        var cursor = Calendar.current.startOfDay(for: Date())
        var count = 0
        while runDays.contains(cursor) {
            count += 1
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return count
    }

    var body: some View {
        GlassCard(cornerRadius: 18, padding: 14, glow: Color.lime) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Momentum Snapshot")
                        .font(.headline)
                    Text("How your training trend looks right now.")
                        .font(.caption)
                        .foregroundStyle(Color.mutedText)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MomentumMetricTile(title: "Weekly Distance", value: String(format: "%.1f", weeklyDistanceKm), unit: "km", symbol: "point.topleft.down.curvedto.point.bottomright.up")
                    MomentumMetricTile(title: "Weekly Runs", value: "\(weeklyRuns)", unit: weeklyRuns == 1 ? "run" : "runs", symbol: "calendar.badge.checkmark")
                    MomentumMetricTile(title: "Consistency", value: "\(consistency)%", unit: "planned workouts", symbol: "waveform.path.ecg")
                    MomentumMetricTile(title: "Total Distance", value: String(format: "%.1f", totalDistanceKm), unit: "km all-time", symbol: "chart.line.uptrend.xyaxis")
                    MomentumMetricTile(title: "Momentum Streak", value: "\(momentumStreak)", unit: momentumStreak == 1 ? "day" : "days", symbol: "flame.fill")
                    MomentumMetricTile(title: "Total Runs", value: "\(runs.count)", unit: "completed", symbol: "checkmark.seal.fill")
                }
            }
        }
    }
}

private struct MomentumMetricTile: View {
    var title: String
    var value: String
    var unit: String
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.mutedText)
                    .lineLimit(2)
                Spacer()
                Image(systemName: symbol)
                    .font(.caption.bold())
                    .foregroundStyle(Color.lime)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.05))
                    .clipShape(Circle())
            }
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.78)
            Text(unit)
                .font(.caption)
                .foregroundStyle(Color.mutedText)
                .lineLimit(1)
        }
        .padding(12)
        .frame(minHeight: 128, alignment: .topLeading)
        .background(.white.opacity(0.045))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct RunTrendChartCard: View {
    var runs: [RecordedRun]

    private var lastEightWeeks: [(label: String, km: Double)] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<8).reversed().map { offset in
            let date = calendar.date(byAdding: .weekOfYear, value: -offset, to: now) ?? now
            let km = runs
                .filter { calendar.isDate($0.startedAt, equalTo: date, toGranularity: .weekOfYear) }
                .reduce(0.0) { $0 + $1.distanceMeters / 1_000 }
            return (DateFormatter.shortMonthDay.string(from: date), km)
        }
    }

    private var maxKm: Double {
        max(1, lastEightWeeks.map(\.km).max() ?? 1)
    }

    var body: some View {
        GlassCard(cornerRadius: 18, padding: 14) {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: "Training Trend", trailing: runs.isEmpty ? "No runs yet" : "8 weeks")
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(lastEightWeeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: 7) {
                            Text(String(format: "%.0f", week.km))
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.mutedText)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(LinearGradient(colors: [Color.electricGreen, Color.lime], startPoint: .bottom, endPoint: .top))
                                .frame(height: max(8, CGFloat(week.km / maxKm) * 112))
                                .opacity(week.km == 0 ? 0.25 : 1)
                            Text(week.label)
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.mutedText)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 156, alignment: .bottom)
            }
        }
    }
}

struct MonthlyScheduleCard: View {
    var workouts: [WorkoutSummary]
    var onSelectWorkout: (WorkoutSummary) -> Void

    private var monthDays: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: Date()) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingBlanks = max(0, firstWeekday - calendar.firstWeekday)
        let start = calendar.date(byAdding: .day, value: -leadingBlanks, to: interval.start) ?? interval.start
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var title: String {
        DateFormatter.monthYear.string(from: Date())
    }

    var body: some View {
        GlassCard(cornerRadius: 18, padding: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Color.mutedText)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.mutedText)
                }

                HStack {
                    ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { symbol in
                        Text(String(symbol.prefix(1)))
                            .font(.caption2.bold())
                            .foregroundStyle(Color.mutedText)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 7), spacing: 7) {
                    ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                        let workout = workout(for: date)
                        let isCurrentMonth = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month)
                        Button {
                            if let workout { onSelectWorkout(workout) }
                        } label: {
                            MonthDayCell(date: date, workout: workout, isCurrentMonth: isCurrentMonth)
                        }
                        .buttonStyle(.plain)
                        .disabled(workout == nil)
                    }
                }
            }
        }
    }

    private func workout(for date: Date) -> WorkoutSummary? {
        guard !workouts.isEmpty else { return nil }
        let index = (Calendar.current.component(.weekday, from: date) + 5) % 7
        let shortWeekday = Calendar.current.shortWeekdaySymbols[Calendar.current.component(.weekday, from: date) - 1]
        let byWeekday = workouts.first { workout in
            String(workout.weekday.prefix(3)).caseInsensitiveCompare(shortWeekday) == .orderedSame
        }
        return byWeekday ?? workouts[index % workouts.count]
    }
}

private struct MonthDayCell: View {
    var date: Date
    var workout: WorkoutSummary?
    var isCurrentMonth: Bool

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(DateFormatter.dayNumber.string(from: date))
                .font(.caption.weight(isToday ? .bold : .semibold))
                .foregroundStyle(isToday ? Color.black : (isCurrentMonth ? Color.white : Color.mutedText.opacity(0.4)))
                .frame(width: 24, height: 24)
                .background(isToday ? Color.lime : Color.clear)
                .clipShape(Circle())

            if let workout, isCurrentMonth {
                Circle()
                    .fill(workout.isComplete ? Color.lime : tint(for: workout.kind))
                    .frame(width: 5, height: 5)
                Text(shortLabel(for: workout.kind))
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.mutedText)
                    .lineLimit(1)
            } else {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 5, height: 5)
                Text(" ")
                    .font(.system(size: 7))
            }
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(isToday ? Color.lime.opacity(0.12) : Color.white.opacity(isCurrentMonth ? 0.035 : 0.015))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func shortLabel(for kind: WorkoutKind) -> String {
        switch kind {
        case .easy: "Easy"
        case .intervals: "Int"
        case .tempo: "Tempo"
        case .hills: "Hills"
        case .strength: "Gym"
        case .recovery: "Rest"
        case .long: "Long"
        case .race: "Race"
        case .parkrun: "Park"
        }
    }

    private func tint(for kind: WorkoutKind) -> Color {
        switch kind {
        case .tempo, .intervals: .orange
        case .hills: .purple
        case .long: .cyan
        case .race: .red
        case .recovery: Color.mutedText
        default: Color.lime
        }
    }
}

private extension DateFormatter {
    static let shortMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()

    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static let dayNumber: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
}
