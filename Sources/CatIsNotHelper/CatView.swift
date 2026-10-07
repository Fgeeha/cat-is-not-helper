import SwiftUI

/// Сам котик. Рисуется в дизайн-координатах 260×230 и масштабируется.
struct CatView: View {
    @ObservedObject var state: CatState
    @ObservedObject var settings: AppSettings
    /// Если задан, используется вместо settings.scale (для превью в настройках).
    var fixedScale: Double? = nil

    static let design = CGSize(width: 260, height: 230)

    static func size(for scale: Double) -> CGSize {
        CGSize(width: design.width * scale, height: design.height * scale)
    }

    /// Область картинки в лапках (дизайн-координаты, y вниз) — для перетаскивания наружу.
    static let heldImageRect = CGRect(x: 75, y: 125, width: 110, height: 78)

    private var fur: FurStyle { settings.fur }
    private var holding: Bool { state.heldImage != nil }
    private var scale: Double { fixedScale ?? settings.scale }
    private var eyeColor: Color { settings.eyeColor.color ?? fur.eye }

    var body: some View {
        ZStack {
            // Тело и всё, что можно отразить
            ZStack {
                tail
                Ellipse().fill(fur.fur).frame(width: 150, height: 105).position(x: 130, y: 166)
                Ellipse().fill(fur.belly).frame(width: 86, height: 64).position(x: 130, y: 180)
                ears
                Circle().fill(fur.fur).frame(width: 112, height: 112).position(x: 130, y: 98)
                stripes
                face
                accessoryBehindPaws
                laptop
                heldImage
                PawView(fur: fur, down: settings.mirrored ? state.rightDown : state.leftDown, holding: holding, side: .left)
                PawView(fur: fur, down: settings.mirrored ? state.leftDown : state.rightDown, holding: holding, side: .right)
                food
                hearts
            }
            .scaleEffect(x: settings.mirrored ? -1 : 1, y: 1)
            // Текст не отражаем
            zzz
            bubble
        }
        .frame(width: Self.design.width, height: Self.design.height)
        .scaleEffect(scale)
        .frame(width: Self.design.width * scale, height: Self.design.height * scale)
        .opacity(fixedScale == nil ? settings.opacity : 1)
    }

    // MARK: - Аксессуары

