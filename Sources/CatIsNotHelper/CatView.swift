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
    /// Закрытые глаза — тёмная линия; на чёрной шерсти цветом глаз, иначе не видно.
    private var lashColor: Color { fur == .black ? eyeColor : eyeColor.mixed(with: .black, by: 0.6) }

    var body: some View {
        ZStack {
            // Тело и всё, что можно отразить
            ZStack {
                torso
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

    /// Тень, хвост, тело, уши, голова и полоски — всё, что под мордочкой.
    private var torso: some View {
        ZStack {
            Ellipse().fill(Color.black.opacity(0.28)).frame(width: 192, height: 10).blur(radius: 3).position(x: 130, y: 223)
            tail
            Ellipse()
                .fill(furGradient(endRadius: 104))
                .overlay(Ellipse().stroke(fur.shade, lineWidth: 1.5))
                .frame(width: 150, height: 105)
                .position(x: 130, y: 166)
            if let c = fur.stripe {
                BodyStripesShape().stroke(c, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            Ellipse()
                .fill(RadialGradient(colors: [fur.belly.mixed(with: .white, by: 0.4), fur.belly],
                                     center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 50))
                .frame(width: 86, height: 64)
                .position(x: 130, y: 180)
            ears
            // Голова в координатах всего холста, поэтому центр градиента пересчитан из её рамки 69…191 × 42…152.
            HeadShape()
                .fill(RadialGradient(gradient: furStops, center: UnitPoint(x: 115 / 260, y: 75 / 230), startRadius: 0, endRadius: 94))
                .overlay(HeadShape().stroke(fur.shade, lineWidth: 1.5))
            stripes
        }
    }

    /// Те же точки перехода, что у SVG-градиента шерсти в cat-renderer.js.
    private var furStops: Gradient {
        Gradient(stops: [.init(color: fur.light, location: 0), .init(color: fur.fur, location: 0.55), .init(color: fur.shade, location: 1)])
    }

    private func furGradient(endRadius: CGFloat) -> RadialGradient {
        RadialGradient(gradient: furStops, center: UnitPoint(x: 0.38, y: 0.3), startRadius: 0, endRadius: endRadius)
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
        return ZStack {
            TailShape().stroke(fur.fur, style: StrokeStyle(lineWidth: 17, lineCap: .round))
            if let c = fur.stripe {
                TailShape().stroke(c, style: StrokeStyle(lineWidth: 17, lineCap: .butt, dash: [6, 13], dashPhase: 5))
            }
        }
            .rotationEffect(.degrees(happy ? 12 : 0), anchor: UnitPoint(x: 190 / 260, y: 185 / 230))
            .animation(happy ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true)
                             : .easeInOut(duration: 0.4), value: happy)
    }

    private func ear(mirrored: Bool) -> some View {
        ZStack {
            EarShape(mirrored: mirrored)
                .fill(furGradient(endRadius: 40))
                .overlay(EarShape(mirrored: mirrored).stroke(fur.shade, lineWidth: 1.5))
                .frame(width: 44, height: 50)
            EarShape(mirrored: mirrored)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.69), Color(red: 1, green: 0.83, blue: 0.85)],
                                     startPoint: .top, endPoint: .bottom))
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
                CheekStripesShape().stroke(c, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            }
        }
    }

    private var face: some View {
        Group {
            let muzzle = fur.belly.mixed(with: .white, by: 0.3)
            Ellipse().fill(muzzle).frame(width: 34, height: 28).position(x: 119, y: 121)
            Ellipse().fill(muzzle).frame(width: 34, height: 28).position(x: 141, y: 121)
            Ellipse().fill(muzzle).frame(width: 20, height: 16).position(x: 130, y: 128)
            let blush = Color(red: 1, green: 0.5, blue: 0.58)
            ForEach([92.0, 168.0], id: \.self) { x in
                Ellipse()
                    .fill(RadialGradient(colors: [blush.opacity(0.8), blush.opacity(0)], center: .center, startRadius: 0, endRadius: 12))
                    .frame(width: 24, height: 16)
                    .position(x: x, y: 116)
            }
            .opacity(state.mood == .happy || state.eating ? 0.9 : 0.35)
            EyeView(mood: state.mood, blinking: state.blinking, color: eyeColor, lid: fur.fur, lash: lashColor, right: false).position(x: 108, y: 96)
            EyeView(mood: state.mood, blinking: state.blinking, color: eyeColor, lid: fur.fur, lash: lashColor, right: true).position(x: 152, y: 96)
            NoseShape().fill(Color(red: 0.95, green: 0.55, blue: 0.6))
            Ellipse().fill(Color.white.opacity(0.6)).frame(width: 4.8, height: 2.6).position(x: 128, y: 109)
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
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [settings.keyboard.base.mixed(with: .white, by: 0.12),
                                              settings.keyboard.base.mixed(with: .black, by: 0.15)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 184, height: 34)
            Capsule().fill(Color.white.opacity(0.25)).frame(width: 172, height: 1.5).offset(y: -15.5)
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
            if state.heldStack.count > 1 {
                ZStack {
                    Circle().fill(Color(red: 0.93, green: 0.55, blue: 0.2))
                    Circle().stroke(Color.white, lineWidth: 2)
                    Text(state.heldStack.count > 99 ? "99+" : "\(state.heldStack.count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(width: 18, height: 18)
                .position(x: 182, y: 128)
                .transition(.scale.combined(with: .opacity))
            }
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
    let lash: Color
    let right: Bool

    var body: some View {
        Group {
            if blinking || mood == .sleepy {
                Capsule().fill(lash).frame(width: 16, height: 3)
            } else if mood == .happy {
                HappyEyeShape()
                    .stroke(lash, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 16, height: 9)
            } else {
                ZStack {
                    openEye
                    if mood == .grumpy {
                        // Хмурое веко наискосок к переносице.
                        ZStack {
                            LidShape().fill(lid)
                            LidLineShape().stroke(lash, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        }
                        .frame(width: 24, height: 24)
                        .scaleEffect(x: right ? -1 : 1, y: 1)
                    }
                }
            }
        }
    }

    private var openEye: some View {
        let excited = mood == .excited
        return ZStack {
            Ellipse()
                .fill(LinearGradient(stops: [.init(color: color.mixed(with: .black, by: 0.35), location: 0),
                                             .init(color: color, location: 0.6),
                                             .init(color: color.mixed(with: .white, by: 0.35), location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Ellipse().stroke(Color.black.opacity(0.35), lineWidth: 1))
                .frame(width: 17, height: excited ? 22 : 20)
            Ellipse()
                .fill(Color(red: 0.1, green: 0.08, blue: 0.08))
                .frame(width: excited ? 13 : 9, height: excited ? 17 : 15)
                .offset(y: 0.5)
            Circle().fill(.white).frame(width: 5.6).offset(x: 3, y: -4.5)
            Circle().fill(Color.white.opacity(0.8)).frame(width: 2.6).offset(x: -3, y: 4.5)
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

/// Голова в координатах холста 260×230: круг, расширенный щеками книзу.
struct HeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 130, y: 42))
        p.addCurve(to: CGPoint(x: 186, y: 94), control1: CGPoint(x: 163, y: 42), control2: CGPoint(x: 186, y: 64))
        p.addCurve(to: CGPoint(x: 191, y: 114), control1: CGPoint(x: 186, y: 100), control2: CGPoint(x: 192, y: 108))
        p.addCurve(to: CGPoint(x: 130, y: 152), control1: CGPoint(x: 189, y: 138), control2: CGPoint(x: 162, y: 152))
        p.addCurve(to: CGPoint(x: 69, y: 114), control1: CGPoint(x: 98, y: 152), control2: CGPoint(x: 71, y: 138))
        p.addCurve(to: CGPoint(x: 74, y: 94), control1: CGPoint(x: 68, y: 108), control2: CGPoint(x: 74, y: 100))
        p.addCurve(to: CGPoint(x: 130, y: 42), control1: CGPoint(x: 74, y: 64), control2: CGPoint(x: 97, y: 42))
        p.closeSubpath()
        return p
    }
}

/// Полоски на боках тела (координаты холста).
struct BodyStripesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (a, c, b) in [((60.0, 152.0), (70.0, 150.0), (78.0, 158.0)), ((58.0, 170.0), (69.0, 168.0), (78.0, 176.0))] {
            for mirror in [false, true] {
                let x = { (v: Double) in mirror ? 260 - v : v }
                p.move(to: CGPoint(x: x(a.0), y: a.1))
                p.addQuadCurve(to: CGPoint(x: x(b.0), y: b.1), control: CGPoint(x: x(c.0), y: c.1))
            }
        }
        return p
    }
}

/// Полоски на щеках (координаты холста).
struct CheekStripesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (a, b) in [((71.0, 104.0), (84.0, 106.0)), ((72.0, 113.0), (83.0, 113.0))] {
            p.move(to: CGPoint(x: a.0, y: a.1)); p.addLine(to: CGPoint(x: b.0, y: b.1))
            p.move(to: CGPoint(x: 260 - a.0, y: a.1)); p.addLine(to: CGPoint(x: 260 - b.0, y: b.1))
        }
        return p
    }
}

/// Хмурое веко в рамке 24×24 с центром глаза посередине (как SVG-путь M-10,-6 L10,-2 L10,-12 Q0,-15 -10,-12 Z):
/// у переносицы (+x для левого глаза) опущено ниже — сердитый, а не грустный взгляд.
struct LidShape: Shape {
    func path(in rect: CGRect) -> Path {
        let o = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.move(to: CGPoint(x: o.x - 10, y: o.y - 6))
        p.addLine(to: CGPoint(x: o.x + 10, y: o.y - 2))
        p.addLine(to: CGPoint(x: o.x + 10, y: o.y - 12))
        p.addQuadCurve(to: CGPoint(x: o.x - 10, y: o.y - 12), control: CGPoint(x: o.x, y: o.y - 15))
        p.closeSubpath()
        return p
    }
}

struct LidLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX - 10, y: rect.midY - 6))
        p.addLine(to: CGPoint(x: rect.midX + 10, y: rect.midY - 2))
        return p
    }
}

extension Color {
    /// Смешать с другим цветом: t=0 — исходный, t=1 — other.
    func mixed(with other: Color, by t: Double) -> Color {
        guard let a = NSColor(self).usingColorSpace(.sRGB), let b = NSColor(other).usingColorSpace(.sRGB) else { return self }
        let f = { (x: CGFloat, y: CGFloat) in Double(x + (y - x) * t) }
        return Color(.sRGB,
                     red: f(a.redComponent, b.redComponent),
                     green: f(a.greenComponent, b.greenComponent),
                     blue: f(a.blueComponent, b.blueComponent),
                     opacity: f(a.alphaComponent, b.alphaComponent))
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

/// Нос в координатах холста, как SVG-путь в cat-renderer.js.
struct NoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 123.5, y: 108))
        p.addQuadCurve(to: CGPoint(x: 136.5, y: 108), control: CGPoint(x: 130, y: 105.5))
        p.addQuadCurve(to: CGPoint(x: 130, y: 117), control: CGPoint(x: 136, y: 115))
        p.addQuadCurve(to: CGPoint(x: 123.5, y: 108), control: CGPoint(x: 124, y: 115))
        p.closeSubpath()
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
