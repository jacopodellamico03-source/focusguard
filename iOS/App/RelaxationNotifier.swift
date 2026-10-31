import Foundation
import RuleEngine
import UserNotifications

/// Notifiche locali delle richieste in attesa. Le decisioni sono in `RelaxationNotificationPlan`.
struct RelaxationNotifier {
    private var center: UNUserNotificationCenter { .current() }

    /// iOS mostra il dialogo solo se non si è ancora risposto.
    func requestPermission() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.app.error("Permesso notifiche: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Allinea le notifiche di iOS alle richieste. Restituisce `true` se il permesso è negato.
    func sync(with requests: [PendingRelaxation]) async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        let scheduled = await center.pendingNotificationRequests().map(\.identifier)
        let delivered = await center.deliveredNotifications().map(\.request.identifier)

        let now = Date()
        let plan = RelaxationNotificationPlan.reconcile(
            requests: requests,
            scheduled: Set(scheduled),
            delivered: Set(delivered),
            now: now
        )
        center.removePendingNotificationRequests(withIdentifiers: Array(plan.toCancel))
        center.removeDeliveredNotifications(withIdentifiers: Array(plan.toRemoveDelivered))

        // Senza permesso non si programma nulla: se arriva dopo, le mancanti partono al riallineamento.
        guard status != .denied, status != .notDetermined else { return status == .denied }
        for notification in plan.toSchedule {
            await schedule(notification, now: now)
        }
        return false
    }

    private func schedule(_ notification: RelaxationNotification, now: Date) async {
        let content = UNMutableNotificationContent()
        content.body = Formatting.notificationBody(for: notification.kind)
        content.sound = .default
        // Intervallo positivo: il piano scarta le date non successive a `now`.
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: notification.fireDate.timeIntervalSince(now),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            Log.app.error("Notifica non programmata: \(error.localizedDescription, privacy: .public)")
        }
    }
}
