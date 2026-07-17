import Foundation
import Observation

enum AppSetupMode: String, CaseIterable, Identifiable {
    case hosted
    case byoConnector
    case selfHost

    var id: String { rawValue }
}

@MainActor
@Observable
final class AppSetupModeStore {
    private static let storageKey = "app.setupMode"

    private(set) var mode: AppSetupMode?
    private(set) var isHoldingForBYOPairing = false

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey) {
            mode = AppSetupMode(rawValue: raw)
        }
    }

    static var currentMode: AppSetupMode? {
        guard let raw = UserDefaults.standard.string(forKey: storageKey) else { return nil }
        return AppSetupMode(rawValue: raw)
    }

    var isBYO: Bool {
        mode == .byoConnector
    }

    /// True for any self-managed mode (BYO connector or full self-host).
    var isSelfManaged: Bool {
        mode == .byoConnector || mode == .selfHost
    }

    func choose(_ mode: AppSetupMode) {
        self.mode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.storageKey)
    }

    func holdForBYOPairing() {
        isHoldingForBYOPairing = true
    }

    func releaseBYOPairingHold() {
        isHoldingForBYOPairing = false
    }

    func reset() {
        isHoldingForBYOPairing = false
        mode = nil
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }
}
