//
//  PomodoroLiveActivity.swift
//  boringNotch
//
//  Closed-notch widget: a small ring and the remaining time, in the band under
//  the cutout. Shown whenever a session is running or paused.
//
//  The music equivalent of this band is the album art plus `AudioSpectrumView`,
//  whose bars move with the track. There is no audio here, so the ring breathes
//  and casts a tinted glow while a session runs: same "this is alive" signal,
//  driven by the session instead of by sound. It settles the moment the timer
//  is paused or done.
//

import SwiftUI
import Defaults

struct PomodoroLiveActivity: View {
    @ObservedObject var pomodoro = PomodoroManager.shared
    @State private var pulse = false

    private var tint: Color { pomodoro.mode.tint }

    var body: some View {
        HStack(spacing: 7) {
            PomodoroProgressRing(progress: pomodoro.progress, size: 15, lineWidth: 2.5, tint: tint)
                .scaleEffect(pulse ? 1 : 0.8)
                .shadow(color: pulse ? tint.opacity(0.8) : .clear, radius: 3)

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
        .animation(
            pomodoro.isRunning
                ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
                : .default,
            value: pulse
        )
        .animation(.spring(.bouncy(duration: 0.4)), value: pomodoro.mode)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .onAppear { restartPulse() }
        .onChange(of: pomodoro.isRunning) { _, _ in restartPulse() }
    }

    /// A repeatForever animation only starts on a value change, so the flag has
    /// to be knocked back to its resting value first and then flipped.
    private func restartPulse() {
        guard pomodoro.isRunning else {
            pulse = false
            return
        }
        pulse = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pulse = true }
    }
}
