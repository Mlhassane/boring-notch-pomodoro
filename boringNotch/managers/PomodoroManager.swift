//
//  PomodoroManager.swift
//  boringNotch
//
//  Pomodoro timer: state machine, rounds, history and end-of-session feedback.
//
//  The countdown is always derived from an absolute deadline rather than
//  decremented per tick, and the heartbeat runs on a dedicated thread: a timer on
//  the main run loop gets starved as soon as another app is frontmost, which
//  would freeze the countdown whenever the user switches windows.
//

import Foundation
import Combine
import AppKit
import UserNotifications
import Defaults

@MainActor
final class PomodoroManager: ObservableObject {
    // MARK: - Properties
    static let shared = PomodoroManager()

    @Published private(set) var mode: PomodoroMode = .focus
    @Published private(set) var state: PomodoroRunState = .idle
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var total: TimeInterval
    @Published private(set) var roundSessions: Int = 0
    @Published private(set) var totalFocusSessions: Int = 0
    /// Bumped on every completion so views can flash.
    @Published private(set) var celebrationToken: Int = 0
    @Published private(set) var sessions: [PomodoroSession] = []
    /// Mirrors `WebcamManager.authorizationStatus`: surfaced in the settings UI so
    /// a denied permission is visible instead of silently swallowing alerts.
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    /// Free-running counter, advanced by the 10 Hz ticker. The closed-notch ring
    /// derives its sweep angle from it. It is deliberately *not* derived from
    /// `remaining`: a 25 minute session moves the progress arc by 0.00007 per
    /// tick, which reads as completely still.
    @Published private(set) var sweepTick: UInt64 = 0

    private var deadline: Date?
    private var startedAt: Date?
    private var tickerThread: Thread?
    private let tickerRunLoop = RunLoopBox()
    private var wakeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    private let storeURL: URL

    // MARK: - Init

    private init() {
        let focus = TimeInterval(Defaults[.pomodoroFocusMinutes] * 60)
        total = focus
        remaining = focus

        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("BoringNotchPomodoro", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appendingPathComponent("sessions.json")

        loadHistory()

        Defaults.publisher(keys: .pomodoroFocusMinutes,
                                   .pomodoroShortBreakMinutes,
                                   .pomodoroLongBreakMinutes)
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.applyDurationChange() }
            }
            .store(in: &cancellables)

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        startTicker()
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        // Inlined rather than calling stopTicker(): deinit of a @MainActor type
        // is nonisolated, so it cannot reach isolated methods.
        tickerThread?.cancel()
        if let runLoop = tickerRunLoop.runLoop {
            CFRunLoopStop(runLoop)
        }
    }

    private final class RunLoopBox: @unchecked Sendable {
        var runLoop: CFRunLoop?
    }

    // MARK: - Ticker

    private func startTicker() {
        let box = tickerRunLoop
        let thread = Thread { [weak self] in
            box.runLoop = CFRunLoopGetCurrent()
            let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
                guard let self else { return }
                Task { @MainActor in self.tick() }
            }
            RunLoop.current.add(timer, forMode: .common)
            while !Thread.current.isCancelled {
                RunLoop.current.run(mode: .default, before: .distantFuture)
            }
        }
        thread.name = "app.boringnotch.pomodoro"
        thread.qualityOfService = .utility
        tickerThread = thread
        thread.start()
    }

    /// Without this the ticker keeps beating — and hopping back onto the main
    /// actor — while the app is trying to terminate, which is enough to keep
    /// the process alive after SIGTERM.
    private func stopTicker() {
        tickerThread?.cancel()
        tickerThread = nil
        if let runLoop = tickerRunLoop.runLoop {
            CFRunLoopStop(runLoop)
            tickerRunLoop.runLoop = nil
        }
    }

    // MARK: - Durations

    func duration(for mode: PomodoroMode) -> TimeInterval {
        switch mode {
        case .focus:      return TimeInterval(Defaults[.pomodoroFocusMinutes] * 60)
        case .shortBreak: return TimeInterval(Defaults[.pomodoroShortBreakMinutes] * 60)
        case .longBreak:  return TimeInterval(Defaults[.pomodoroLongBreakMinutes] * 60)
        }
    }

    var sessionsPerRound: Int { Defaults[.pomodoroSessionsPerRound] }

    private func applyDurationChange() {
        guard state == .idle, deadline == nil else { return }
        let fresh = duration(for: mode)
        total = fresh
        remaining = fresh
    }

    // MARK: - Derived

    var isRunning: Bool { state == .running }

