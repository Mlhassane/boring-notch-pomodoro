//
//  PomodoroLiveActivity.swift
//  boringNotch
//
//  Closed-notch widget: a small ring and the remaining time, in the band under
//  the cutout. Shown whenever a session is running or paused.
//

import SwiftUI
import Defaults

struct PomodoroLiveActivity: View {
    @ObservedObject var pomodoro = PomodoroManager.shared

    private var tint: Color { pomodoro.mode.tint }

    var body: some View {
        HStack(spacing: 7) {
            PomodoroProgressRing(progress: pomodoro.progress, size: 15, lineWidth: 2.5, tint: tint)

            Text(pomodoro.formattedRemaining)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                // contentTransition alone does nothing: the value has to drive it.
                .animation(.snappy(duration: 0.3), value: pomodoro.remaining)

            if Defaults[.pomodoroShowInNotch] {
                Text("\(pomodoro.sessionsInRound)/\(pomodoro.sessionsPerRound)")
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.gray)
            }
        }
        .frame(height: max(0, Defaults[.notchHeight] - 12))
        .padding(.horizontal, 4)
        .animation(.spring(.bouncy(duration: 0.4)), value: pomodoro.mode)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}