    @ViewBuilder private var accessoryBehindPaws: some View {
        switch settings.accessory {
        case .none:
            EmptyView()
        case .bow:
            BowView().position(x: 92, y: 80)
        case .glasses:
            GlassesShape()
                .stroke(Color(red: 0.2, green: 0.2, blue: 0.25), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 80, height: 30)
                .position(x: 130, y: 97)
        case .hat:
            ZStack {
                Capsule().fill(Color(red: 0.85, green: 0.25, blue: 0.3)).frame(width: 58, height: 30).offset(y: 2)
                Capsule().fill(Color.white.opacity(0.9)).frame(width: 62, height: 10).offset(y: 14)
                Circle().fill(Color.white).frame(width: 14).offset(y: -14)
            }
            .position(x: 130, y: 40)
        case .scarf:
            ZStack {
                Capsule().fill(Color(red: 0.85, green: 0.25, blue: 0.3)).frame(width: 92, height: 18)
                RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.85, green: 0.25, blue: 0.3)).frame(width: 14, height: 30).offset(x: 30, y: 18)
                Capsule().fill(Color.white.opacity(0.7)).frame(width: 10, height: 3).offset(x: 30, y: 29)
            }
            .position(x: 130, y: 152)
        }
    }

    // MARK: - Части

    private var tail: some View {
        let happy = state.mood == .happy || state.mood == .excited
        return TailShape()
            .stroke(fur.fur, style: StrokeStyle(lineWidth: 16, lineCap: .round))
            .rotationEffect(.degrees(happy ? 12 : 0), anchor: UnitPoint(x: 190 / 260, y: 185 / 230))
            .animation(happy ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true)
                             : .easeInOut(duration: 0.4), value: happy)
    }

    private func ear(mirrored: Bool) -> some View {
        ZStack {
            EarShape(mirrored: mirrored).fill(fur.fur).frame(width: 44, height: 50)
            EarShape(mirrored: mirrored)
                .fill(Color(red: 1, green: 0.72, blue: 0.76))
                .frame(width: 24, height: 28)
                .offset(y: 9)
        }
        .rotationEffect(.degrees(mirrored ? 14 : -14))
    }

    private var ears: some View {
        Group {
            ear(mirrored: false).position(x: 90, y: 58)
            ear(mirrored: true).position(x: 170, y: 58)
        }
    }

    @ViewBuilder private var stripes: some View {
        if let c = fur.stripe {
            Group {
                Capsule().fill(c).frame(width: 7, height: 22).rotationEffect(.degrees(-18)).position(x: 112, y: 58)
                Capsule().fill(c).frame(width: 7, height: 26).position(x: 130, y: 54)
                Capsule().fill(c).frame(width: 7, height: 22).rotationEffect(.degrees(18)).position(x: 148, y: 58)
            }
        }
    }

    private var face: some View {
        Group {
            Ellipse().fill(fur.belly).frame(width: 60, height: 38).position(x: 130, y: 120)
            if state.mood == .happy || state.eating {
                Circle().fill(Color(red: 1, green: 0.6, blue: 0.65).opacity(0.45)).frame(width: 16).position(x: 94, y: 112)
                Circle().fill(Color(red: 1, green: 0.6, blue: 0.65).opacity(0.45)).frame(width: 16).position(x: 166, y: 112)
            }
            EyeView(mood: state.mood, blinking: state.blinking, color: eyeColor, lid: fur.fur).position(x: 108, y: 96)
            EyeView(mood: state.mood, blinking: state.blinking, color: eyeColor, lid: fur.fur).position(x: 152, y: 96)
            NoseShape().fill(Color(red: 0.95, green: 0.55, blue: 0.6)).frame(width: 12, height: 8).position(x: 130, y: 112)
            mouth
            WhiskerShape().stroke(fur.outline, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }

    @ViewBuilder private var mouth: some View {
        if state.eating || state.mood == .excited {
            Ellipse().fill(Color(red: 0.55, green: 0.2, blue: 0.25)).frame(width: 8, height: 9).position(x: 130, y: 124)
        } else {
            MouthShape(sad: state.mood == .grumpy)
                .stroke(fur.outline, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: 20, height: 10)
                .position(x: 130, y: 122)
        }
    }

    private var laptop: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(settings.keyboard.base).frame(width: 184, height: 34)
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<(14 - row), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1.5).fill(settings.keyboard.keys).frame(width: 8, height: 6)
                        }
                    }
                }
            }
        }
        .position(x: 130, y: 208)
    }

    @ViewBuilder private var heldImage: some View {
        if let img = state.heldImage {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 72)
                .padding(3)
                .background(Color.white)
                .cornerRadius(3)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .rotationEffect(.degrees(-3))
                .position(x: 130, y: 164)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
    }

    @ViewBuilder private var food: some View {
        if state.eating {
            Text("🐟").font(.system(size: 26)).position(x: 130, y: 142).transition(.scale.combined(with: .opacity))
        }
    }

    private var hearts: some View {
        ForEach(state.hearts) { heart in
            Text("❤️")
                .font(.system(size: 16))
                .position(x: heart.x, y: 64)
                .offset(y: heart.risen ? -58 : 0)
                .opacity(heart.risen ? 0 : 1)
        }
    }

    @ViewBuilder private var zzz: some View {
        if state.mood == .sleepy { ZzzView() }
    }

    @ViewBuilder private var bubble: some View {
        if let text = state.bubble {
            BubbleView(text: text)
                .position(x: 165, y: 22)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
    }
}

// MARK: - Лапки

struct PawView: View {
    let fur: FurStyle
    let down: Bool
    let holding: Bool
    let side: Paw

    private var x: CGFloat {
        if holding { return side == .left ? 76 : 184 }
        return side == .left ? 86 : 174
    }

    private var y: CGFloat {
        if holding { return down ? 171 : 168 }
        return down ? 196 : 184
    }

    private var rotation: Double {
        if holding { return side == .left ? -25 : 25 }
        if down { return side == .left ? -6 : 6 }
        return 0
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13).fill(fur.belly).frame(width: 46, height: 30)
            RoundedRectangle(cornerRadius: 13).stroke(fur.outline.opacity(0.35), lineWidth: 1).frame(width: 46, height: 30)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(fur.outline.opacity(0.25)).frame(width: 2, height: 9)
                }
            }
            .offset(y: -8)
        }
        .rotationEffect(.degrees(rotation))
        .position(x: x, y: y)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: holding)
    }
}

// MARK: - Глаза

struct EyeView: View {
    let mood: Mood
    let blinking: Bool
    let color: Color
    let lid: Color

