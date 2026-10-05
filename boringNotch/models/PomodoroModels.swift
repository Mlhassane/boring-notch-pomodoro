//
//  PomodoroModels.swift
//  boringNotch
//
//  Pomodoro value types.
//

import Foundation
import SwiftUI

enum PomodoroMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case focus
    case shortBreak
    case longBreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus:      return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak:  return "Long break"
        }
    }

    var symbol: String {
        switch self {
        case .focus:      return "flame.fill"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak:  return "leaf.fill"
        }
    }

    var tint: Color {
        switch self {
        case .focus:      return Color(red: 1.00, green: 0.36, blue: 0.24)
        case .shortBreak: return Color(red: 0.20, green: 0.79, blue: 0.60)
        case .longBreak:  return Color(red: 0.35, green: 0.60, blue: 1.00)
        }
    }

    var isBreak: Bool { self != .focus }
}

enum PomodoroRunState: String, Hashable {
    case idle
    case running
    case paused
}

struct PomodoroSession: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var start: Date
    var end: Date
    var mode: PomodoroMode
    var actualSeconds: Int
    var completed: Bool
    /// `false` for scraps under 30 s, ignored by the stats.
    var counted: Bool

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}