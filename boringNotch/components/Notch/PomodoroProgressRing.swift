//
//  PomodoroProgressRing.swift
//  boringNotch
//
//  Configurable progress ring. `CircularProgressView` is fixed at 6 pt with no
//  frame, so it cannot serve both the 20 pt notch widget and the 64 pt tab ring.
//
//  `sweep` draws a bright head travelling around the circumference. Progress alone
//  is not readable as motion in a 20 pt ring — on a 25 minute session the arc
//  creeps — so the sweep carries the "this is running" signal the way the music
//  band lets `AudioSpectrumView` carry it. `sweepAngle` is driven by the caller.
//

import SwiftUI

struct PomodoroProgressRing: View {
    let progress: Double
    var size: CGFloat = 96
    var lineWidth: CGFloat = 7
    let tint: Color
    var sweep: Bool = false
    var sweepAngle: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.22), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // A round line cap paints a visible dot even at a zero-length trim,
            // so the arc is skipped entirely until there is progress to show.
            if progress > 0.002 {
                Circle()
                    .trim(from: 0, to: min(1, progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: progress)
            }

            if sweep {
                Circle()
                    .fill(tint)
                    .frame(width: lineWidth * 1.7, height: lineWidth * 1.7)
                    .offset(y: -(size / 2) + lineWidth / 2)
                    .rotationEffect(.degrees(sweepAngle))
            }
        }
        .frame(width: size, height: size)
    }
}
