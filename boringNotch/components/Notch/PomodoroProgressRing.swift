//
//  PomodoroProgressRing.swift
//  boringNotch
//
//  Configurable progress ring. `CircularProgressView` is fixed at 6 pt with no
//  frame, so it cannot serve both the 15 pt notch widget and the 108 pt tab ring.
//

import SwiftUI

struct PomodoroProgressRing: View {
    let progress: Double
    var size: CGFloat = 96
    var lineWidth: CGFloat = 7
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // A round line cap paints a visible dot even at a zero-length trim,
            // so the arc is skipped entirely until there is progress to show.
            if progress > 0.002 {
                Circle()
                    .trim(from: 0, to: min(1, progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: progress)
            }
        }
        .frame(width: size, height: size)
    }
}