/// Whether the notch widget should be on screen.
    ///
    /// Running or paused is the obvious case, but a skipped session lands on an
    /// *idle* break — hiding the widget there would leave no trace of where the
    /// user just moved to. So it also stays while parked on a break or once the
    /// current round has started. Picking Focus again while idle clears the round
    /// and hands the notch back to the music widget.
    /// The music widget only claims the closed notch while it is playing, and the
    /// Pomodoro used to do the same: idle, focused, no round banked and the band
    /// went empty, so the remaining time was unreadable until a session started.
    /// `pomodoroAlwaysInNotch` keeps it on screen between sessions too.
    var isRelevantToNotch: Bool {
        guard !Defaults[.pomodoroAlwaysInNotch] else { return true }
        return state != .idle || mode != .focus || roundSessions > 0
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }

    var formattedRemaining: String { Self.format(remaining) }

    var sessionsInRound: Int { min(roundSessions, sessionsPerRound) }

    static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        guard total > 0 else { return "00:00" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func durationLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    // MARK: - Controls

    func toggle() {
        switch state {
        case .running: pause()
        case .idle, .paused: start()
        }
    }

    func start() {
        if remaining <= 0 {
            remaining = duration(for: mode)
            total = remaining
        }
        startedAt = Date()
        deadline = Date().addingTimeInterval(remaining)
        state = .running
    }

    func pause() {
        guard state == .running else { return }
        tick()
        guard state == .running else { return }
        state = .paused
        deadline = nil
        bankSession(completed: false)
    }

    func reset() {
        state = .idle
        deadline = nil
        bankSession(completed: false)
        let fresh = duration(for: mode)
        total = fresh
        remaining = fresh
    }

    func skip() {
        bankSession(completed: false)
        let next = mode.isBreak ? PomodoroMode.focus : breakModeAfter(crediting: false)
        transition(to: next, creditFocus: false, autoStart: false)
    }

    func select(_ newMode: PomodoroMode) {
        guard newMode != mode else { return }
        bankSession(completed: false)
        // Coming back to Focus from an idle break is the way to say "I'm done with
        // the timer": reset the round so the notch returns to the music widget.
        if newMode == .focus, state == .idle {
            roundSessions = 0
        }
        transition(to: newMode, creditFocus: false, autoStart: false)
    }

    // MARK: - Internals

    private func tick() {
        guard state == .running, let deadline else { return }
        // The closed-notch ring sweeps off this. It rides the existing 10 Hz
        // ticker because a `TimelineView(.animation)` would not run: AppKit
        // throttles CADisplayLink for the non-activating panel the notch is
        // drawn in, so its angle stayed frozen at zero.
        sweepTick &+= 1
        let left = deadline.timeIntervalSinceNow
        if left <= 0 {
            remaining = 0
            complete()
        } else if abs(left - remaining) > 0.05 {
            remaining = left
        }
    }

    private func complete() {
        let finishedMode = mode
        state = .idle
        deadline = nil
        bankSession(completed: true)

        celebrationToken &+= 1

        let next = mode.isBreak ? PomodoroMode.focus : breakModeAfter(crediting: true)
        let shouldAutoStart = mode.isBreak ? Defaults[.pomodoroAutoStartFocus] : Defaults[.pomodoroAutoStartBreaks]
        transition(to: next, creditFocus: true, autoStart: shouldAutoStart)

        // After the transition on purpose: `totalFocusSessions` is bumped inside
        // transition(), so announcing before it always reported the tally as if
        // this session had not happened yet.
        announceCompletion(finishedMode: finishedMode)
    }

    private func breakModeAfter(crediting: Bool) -> PomodoroMode {
        let projected = roundSessions + (crediting ? 1 : 0)
        if projected > 0 && projected % max(1, sessionsPerRound) == 0 {
            return .longBreak
        }
        return .shortBreak
    }

    private func transition(to newMode: PomodoroMode, creditFocus: Bool, autoStart: Bool) {
        if creditFocus && newMode.isBreak {
            roundSessions += 1
            totalFocusSessions += 1
        }
        mode = newMode
        let fresh = duration(for: newMode)
        total = fresh
        remaining = fresh
        deadline = nil
        startedAt = nil
        state = .idle
        if autoStart { start() }
    }

    private func bankSession(completed: Bool) {
        guard let startedAt else { return }
        let elapsed = max(0, total - remaining)
        let record = PomodoroSession(
            start: startedAt,
            end: Date(),
            mode: mode,
            actualSeconds: Int(elapsed),
            completed: completed,
            counted: elapsed >= 30
        )
        sessions.append(record)
        if sessions.count > 500 { sessions.removeFirst(sessions.count - 500) }
        saveHistory()
        self.startedAt = nil
    }

    // MARK: - Feedback

    private func announceCompletion(finishedMode: PomodoroMode) {
        if Defaults[.pomodoroSoundEnabled] {
            NSSound(named: finishedMode.isBreak ? "Glass" : "Bell")?.play()
        }
        guard Defaults[.pomodoroNotifications] else { return }

        let content = UNMutableNotificationContent()
        switch finishedMode {
        case .focus:
            content.title = "Session complete"
            content.body = "\(totalFocusSessions) done today. Time for a break."
        case .shortBreak:
            content.title = "Break over"
            content.body = "Back to it — the next focus session is ready."
        case .longBreak:
            content.title = "Round complete"
            content.body = "Long break earned. Step away properly."
        }
        content.sound = Defaults[.pomodoroSoundEnabled] ? .default : nil

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                // Ask in context, the first time an alert would actually matter.
                // Doing it at launch is too early for the activation-policy dance
                // to bring an alert forward, so nothing ever appeared.
                Task { @MainActor in self?.requestNotificationPermission() }
            case .authorized, .provisional, .ephemeral:
                center.add(
                    UNNotificationRequest(
                        identifier: "pomodoro.\(UUID().uuidString)",
                        content: content,
                        // Deliver now, rather than a beat after the session ends.
                        trigger: nil
                    )
                )
            default:
                Task { @MainActor in self?.notificationStatus = settings.authorizationStatus }
                break
            }
        }
    }

    func requestNotificationPermission() {
        guard Defaults[.pomodoroNotifications] else { return }
        UNUserNotificationCenter.current()
            .getNotificationSettings { [weak self] settings in
                Task { @MainActor in self?.notificationStatus = settings.authorizationStatus }
                switch settings.authorizationStatus {
                case .notDetermined:
                    // macOS does not show its own prompt for an accessory app:
                    // no Dock icon, nothing to attach it to. So ask through our
                    // own alert, which needs a regular activation policy — the
                    // same dance `BoringViewModel` uses for camera access.
                    Self.presentPermissionAlert()
                case .denied:
                    break // handled by the button in Settings → Focus
                default:
                    break
                }
            }
    }

    /// Same dance as `BoringViewModel.toggleCameraPreview()`: briefly become a
    /// regular app so an alert can be shown, then go back to being an accessory.
    private static func presentPermissionAlert() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = "Notifications for Notches"
            alert.informativeText = "Allow notifications to be reminded when a focus session or a break ends."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Not now")

            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
                UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound]) { granted, err in
                    }
            }

            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
            PomodoroManager.shared.refreshNotificationStatus()
        }
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current()
            .getNotificationSettings { [weak self] settings in
                Task { @MainActor in self?.notificationStatus = settings.authorizationStatus }
            }
    }

    /// Opens the Notifications pane, the only way out of a denied permission.
    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - History

    private var focusSessions: [PomodoroSession] {
        sessions.filter { $0.counted && $0.mode == .focus }
    }

    var todayFocusSeconds: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return focusSessions.filter { $0.start >= start }.reduce(0) { $0 + $1.actualSeconds }
    }

    var todaySessionCount: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return focusSessions.filter { $0.start >= start }.count
    }

    var totalFocusSeconds: Int { focusSessions.reduce(0) { $0 + $1.actualSeconds } }

    /// Consecutive days, ending today or yesterday, with at least one session.
    var currentStreak: Int {
        let calendar = Calendar.current
        let days = Set(focusSessions.map { calendar.startOfDay(for: $0.start) })
        guard !days.isEmpty else { return 0 }
        var cursor = calendar.startOfDay(for: Date())
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    func focusSeconds(on day: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return focusSessions.filter { $0.start >= start && $0.start < end }.reduce(0) { $0 + $1.actualSeconds }
    }

    func clearHistory() {
        sessions.removeAll()
        saveHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([PomodoroSession].self, from: data) else { return }
        sessions = decoded.sorted { $0.start < $1.start }
    }

    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: - Teardown

    /// Banks whatever is in flight so quitting mid-session does not lose it.
    public func destroy() {
        stopTicker()
        if state == .running { tick() }
        bankSession(completed: false)
    }
}
