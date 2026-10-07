import AppKit
import SwiftUI

enum Paw { case left, right }

enum Mood: Equatable {
    case normal, happy, sleepy, grumpy, excited
}

func moodTitle(_ mood: Mood) -> String {
    switch mood {
    case .normal: return "спокойный"
    case .happy: return "довольный"
    case .sleepy: return "спит"
    case .grumpy: return "ворчит"
    case .excited: return "в ударе"
    }
}

func moodEmoji(_ mood: Mood) -> String {
    switch mood {
    case .normal: return "😺"
    case .happy: return "😸"
    case .sleepy: return "😴"
    case .grumpy: return "😾"
    case .excited: return "🙀"
    }
}

struct Heart: Identifiable {
    let id = UUID()
    let x: CGFloat
    var risen = false
}

/// Живое состояние котика: лапки, настроение, что держит, пузырьки.
final class CatState: ObservableObject {
    @Published var leftDown = false
    @Published var rightDown = false
    @Published var happiness: Double = 0.6
    @Published var mood: Mood = .normal
    @Published var blinking = false
    @Published var bubble: String?
    @Published var heldImage: NSImage?
    @Published var heldURL: URL?
    @Published var eating = false
    @Published var hearts: [Heart] = []
    @Published var needsAccess = false

    var bubblesEnabled = true
    private(set) var lastActivity = Date()
    private var petBoostUntil = Date.distantPast
    private var releaseLeft: DispatchWorkItem?
    private var releaseRight: DispatchWorkItem?
    private var bubbleItem: DispatchWorkItem?
    private var lastRandomBubble = Date()
    private var tapsSinceBubble = 0

    static let idlePhrases = [
        "мяу", "я не помогаю, я тапаю", "это не баг, это фича", "коммитить будешь?",
        "мур-р", "дай скриншот подержать", "кто тут хороший разработчик?", "а перерыв?",
        "тесты зелёные?", "мяу-мяу (одобряю)",
    ]
    static let fastPhrases = ["быстрее!", "ого!", "лапки горят 🔥", "не успеваю!", "ты робот?"]

    init() {
        scheduleBlink()
    }

    // MARK: - Тапы

    func tap(_ paw: Paw) {
        lastActivity = Date()
        happiness = min(1, happiness + 0.001)
        tapsSinceBubble += 1
        switch paw {
        case .left:
            releaseLeft?.cancel()
            withAnimation(.easeOut(duration: 0.04)) { leftDown = true }
            let item = DispatchWorkItem { [weak self] in
                withAnimation(.easeIn(duration: 0.08)) { self?.leftDown = false }
            }
            releaseLeft = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
        case .right:
            releaseRight?.cancel()
            withAnimation(.easeOut(duration: 0.04)) { rightDown = true }
            let item = DispatchWorkItem { [weak self] in
                withAnimation(.easeIn(duration: 0.08)) { self?.rightDown = false }
            }
            releaseRight = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
        }
    }

    // MARK: - Взаимодействие

    func pet() {
        lastActivity = Date()
        happiness = min(1, happiness + 0.08)
        petBoostUntil = Date().addingTimeInterval(2.5)
        withAnimation(.easeInOut(duration: 0.2)) { mood = .happy }
        say(["мурр", "ещё!", "вот тут, да", "❤️", "мр-р-р"].randomElement()!)
        spawnHeart()
    }

    func feed() {
        guard !eating else { return }
        lastActivity = Date()
        happiness = min(1, happiness + 0.25)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { eating = true }
        say(["ням-ням", "рыбка!", "спасибо 🐟", "ом-ном-ном"].randomElement()!)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.2)) { self.eating = false }
            self.petBoostUntil = Date().addingTimeInterval(3)
        }
    }

    func hold(url: URL) {
        guard let image = ImageLoader.thumbnail(url: url, maxPixel: 480) else {
            say("это не картинка 🤔")
            return
        }
        lastActivity = Date()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            heldImage = image
            heldURL = url
        }
        say(["держу!", "о, скриншот", "не потеряю", "моя прелесть"].randomElement()!)
    }

    func putAway() {
        withAnimation(.easeInOut(duration: 0.25)) {
            heldImage = nil
            heldURL = nil
        }
        say("ладно, забирай")
    }

    func say(_ text: String, seconds: Double = 2.6) {
        guard bubblesEnabled else { return }
        bubbleItem?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { bubble = text }
        let item = DispatchWorkItem { [weak self] in
            withAnimation(.easeIn(duration: 0.2)) { self?.bubble = nil }
        }
        bubbleItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    // MARK: - Тик раз в секунду

    func tick(cpm: Int) {
        let now = Date()
        happiness = max(0, happiness - 0.0003)
        let idle = now.timeIntervalSince(lastActivity)

        let newMood: Mood
        if eating || now < petBoostUntil {
            newMood = .happy
        } else if idle > 120 {
            newMood = .sleepy
        } else if cpm >= 220 {
            newMood = .excited
        } else if happiness > 0.8 {
            newMood = .happy
        } else if happiness < 0.2 {
            newMood = .grumpy
        } else {
            newMood = .normal
        }
        if newMood != mood {
            withAnimation(.easeInOut(duration: 0.25)) { mood = newMood }
        }

        if bubble == nil, idle < 20, now.timeIntervalSince(lastRandomBubble) > 45, tapsSinceBubble > 60 {
            lastRandomBubble = now
            tapsSinceBubble = 0
            if Int.random(in: 0..<3) == 0 {
                let pool = cpm >= 220 ? Self.fastPhrases : Self.idlePhrases
                say(pool.randomElement()!)
            }
        }
    }

    // MARK: - Внутреннее

    private func scheduleBlink() {
        let delay = Double.random(in: 2.5...6)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if self.mood != .sleepy {
                self.blinking = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    self?.blinking = false
                }
            }
            self.scheduleBlink()
        }
    }

    private func spawnHeart() {
        let heart = Heart(x: CGFloat.random(in: 95...165))
        hearts.append(heart)
        DispatchQueue.main.async { [weak self] in
            guard let self, let i = self.hearts.firstIndex(where: { $0.id == heart.id }) else { return }
            withAnimation(.easeOut(duration: 1.2)) { self.hearts[i].risen = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            self?.hearts.removeAll { $0.id == heart.id }
        }
    }
}
