import SwiftUI
import Combine

enum FurStyle: String, CaseIterable, Identifiable {
    case ginger, gray, black, white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ginger: return "Рыжий"
        case .gray: return "Серый"
        case .black: return "Чёрный"
        case .white: return "Белый"
        }
    }

    var fur: Color {
        switch self {
        case .ginger: return Color(red: 0.95, green: 0.65, blue: 0.27)
        case .gray: return Color(red: 0.62, green: 0.64, blue: 0.68)
        case .black: return Color(red: 0.19, green: 0.19, blue: 0.22)
        case .white: return Color(red: 0.96, green: 0.95, blue: 0.93)
        }
    }

    var belly: Color {
        switch self {
        case .ginger: return Color(red: 1.0, green: 0.95, blue: 0.86)
        case .gray: return Color(red: 0.88, green: 0.89, blue: 0.91)
        case .black: return Color(red: 0.33, green: 0.33, blue: 0.37)
        case .white: return Color.white
        }
    }

    var stripe: Color? {
        switch self {
        case .ginger: return Color(red: 0.82, green: 0.47, blue: 0.14)
        case .gray: return Color(red: 0.42, green: 0.44, blue: 0.49)
        default: return nil
        }
    }

    var eye: Color {
        switch self {
        case .black: return Color(red: 0.98, green: 0.78, blue: 0.2)
        case .white: return Color(red: 0.25, green: 0.55, blue: 0.85)
        default: return Color(red: 0.16, green: 0.14, blue: 0.13)
        }
    }

    var outline: Color {
        self == .black ? Color.white.opacity(0.55) : Color.black.opacity(0.55)
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let ud = UserDefaults.standard

    @Published var scale: Double { didSet { ud.set(scale, forKey: "scale") } }
    @Published var opacity: Double { didSet { ud.set(opacity, forKey: "opacity") } }
    @Published var fur: FurStyle { didSet { ud.set(fur.rawValue, forKey: "fur") } }
    @Published var alwaysOnTop: Bool { didSet { ud.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    @Published var allSpaces: Bool { didSet { ud.set(allSpaces, forKey: "allSpaces") } }
    @Published var bubbles: Bool { didSet { ud.set(bubbles, forKey: "bubbles") } }
    @Published var catVisible: Bool { didSet { ud.set(catVisible, forKey: "catVisible") } }

    private init() {
        scale = ud.object(forKey: "scale") as? Double ?? 1.0
        opacity = ud.object(forKey: "opacity") as? Double ?? 1.0
        fur = FurStyle(rawValue: ud.string(forKey: "fur") ?? "") ?? .ginger
        alwaysOnTop = ud.object(forKey: "alwaysOnTop") as? Bool ?? true
        allSpaces = ud.object(forKey: "allSpaces") as? Bool ?? true
        bubbles = ud.object(forKey: "bubbles") as? Bool ?? true
        catVisible = ud.object(forKey: "catVisible") as? Bool ?? true
    }
}
