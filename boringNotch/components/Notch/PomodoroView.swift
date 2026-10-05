//
//  PomodoroView.swift
//  boringNotch
//
//  The Focus tab: timer, controls, round progress and today's stats.
//
//  Height budget: the open panel is 190 pt and `BoringHeader` (which carries the
//  tab bar) takes `effectiveClosedNotchHeight` — 32 pt on a notched display —
//  leaving 158 pt. Everything below is sized against that budget; overflow pushes
//  the header out of the clipped frame and eats the rounded bottom corners.
//
//  The left column deliberately mirrors the music tab's arrangement — title line,
//  progress bar with elapsed / total, transport row — so switching tabs does not
//  feel like switching to a different application.
//

import SwiftUI
import Defaults

private enum Metrics {
    static let ringSize: CGFloat = 64
    static let ringLine: CGFloat = 7
    static let playSize: CGFloat = 36
    static let sideButton: CGFloat = 26
    static let timerColumnWidth: CGFloat = 220
    static let columnSpacing: CGFloat = 18
}

struct PomodoroView: View {
    @ObservedObject var pomodoro = PomodoroManager.shared
    @State private var confirmClear = false

    private var tint: Color { pomodoro.mode.tint }

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.columnSpacing) {
            timerColumn
            statsColumn
        }
        .padding(.horizontal, 4)
        .frame(maxHeight: .infinity, alignment: .top)
        .sensoryFeedback(.impact(weight: .light), trigger: pomodoro.isRunning)
    }

    // MARK: - Timer

    private var timerColumn: some View {
        VStack(spacing: 5) {
            // Mirrors the music tab: a bold title line on top, the round dots
            // sitting on the right of that same line.
            HStack(alignment: .firstTextBaseline) {
                Text(pomodoro.state == .paused ? "Paused" : pomodoro.mode.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 6)

                HStack(spacing: 4) {
                    ForEach(0..<max(1, pomodoro.sessionsPerRound), id: \.self) { index in
                        Circle()
                            .fill(index < pomodoro.sessionsInRound ? tint : Color.white.opacity(0.22))
                            .frame(width: 5, height: 5)
                    }
                }
            }

            ZStack {
                PomodoroProgressRing(
                    progress: pomodoro.progress,
                    size: Metrics.ringSize,
                    lineWidth: Metrics.ringLine,
                    tint: tint
                )

                Text(pomodoro.formattedRemaining)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .frame(height: Metrics.ringSize)

            // Same slot as the music tab's scrubber: a bar with elapsed on the
            // left and the full duration on the right.
            VStack(spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                        Capsule()
                            .fill(tint)
                            .frame(width: geo.size.width * pomodoro.progress)
                    }
                }
                .frame(height: 3)

                HStack {
                    Text(Self.shortFormat(elapsed))
                    Spacer()
                    Text(Self.shortFormat(pomodoro.total))
                }
                .font(.system(size: 8))
                .monospacedDigit()
                .foregroundStyle(.gray)
            }
            .animation(.linear(duration: 0.25), value: pomodoro.progress)

            HStack(spacing: 10) {
                sideButton("stop.fill", enabled: canReset) {
                    pomodoro.reset()
                }

                // Their `HoverButton` carries the `.symbolEffect` transition that
                // morphs play ↔ pause, same as the music controls.
                ZStack {
                    Circle()
                        .fill(tint)
                        .frame(width: Metrics.playSize, height: Metrics.playSize)
                    HoverButton(
                        icon: pomodoro.isRunning ? "pause.fill" : "play.fill",
                        iconColor: .white,
                        scale: .medium
                    ) {
                        pomodoro.toggle()
                    }
                }
                .frame(width: Metrics.playSize + 4, height: Metrics.playSize + 4)
                .contentShape(Circle())

                sideButton("forward.end.fill", enabled: true) {
                    pomodoro.skip()
                }
            }
            .frame(height: Metrics.playSize + 4)
        }
        .frame(width: Metrics.timerColumnWidth)
    }

    private var elapsed: TimeInterval { max(0, pomodoro.total - pomodoro.remaining) }

    /// `m:ss`, matching how the music tab labels its scrubber.
    private static func shortFormat(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded(.down))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var canReset: Bool {
        pomodoro.state != .idle || pomodoro.progress > 0
    }

    // MARK: - Stats

    private var statsColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: Binding(
                get: { pomodoro.mode },
                set: { pomodoro.select($0) }
            )) {
                ForEach(PomodoroMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            HStack(spacing: 6) {
                tile(PomodoroManager.durationLabel(pomodoro.todayFocusSeconds), "today", pomodoro.mode.tint)
                tile("\(pomodoro.todaySessionCount)",
                     pomodoro.todaySessionCount == 1 ? "session" : "sessions",
                     .green)
                tile("\(pomodoro.currentStreak)", "day streak", .blue)
            }

            weekChart
                .frame(height: 38)

            HStack {
                Text("All time")
                    .font(.system(size: 8))
                    .foregroundStyle(.gray)
                Spacer()
                Text("\(PomodoroManager.durationLabel(pomodoro.totalFocusSeconds)) · \(pomodoro.sessions.count) sessions")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            if confirmClear {
                HStack(spacing: 10) {
                    Text("Delete history?")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Cancel") { confirmClear = false }
                        .buttonStyle(PlainButtonStyle())
                        .font(.system(size: 9))
                        .foregroundStyle(.gray)
                    Button("Delete") {
                        pomodoro.clearHistory()
                        confirmClear = false
                    }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.red)
                }
            } else {
                Button("Clear history") { confirmClear = true }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 8))
                    .foregroundStyle(.gray.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pieces

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 7))
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var weekChart: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days: [(Date, Int)] = (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, pomodoro.focusSeconds(on: day))
        }
        let peak = max(days.map(\.1).max() ?? 0, 1)
        let barHeight: CGFloat = 26

        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(days, id: \.0) { day, seconds in
                VStack(spacing: 2) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.07))
                            .frame(height: barHeight)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(seconds > 0 ? pomodoro.mode.tint.opacity(0.8) : .clear)
                            .frame(height: max(2, barHeight * Double(seconds) / Double(peak)))
                    }
                    .frame(height: barHeight)

                    Text(Self.weekdayLetter(day))
                        .font(.system(size: 7))
                        .foregroundStyle(calendar.isDateInToday(day) ? .white : .gray)
                }
            }
        }
    }

    private static func weekdayLetter(_ date: Date) -> String {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let index = Calendar.current.component(.weekday, from: date) - 1
        guard symbols.indices.contains(index) else { return "" }
        return String(symbols[index].prefix(1)).uppercased()
    }

    private func sideButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Metrics.sideButton, height: Metrics.sideButton)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }
}