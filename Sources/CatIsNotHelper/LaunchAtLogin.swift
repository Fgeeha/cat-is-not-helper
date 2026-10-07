import Foundation
import ServiceManagement

/// Автозапуск при входе в систему через SMAppService (macOS 13+).
enum LaunchAtLogin {
    /// Включён, либо зарегистрирован, но ждёт одобрения пользователя в системе.
    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    /// Пользователь отключил элемент в Системных настройках — нужно разрешить вручную.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
