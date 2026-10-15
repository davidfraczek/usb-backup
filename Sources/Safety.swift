import UIKit
import Network

// MARK: - Battery / Low Power Mode

struct PowerWarning: Equatable, Sendable {
    var lowPowerMode: Bool
    var batteryPercent: Int?
    var charging: Bool

    var title: String {
        if lowPowerMode && !isBatteryLow { return tr("Tryb niskiego zużycia energii", "Low Power Mode is on") }
        return tr("Niski poziom baterii", "Low battery")
    }

    var isBatteryLow: Bool {
        guard let batteryPercent else { return false }
        return batteryPercent < PowerWarning.threshold && !charging
    }

    var message: String {
        var parts: [String] = []
        if isBatteryLow, let batteryPercent {
            parts.append(tr("Bateria: \(batteryPercent)%, telefon się nie ładuje.",
                            "Battery: \(batteryPercent)%, the phone is not charging."))
        }
        if lowPowerMode {
            parts.append(tr("Włączony jest tryb niskiego zużycia energii, który może spowalniać kopię i szybciej wygaszać ekran.",
                            "Low Power Mode is on; it can slow the backup down."))
        }
        parts.append(tr("Pendrive zasila się z telefonu, a jedyny port jest zajęty, więc nie podłączysz zwykłej ładowarki. Najlepiej użyj ładowarki bezprzewodowej (MagSafe/Qi) albo huba USB-C z zasilaniem. Gdy bateria się wyczerpie w trakcie, kopia się przerwie (to bezpieczne: wznowi się od miejsca przerwania).",
                        "The USB drive is powered by the phone and the only port is in use, so a regular charger can't be connected. Best use a wireless charger (MagSafe/Qi) or a powered USB-C hub. If the battery runs out, the backup stops (this is safe: it resumes where it stopped)."))
        return parts.joined(separator: "\n\n")
    }

    static let threshold = 20

    /// A warning if the battery is below 20 % and the phone is not charging, or Low Power Mode is on.
    @MainActor
    static func current() -> PowerWarning? {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel                       // -1 = unknown (e.g. simulator)
        let charging = device.batteryState == .charging || device.batteryState == .full
        let percent = level >= 0 ? Int((level * 100).rounded()) : nil
        let warning = PowerWarning(lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                   batteryPercent: percent,
                                   charging: charging)
        return (warning.isBatteryLow || warning.lowPowerMode) ? warning : nil
    }
}

// MARK: - Cellular data

/// Remembers whether the current network is "expensive" (cellular or Personal Hotspot).
/// iOS has no setting for this in the Photos API, so the app decides itself before it downloads an original from iCloud.
final class NetworkWatcher: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var expensive = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.expensive = path.isExpensive
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "usbbackup.network"))
    }

    var isExpensive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return expensive
    }

    func stop() { monitor.cancel() }
}

/// The original is in iCloud and the phone is on cellular data, which the user didn't allow.
struct CellularBlockedError: LocalizedError {
    var errorDescription: String? {
        tr("Plik jest w iCloud, a telefon jest w sieci komórkowej (pobieranie przez nią jest wyłączone w ustawieniach).",
           "The file is in iCloud and the phone is on cellular data (downloading over it is turned off in Settings).")
    }
}