    var body: some View {
        Group {
            if blinking || mood == .sleepy {
                Capsule().fill(color).frame(width: 16, height: 3)
            } else if mood == .happy {
                HappyEyeShape()
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 16, height: 9)
            } else if mood == .grumpy {
                ZStack {
                    Ellipse().fill(color).frame(width: 14, height: 18)
                    Rectangle().fill(lid).frame(width: 18, height: 9).offset(y: -7)
                }
            } else {
                ZStack {
                    Ellipse().fill(color).frame(width: 14, height: mood == .excited ? 21 : 18)
                    Circle().fill(.white).frame(width: 5).offset(x: 3, y: -4)
                }
            }
        }
    }
}

// MARK: - Фигуры

struct TailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 190, y: 185))
        p.addCurve(to: CGPoint(x: 240, y: 118),
                   control1: CGPoint(x: 238, y: 192),
                   control2: CGPoint(x: 252, y: 150))
        return p
    }
}

struct EarShape: Shape {
    let mirrored: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tipX = mirrored ? rect.minX + rect.width * 0.65 : rect.minX + rect.width * 0.35
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: tipX, y: rect.minY),
                       control: CGPoint(x: mirrored ? rect.minX + rect.width * 0.2 : rect.minX + rect.width * 0.05, y: rect.minY + rect.height * 0.3))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                       control: CGPoint(x: mirrored ? rect.maxX - rect.width * 0.05 : rect.maxX - rect.width * 0.2, y: rect.minY + rect.height * 0.3))
        p.closeSubpath()
        return p
    }
}

struct NoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}

struct MouthShape: Shape {
    let sad: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if sad {
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - 2))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY + 2), control: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.maxY))
        }
        return p
    }
}

struct HappyEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height))
        return p
    }
}

struct WhiskerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let lines: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 100, y: 112), CGPoint(x: 70, y: 106)),
            (CGPoint(x: 100, y: 117), CGPoint(x: 66, y: 117)),
            (CGPoint(x: 100, y: 122), CGPoint(x: 70, y: 128)),
            (CGPoint(x: 160, y: 112), CGPoint(x: 190, y: 106)),
            (CGPoint(x: 160, y: 117), CGPoint(x: 194, y: 117)),
            (CGPoint(x: 160, y: 122), CGPoint(x: 190, y: 128)),
        ]
        for (a, b) in lines {
            p.move(to: a)
            p.addLine(to: b)
        }
        return p
    }
}

struct GlassesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.height / 2
        let left = CGRect(x: rect.minX + 4, y: rect.minY, width: r * 2, height: r * 2)
        let right = CGRect(x: rect.maxX - 4 - r * 2, y: rect.minY, width: r * 2, height: r * 2)
        p.addEllipse(in: left)
        p.addEllipse(in: right)
        p.move(to: CGPoint(x: left.maxX, y: rect.midY - 2))
        p.addQuadCurve(to: CGPoint(x: right.minX, y: rect.midY - 2), control: CGPoint(x: rect.midX, y: rect.midY - 8))
        p.move(to: CGPoint(x: left.minX, y: rect.midY - 2))
        p.addLine(to: CGPoint(x: rect.minX - 6, y: rect.midY - 6))
        p.move(to: CGPoint(x: right.maxX, y: rect.midY - 2))
        p.addLine(to: CGPoint(x: rect.maxX + 6, y: rect.midY - 6))
        return p
    }
}

struct BowView: View {
    private let color = Color(red: 0.9, green: 0.3, blue: 0.4)
    var body: some View {
        ZStack {
            Ellipse().fill(color).frame(width: 18, height: 12).rotationEffect(.degrees(-15)).offset(x: -10)
            Ellipse().fill(color).frame(width: 18, height: 12).rotationEffect(.degrees(15)).offset(x: 10)
            Circle().fill(color.opacity(0.8)).frame(width: 8)
        }
    }
}

struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Мелкие вью

struct BubbleView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(.black.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            )
            .overlay(alignment: .bottomLeading) {
                BubbleTail().fill(Color.white).frame(width: 12, height: 8).offset(x: 14, y: 7)
            }
            .fixedSize()
    }
}

struct ZzzView: View {
    @State private var up = false
    var body: some View {
        Text("z z Z")
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(.secondary)
            .position(x: 196, y: 42)
            .offset(y: up ? -10 : 0)
            .opacity(up ? 0.4 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { up = true }
            }
    }
}
