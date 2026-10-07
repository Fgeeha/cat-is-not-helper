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

enum Accessory: String, CaseIterable, Identifiable {
    case none, bow, glasses, hat, scarf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Без всего"
        case .bow: return "Бантик"
        case .glasses: return "Очки"
        case .hat: return "Шапка"
        case .scarf: return "Шарф"
        }
    }
}

enum EyeColorChoice: String, CaseIterable, Identifiable {
    case auto, green, blue, amber, brown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "По окрасу"
        case .green: return "Зелёные"
        case .blue: return "Голубые"
        case .amber: return "Янтарные"
        case .brown: return "Карие"
        }
    }

    var color: Color? {
        switch self {
        case .auto: return nil
        case .green: return Color(red: 0.3, green: 0.7, blue: 0.4)
        case .blue: return Color(red: 0.25, green: 0.55, blue: 0.85)
        case .amber: return Color(red: 0.98, green: 0.78, blue: 0.2)
        case .brown: return Color(red: 0.16, green: 0.14, blue: 0.13)
        }
    }
}

enum KeyboardStyle: String, CaseIterable, Identifiable {
    case dark, light, pink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "Тёмная"
        case .light: return "Светлая"
        case .pink: return "Розовая"
        }
    }

    var base: Color {
        switch self {
        case .dark: return Color(red: 0.23, green: 0.25, blue: 0.3)
        case .light: return Color(red: 0.82, green: 0.83, blue: 0.86)
        case .pink: return Color(red: 0.95, green: 0.68, blue: 0.78)
        }
    }

    var keys: Color {
        switch self {
        case .dark: return Color.white.opacity(0.35)
        case .light: return Color.black.opacity(0.25)
        case .pink: return Color.white.opacity(0.6)
        }
    }
}

enum SizePreset: String, CaseIterable, Identifiable {
    case s, m, l, xl

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    var scale: Double {
        switch self {
        case .s: return 0.7
        case .m: return 1.0
        case .l: return 1.4
        case .xl: return 2.0
        }
    }

    static func closest(to scale: Double) -> SizePreset? {
        allCases.first { abs($0.scale - scale) < 0.01 }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let ud = UserDefaults.standard

    static let scaleRange = 0.5...2.5

    @Published var scale: Double { didSet { ud.set(scale, forKey: "scale") } }
    @Published var opacity: Double { didSet { ud.set(opacity, forKey: "opacity") } }
    @Published var fur: FurStyle { didSet { ud.set(fur.rawValue, forKey: "fur") } }
    @Published var accessory: Accessory { didSet { ud.set(accessory.rawValue, forKey: "accessory") } }
    @Published var eyeColor: EyeColorChoice { didSet { ud.set(eyeColor.rawValue, forKey: "eyeColor") } }
    @Published var keyboard: KeyboardStyle { didSet { ud.set(keyboard.rawValue, forKey: "keyboard") } }
    @Published var mirrored: Bool { didSet { ud.set(mirrored, forKey: "mirrored") } }
    @Published var alwaysOnTop: Bool { didSet { ud.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    @Published var allSpaces: Bool { didSet { ud.set(allSpaces, forKey: "allSpaces") } }
    @Published var bubbles: Bool { didSet { ud.set(bubbles, forKey: "bubbles") } }
    @Published var catVisible: Bool { didSet { ud.set(catVisible, forKey: "catVisible") } }

    private init() {
        scale = ud.object(forKey: "scale") as? Double ?? 1.0
        opacity = ud.object(forKey: "opacity") as? Double ?? 1.0
        fur = FurStyle(rawValue: ud.string(forKey: "fur") ?? "") ?? .ginger
        accessory = Accessory(rawValue: ud.string(forKey: "accessory") ?? "") ?? .none
        eyeColor = EyeColorChoice(rawValue: ud.string(forKey: "eyeColor") ?? "") ?? .auto
        keyboard = KeyboardStyle(rawValue: ud.string(forKey: "keyboard") ?? "") ?? .dark
        mirrored = ud.object(forKey: "mirrored") as? Bool ?? false
        alwaysOnTop = ud.object(forKey: "alwaysOnTop") as? Bool ?? true
        allSpaces = ud.object(forKey: "allSpaces") as? Bool ?? true
        bubbles = ud.object(forKey: "bubbles") as? Bool ?? true
        catVisible = ud.object(forKey: "catVisible") as? Bool ?? true
    }
}
