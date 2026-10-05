//
//  PomodoroLiveActivity.swift
//  boringNotch
//
//  Closed-notch widget: a ring, the remaining time and the round counter, in the
//  band under the cutout.
//
//  The music equivalent of this band is the album art plus `AudioSpectrumView`,
//  whose bars move with the track. There is no audio here, so the ring carries
//  the motion instead: a bright head sweeps the circumference and the ring
//  breathes, both of them only while a session is running. Both stop dead on
//  pause. Progress on its own is not enough — over a 25 minute session the arc
//  creeps, and the first frames of a session have no arc at all.
//
//  Colours are neutral, not `mode.tint`. In the notch the timer sits between
//  the album art and the spectrum, and a saturated ring there reads louder than
//  the music it is supposed to sit quietly beside. The tint stays in the Focus
//  tab, where it has room and no neighbours.
//

import SwiftUI
import Defaults

struct PomodoroLiveActivity: View {
    @ObservedObject var pomodoro = PomodoroManager.shared
    @State private var pulse = false

    /// Deliberately achromatic, see the note at the top of the file.
    private let ringTint = Color.white

    var body: some View {
        HStack(spacing: 7) {
            ring

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
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(height: max(0, Defaults[.notchHeight] - 12))
        .padding(.horizontal, 4)
        .animation(
            pomodoro.isRunning
                ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                : .default,
            value: pulse
        )
        .animation(.spring(.bouncy(duration: 0.4)), value: pomodoro.mode)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .onAppear { restartBreathing() }
        .onChange(of: pomodoro.isRunning) { _, _ in restartBreathing() }
    }

    /// The sweep is driven by `PomodoroManager.sweepTick` rather than by a
    /// `TimelineView` or a `withAnimation(.repeatForever)`. Both of those looked
    /// correct in the source and neither moved: the notch is drawn in a
    /// non-activating `NSPanel`, AppKit throttles its CADisplayLink, and the
    /// stored angle simply never left zero. Riding the existing 10 Hz ticker
    /// uses the same path as the countdown digits, which demonstrably repaint.
    private var ring: some View {
        ring(at: Self.sweepAngle)
    }

    /// One full turn every 24 ticks (2.4 s at 10 Hz) — 15° per step, quick enough
    /// to read as motion, slow enough not to strobe.
    private static var sweepAngle: Double {
        Double(PomodoroManager.shared.sweepTick % 24) / 24 * 360
    }

    private func ring(at angle: Double) -> some View {
        PomodoroProgressRing(
            progress: pomodoro.progress,
            // 20 pt is what the music band gives its artwork
            // (`effectiveClosedNotchHeight - 12`), so both read at the same weight.
            size: 20,
            lineWidth: 3,
            tint: ringTint,
            sweep: pomodoro.isRunning,
            sweepAngle: angle
        )
        .scaleEffect(pulse ? 1.1 : 0.82)
        .shadow(color: pulse ? Color.white.opacity(0.55) : .clear, radius: 4)
    }

    /// A repeatForever animation only starts on a value change, so the flag has
    /// to be knocked back to its resting value first and then flipped.
    private func restartBreathing() {
        guard pomodoro.isRunning else {
            pulse = false
            return
        }
        pulse = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
