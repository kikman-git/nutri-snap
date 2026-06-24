import SwiftUI

/// Month grid with calm divergent fill per day (PRD §5.3). Tap a day → photo diary.
struct CalendarScreen: View {
    @Environment(MealStore.self) private var store
    private let month = MonthGrid(date: Date())
    @State private var selectedDay: DayLog?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 7)

    private var target: Nutrients { store.target }
    private func rollup(for date: Date) -> DayRollup? {
        store.rollups.first { $0.id == DayLog.key(for: date) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text(month.title)
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Palette.ink)

                    weekdayHeader

                    LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                        ForEach(month.cells.indices, id: \.self) { index in
                            if let date = month.cells[index] {
                                DayCell(date: date,
                                        rollup: rollup(for: date),
                                        target: target,
                                        isToday: month.isToday(date)) {
                                    Task { selectedDay = await store.entries(on: date) }
                                }
                            } else {
                                Color.clear.frame(height: 44)
                            }
                        }
                    }

                    Legend()

                    NutrientGuideView()
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Palette.background)
            .navigationDestination(item: $selectedDay) { day in
                DayDetailView(day: day, target: target)
            }
            .task {
                // Screenshot hook: OPEN_DAY pushes today's diary on appear (the CLI can't tap a cell).
                if ProcessInfo.processInfo.environment["OPEN_DAY"] != nil {
                    selectedDay = await store.entries(on: Date())
                }
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(month.weekdaySymbols.indices, id: \.self) { index in
                Text(month.weekdaySymbols[index])
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct DayCell: View {
    let date: Date
    let rollup: DayRollup?
    let target: Nutrients
    let isToday: Bool
    let action: () -> Void

    private var hasLog: Bool { (rollup?.entryCount ?? 0) > 0 }
    private var band: DayBand { hasLog ? (rollup?.band(target: target) ?? .none) : .none }
    private var dayNumber: String { "\(Calendar.current.component(.day, from: date))" }

    var body: some View {
        Button(action: action) {
            Text(dayNumber)
                .font(Theme.Typography.body)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(band.onFill)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(band.fill,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .strokeBorder(Theme.Palette.ink.opacity(0.5), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!hasLog)   // only logged days open the diary
    }
}

private struct Legend: View {
    private let bands: [DayBand] = [.under, .inRange, .over]

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(bands, id: \.self) { band in
                HStack(spacing: Theme.Spacing.xs) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(band.fill)
                        .frame(width: 14, height: 14)
                    Text(band.shortLabel)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
            }
        }
    }
}

/// Pure date math for one month's grid (leading blanks + each day cell).
struct MonthGrid {
    let cells: [Date?]
    let weekdaySymbols: [String]
    let title: String
    private let calendar: Calendar
    private let today: Date

    init(date: Date, calendar: Calendar = .current) {
        self.calendar = calendar
        self.today = Date()

        let comps = calendar.dateComponents([.year, .month], from: date)
        let firstOfMonth = calendar.date(from: comps) ?? date

        let range = calendar.range(of: .day, in: .month, for: firstOfMonth) ?? (1..<29)
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)
        let leading = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        let dayDates: [Date?] = range.map { day in
            calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
        }
        self.cells = Array(repeating: nil, count: leading) + dayDates

        // Weekday symbols, reordered to start at the locale's first weekday.
        let symbols = calendar.shortWeekdaySymbols
        let firstIndex = calendar.firstWeekday - 1
        self.weekdaySymbols = Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])

        let titleFormatter = DateFormatter()
        titleFormatter.calendar = calendar
        titleFormatter.locale = calendar.locale ?? .current
        titleFormatter.setLocalizedDateFormatFromTemplate("yMMMM")
        self.title = titleFormatter.string(from: firstOfMonth)
    }

    func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: today)
    }
}

#Preview {
    CalendarScreen().environment(MealStore.sample)
}
