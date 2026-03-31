//
//  ReminderScheduler.swift
//  todoMarkdown
//
//  Created by Codex on 2026/3/27.
//

import CryptoKit
import Foundation
import UserNotifications

protocol ReminderScheduling {
    func scheduleAfternoonRemindersIfNeeded(from content: String, pageID: UUID, pageTitle: String)
}

final class UserNotificationReminderScheduler: ReminderScheduling {
    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let scheduledReminderKey = "scheduledAfternoonReminderIDs"

    init(center: UNUserNotificationCenter = .current(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
    }

    func scheduleAfternoonRemindersIfNeeded(from content: String, pageID: UUID, pageTitle: String) {
        let candidates = extractCandidates(from: content)
        guard !candidates.isEmpty else { return }

        Task {
            let granted = await ensureAuthorization()
            guard granted else { return }

            var scheduledIDs = Set(defaults.stringArray(forKey: scheduledReminderKey) ?? [])
            let fireDate = Self.nextAfternoonDate(from: .now)

            for candidate in candidates {
                let identifier = reminderID(pageID: pageID, line: candidate)
                guard !scheduledIDs.contains(identifier) else { continue }

                let content = UNMutableNotificationContent()
                content.title = "下午提醒"
                content.body = candidate.isEmpty ? pageTitle : candidate
                content.sound = .default

                let dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

                do {
                    try await center.add(request)
                    scheduledIDs.insert(identifier)
                } catch {
                    continue
                }
            }

            defaults.set(Array(scheduledIDs), forKey: scheduledReminderKey)
        }
    }

    private func extractCandidates(from content: String) -> [String] {
        content
            .components(separatedBy: "\n")
            .filter { $0.contains("#下午") && $0.contains("@我") }
            .map { line in
                line
                    .replacingOccurrences(of: #"#[^\s#@]+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"@[^\s@]+"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }

    private func reminderID(pageID: UUID, line: String) -> String {
        let raw = "\(pageID.uuidString)::\(line)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        let token = digest.map { String(format: "%02x", $0) }.joined()
        return "todoMarkdown.afternoon.\(token)"
    }

    private func ensureAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func nextAfternoonDate(from now: Date) -> Date {
        let calendar = Calendar.current
        let todayAtTwo = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now) ?? now
        if todayAtTwo > now {
            return todayAtTwo
        }
        return calendar.date(byAdding: .day, value: 1, to: todayAtTwo) ?? todayAtTwo
    }
}
