import SwiftUI
import LocalAuthentication
import CryptoKit
import Security

// MARK: - PIN storage (Keychain; only a salted hash of the PIN is kept)

enum PinStore {
    nonisolated private static let service = "pl.moja.usbphotobackup.pin"

    nonisolated private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "pin"]
    }

    @discardableResult
    nonisolated static func save(_ data: Data) -> Bool {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    nonisolated static func load() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    nonisolated static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

// MARK: - App lock (4-digit PIN, optionally Face ID / Touch ID)

@MainActor
final class AppLock: ObservableObject {
    private static let enabledKey = "appLockEnabled"
    private static let biometricsKey = "appLockBiometrics"
    private static let failedKey = "appLockFailed"
    private static let untilKey = "appLockUntil"
    private static let maxAttempts = 5

    @Published private(set) var isEnabled: Bool
    @Published var isLocked: Bool
    @Published var useBiometrics: Bool {
        didSet { UserDefaults.standard.set(useBiometrics, forKey: Self.biometricsKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        var enabled = defaults.bool(forKey: Self.enabledKey)
        if enabled && PinStore.load() == nil {
            enabled = false                       // PIN missing: don't lock the user out
            defaults.set(false, forKey: Self.enabledKey)
        }
        if !enabled {
            // The Keychain survives deleting the app. A PIN left over from an earlier install is dropped,
            // so deleting and reinstalling the app is the way out if the PIN is forgotten.
            PinStore.delete()
        }
        isEnabled = enabled
        isLocked = enabled
        useBiometrics = defaults.object(forKey: Self.biometricsKey) as? Bool ?? true
    }

    // MARK: Biometrics

    private var biometryType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return .none }
        return context.biometryType
    }

    var biometryAvailable: Bool { biometryType != .none }

    var biometryName: String {
        switch biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return tr("Biometria", "Biometrics")
        }
    }

    var biometryIcon: String { biometryType == .touchID ? "touchid" : "faceid" }

    func unlockWithBiometrics() async {
        guard isEnabled, isLocked, useBiometrics, biometryAvailable, secondsLeft() == 0 else { return }
        let context = LAContext()
        context.localizedFallbackTitle = ""      // hides "Enter Passcode": the app has its own PIN
        let reason = tr("Odblokuj aplikację USB Backup", "Unlock USB Backup")
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)) ?? false
        if ok { unlockSucceeded() }
    }

    // MARK: PIN

    private func hash(_ pin: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(pin.utf8)))
    }

    func setPIN(_ pin: String) {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        guard PinStore.save(salt + hash(pin, salt: salt)) else { return }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.enabledKey)
        defaults.set(0, forKey: Self.failedKey)
        defaults.removeObject(forKey: Self.untilKey)
        isEnabled = true
        isLocked = false
        if !biometryAvailable { useBiometrics = false }
        objectWillChange.send()
    }

    /// Seconds left of the temporary block after too many wrong PINs (0 = not blocked).
    func secondsLeft(at date: Date = Date()) -> Int {
        guard let until = UserDefaults.standard.object(forKey: Self.untilKey) as? Date else { return 0 }
        return max(0, Int(until.timeIntervalSince(date).rounded(.up)))
    }

    /// Checks the PIN. Wrong tries are counted; every 5th in a row blocks further tries for a while.
    func verify(_ pin: String) -> Bool {
        guard secondsLeft() == 0, let stored = PinStore.load(), stored.count == 16 + 32 else { return false }
        let salt = stored.prefix(16)
        let expected = stored.suffix(32)
        let defaults = UserDefaults.standard
        if hash(pin, salt: Data(salt)) == Data(expected) {
            defaults.set(0, forKey: Self.failedKey)
            defaults.removeObject(forKey: Self.untilKey)
            return true
        }
        let failed = defaults.integer(forKey: Self.failedKey) + 1
        defaults.set(failed, forKey: Self.failedKey)
        if failed % Self.maxAttempts == 0 {
            let seconds = 30 * (failed / Self.maxAttempts)
            defaults.set(Date().addingTimeInterval(TimeInterval(min(seconds, 600))), forKey: Self.untilKey)
        }
        objectWillChange.send()
        return false
    }

    func unlock(with pin: String) -> Bool {
        guard verify(pin) else { return false }
        unlockSucceeded()
        return true
    }

    private func unlockSucceeded() {
        UserDefaults.standard.set(0, forKey: Self.failedKey)
        UserDefaults.standard.removeObject(forKey: Self.untilKey)
        isLocked = false
    }

    func lockIfEnabled() {
        if isEnabled { isLocked = true }
    }

    func disable() {
        PinStore.delete()
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        isEnabled = false
        isLocked = false
    }
}

// MARK: - Views

