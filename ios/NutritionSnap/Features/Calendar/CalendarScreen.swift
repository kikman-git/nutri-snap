import SwiftUI

struct CalendarScreen: View {
    @Environment(MealStore.self) private var store
    var onSnap: () -> Void = {}
    @State private var monthOffset = 0
    @State private var selectedDay: DayLog?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 7)

    private var month: MonthGrid {
        let date = Calendar.current.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
        return MonthGrid(date: date)
    }
    private var target: Nutrients { store.target }
    private func rollup(for date: Date) -> DayRollup? {
        store.rollups.first { $0.id == DayLog.key(for: date) }
    }

    private func loggedDays(in month: MonthGrid) -> [Date] {
        month.cells.compactMap { $0 }.filter { (rollup(for: $0)?.entryCount ?? 0) > 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let month = self.month
                let logged = loggedDays(in: month)
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header(month)
                    if logged.isEmpty {
                        EmptyJournal(onSnap: onSnap)
                    } else {
                        streakBanner(inRange: logged.filter { rollup(for: $0)?.band(target: target) == .inRange }.count)
                        weekdayHeader(month)
                        grid(month)
                        Legend()
                        NutrientGuideView()
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Palette.background)
            .navigationDestination(item: $selectedDay) { day in
                DayDetailView(day: day, target: target)
            }
            .task {
                if ProcessInfo.processInfo.environment["OPEN_DAY"] != nil {
                    selectedDay = await store.entries(on: Date())
                }
            }
        }
    }

    private func header(_ month: MonthGrid) -> some View {
        HStack {
            Text(month.title).font(Theme.Typography.title).foregroundStyle(Theme.Palette.ink)
            Spacer()
            HStack(spacing: Theme.Spacing.sm) {
                navButton("chevron.left") { monthOffset -= 1 }
                navButton("chevron.right") { monthOffset += 1 }
            }
        }
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .frame(width: 36, height: 36)
                .background(Theme.Palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func streakBanner(inRange: Int) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(inRange) \(inRange == 1 ? "day" : "days")").font(Theme.Typography.numeral(24))
                    .foregroundStyle(.white)
                Text("in range this month").font(Theme.Typography.caption).foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
            Text("a calm, even rhythm")
                .font(Theme.Typography.accent).foregroundStyle(.white)
                .multilineTextAlignment(.trailing).frame(maxWidth: 130)
        }
        .padding(Theme.Spacing.md)
        .background(
            LinearGradient(colors: [Theme.Palette.honey, Theme.Palette.bandOver],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
        .amberButtonShadow()
    }

    private func weekdayHeader(_ month: MonthGrid) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(month.weekdaySymbols.indices, id: \.self) { i in
                Text(month.weekdaySymbols[i])
                    .font(.custom("HankenGrotesk-Bold", size: 11))
                    .foregroundStyle(Theme.Palette.tabInactive)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func grid(_ month: MonthGrid) -> some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
            ForEach(month.cells.indices, id: \.self) { index in
                if let date = month.cells[index] {
                    DayCell(date: date, rollup: rollup(for: date), target: target,
                            isToday: month.isToday(date), isFuture: month.isFuture(date)) {
                        Task { selectedDay = await store.entries(on: date) }
                    }
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }
}

private struct DayCell: View {
    let date: Date
    let rollup: DayRollup?
    let target: Nutrients
    let isToday: Bool
    let isFuture: Bool
    let action: () -> Void

    private var hasLog: Bool { (rollup?.entryCount ?? 0) > 0 }
    private var band: DayBand { hasLog ? (rollup?.band(target: target) ?? .none) : .none }
    private var day: String { "\(Calendar.current.component(.day, from: date))" }

    var body: some View {
        Button(action: action) {
            Text(day)
                .font(Theme.Typography.numeral(13))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(hasLog ? band.fill : .clear, in: Circle())
                .overlay { if isToday { Circle().strokeBorder(Theme.Palette.accent, lineWidth: 2) } }
        }
        .buttonStyle(.plain)
        .disabled(!hasLog)
    }

    private var textColor: Color {
        if hasLog { return band.onFill }
        if isToday { return Theme.Palette.accent }
        return Theme.Palette.tabInactive
    }
}

private struct Legend: View {
    private let bands: [DayBand] = [.under, .inRange, .over]

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(bands, id: \.self) { band in
                HStack(spacing: 6) {
                    Circle().fill(band.fill).frame(width: 11, height: 11)
                    Text(band.shortLabel).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.inkSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct EmptyJournal: View {
    var onSnap: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer(minLength: Theme.Spacing.xxl)
            Image(systemName: "book.closed")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 150, height: 150)
                .background(Theme.Palette.amberTintBg, in: Circle())
            Text("Your journal starts here").font(Theme.Typography.title).foregroundStyle(Theme.Palette.ink)
            Text("snap your first meal and watch the month fill in").accentLine()
                .multilineTextAlignment(.center)
            Spacer(minLength: Theme.Spacing.xl)
            Button("Snap a meal", action: onSnap).buttonStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, Theme.Spacing.xxl)
    }
}

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

        let symbols = calendar.shortWeekdaySymbols
        let firstIndex = calendar.firstWeekday - 1
        self.weekdaySymbols = Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])

        let titleFormatter = DateFormatter()
        titleFormatter.calendar = calendar
        titleFormatter.locale = calendar.locale ?? .current
        titleFormatter.setLocalizedDateFormatFromTemplate("yMMMM")
        self.title = titleFormatter.string(from: firstOfMonth)
    }

    func isToday(_ date: Date) -> Bool { calendar.isDate(date, inSameDayAs: today) }
    func isFuture(_ date: Date) -> Bool {
        calendar.startOfDay(for: date) > calendar.startOfDay(for: today)
    }
}

#Preview {
    CalendarScreen().environment(MealStore.sample)
}
