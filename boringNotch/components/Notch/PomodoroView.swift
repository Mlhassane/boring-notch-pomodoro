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

import SwiftUI
import Defaults

private enum Metrics {
    static let ringSize: CGFloat = 78
    static let ringLine: CGFloat = 6
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
            ZStack {
                PomodoroProgressRing(
                    progress: pomodoro.progress,
                    size: Metrics.ringSize,
                    lineWidth: Metrics.ringLine,
                    tint: tint
                )

                VStack(spacing: 0) {
                    Text(pomodoro.formattedRemaining)
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(pomodoro.state == .paused ? "PAUSED" : pomodoro.mode.title.uppercased())
                        .font(.system(size: 7, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(tint)
                }
            }
            .frame(height: Metrics.ringSize)

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

            HStack(spacing: 5) {
                ForEach(0..<max(1, pomodoro.sessionsPerRound), id: \.self) { index in
                    Circle()
                        .fill(index < pomodoro.sessionsInRound ? tint : Color.white.opacity(0.22))
                        .frame(width: 5, height: 5)
                }
            }

            Text("\(pomodoro.sessionsInRound) of \(pomodoro.sessionsPerRound) sessions")
                .font(.system(size: 8))
                .foregroundStyle(.gray)
        }
        .frame(width: Metrics.timerColumnWidth)
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