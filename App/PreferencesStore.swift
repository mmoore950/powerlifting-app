import Foundation
import LiftingCore

struct PreferencesStore {
    let defaults: UserDefaults
    private let key = "liftToolkit.preferences"
    private let recoveryKey = "liftToolkit.preferences.recoveryBackup"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> PreferencesRecovery {
        let stored = defaults.object(forKey: key)
        let data = stored as? Data
        let recovery = PreferencesCodec.recover(stored == nil ? nil : (data ?? Data()))
        // Preserve unknown/corrupt bytes before a subsequent explicit settings change overwrites them.
        if recovery.kind == .reset, let stored { defaults.set(stored, forKey: recoveryKey) }
        if recovery.kind == .migrated { try? save(recovery.preferences) }
        return recovery
    }
    func save(_ preferences: AppPreferences) throws {
        defaults.set(try PreferencesCodec.encode(preferences), forKey: key)
    }
}