/// Numeric keypad with four dots.
struct PinPad: View {
    @Binding var entry: String
    var disabled = false
    var onFull: () -> Void

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]
    private let length = 4

    var body: some View {
        VStack(spacing: 30) {
            HStack(spacing: 18) {
                ForEach(0..<length, id: \.self) { index in
                    Circle()
                        .fill(index < entry.count ? Color.primary : Color.clear)
                        .overlay(Circle().stroke(Color.primary.opacity(0.45), lineWidth: 1.5))
                        .frame(width: 16, height: 16)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(76), spacing: 22), count: 3), spacing: 18) {
                ForEach(keys, id: \.self) { key in
                    keyView(key)
                }
            }
        }
        .opacity(disabled ? 0.4 : 1)
    }

    @ViewBuilder
    private func keyView(_ key: String) -> some View {
        if key.isEmpty {
            Color.clear.frame(width: 76, height: 76)
        } else if key == "⌫" {
            Button {
                if !entry.isEmpty { entry.removeLast() }
            } label: {
                Image(systemName: "delete.left")
                    .font(.title2)
                    .frame(width: 76, height: 76)
            }
            .disabled(disabled)
        } else {
            Button {
                guard !disabled, entry.count < length else { return }
                entry.append(key)
                if entry.count == length {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { onFull() }
                }
            } label: {
                Text(key)
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .frame(width: 76, height: 76)
                    .background(Color(.secondarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(disabled)
        }
    }
}

/// Full-screen cover shown while the app is locked.
struct LockScreenView: View {
    @ObservedObject var lock: AppLock
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appTheme) private var theme
    @State private var entry = ""
    @State private var wrong = false
    @State private var asking = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 26) {
                Spacer(minLength: 0)
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(theme.accent)
                Text(tr("Wpisz PIN", "Enter PIN"))
                    .font(.system(.title2, design: .rounded, weight: .bold))

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = lock.secondsLeft(at: context.date)
                    VStack(spacing: 22) {
                        Group {
                            if left > 0 {
                                Text(tr("Zbyt wiele prób. Spróbuj za \(left) s.", "Too many tries. Try again in \(left) s."))
                                    .foregroundStyle(.orange)
                            } else if wrong {
                                Text(tr("Zły PIN", "Wrong PIN"))
                                    .foregroundStyle(.red)
                            } else {
                                Text(" ")
                            }
                        }
                        .font(.subheadline)
                        PinPad(entry: $entry, disabled: left > 0) { check() }
                    }
                }

                if lock.useBiometrics && lock.biometryAvailable {
                    Button {
                        Task { await tryBiometrics() }
                    } label: {
                        Label(lock.biometryName, systemImage: lock.biometryIcon)
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding()
        }
        .task {
            if scenePhase == .active { await tryBiometrics() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await tryBiometrics() } }
        }
    }

    private func check() {
        let pin = entry
        entry = ""
        if lock.unlock(with: pin) {
            wrong = false
        } else {
            wrong = true
        }
    }

    private func tryBiometrics() async {
        guard !asking else { return }
        asking = true
        defer { asking = false }
        await lock.unlockWithBiometrics()
    }
}

/// Setting, changing and removing the PIN.
struct PinFlowView: View {
    enum Purpose: String, Identifiable {
        case enable, change, disable
        var id: String { rawValue }
    }

    private enum Step { case current, new, confirm }

    let purpose: Purpose
    @ObservedObject var lock: AppLock
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var entry = ""
    @State private var firstPIN = ""
    @State private var message: String?

    init(purpose: Purpose, lock: AppLock) {
        self.purpose = purpose
        self.lock = lock
        _step = State(initialValue: purpose == .enable ? .new : .current)
    }

    private var title: String {
        switch step {
        case .current: return tr("Wpisz obecny PIN", "Enter your current PIN")
        case .new: return tr("Wpisz nowy 4-cyfrowy PIN", "Enter a new 4-digit PIN")
        case .confirm: return tr("Powtórz PIN", "Repeat the PIN")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(message ?? " ")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                PinPad(entry: $entry, disabled: lock.secondsLeft() > 0) { submit() }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Anuluj", "Cancel")) { dismiss() }
                }
            }
        }
    }

    private func submit() {
        let pin = entry
        entry = ""
        switch step {
        case .current:
            if lock.verify(pin) {
                message = nil
                if purpose == .disable {
                    lock.disable()
                    dismiss()
                } else {
                    step = .new
                }
            } else {
                let left = lock.secondsLeft()
                message = left > 0 ? tr("Zbyt wiele prób. Spróbuj za \(left) s.", "Too many tries. Try again in \(left) s.")
                                   : tr("Zły PIN", "Wrong PIN")
            }
        case .new:
            firstPIN = pin
            message = nil
            step = .confirm
        case .confirm:
            if pin == firstPIN {
                lock.setPIN(pin)
                dismiss()
            } else {
                firstPIN = ""
                step = .new
                message = tr("PIN-y się różnią. Spróbuj jeszcze raz.", "The PINs don't match. Try again.")
            }
        }
    }
}
