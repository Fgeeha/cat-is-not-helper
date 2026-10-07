import SwiftUI
import Combine

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let isTrusted: () -> Bool
    let requestAccess: () -> Void

    @State private var trusted = false
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Котик") {
                Picker("Окрас", selection: $settings.fur) {
                    ForEach(FurStyle.allCases) { Text($0.title).tag($0) }
                }
                HStack {
                    Text("Размер")
                    Slider(value: $settings.scale, in: 0.6...1.8)
                    Text("\(Int(settings.scale * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                HStack {
                    Text("Непрозрачность")
                    Slider(value: $settings.opacity, in: 0.3...1.0)
                    Text("\(Int(settings.opacity * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Toggle("Фразы в пузырьках", isOn: $settings.bubbles)
            }

            Section("Окно") {
                Toggle("Поверх всех окон", isOn: $settings.alwaysOnTop)
                Toggle("На всех рабочих столах", isOn: $settings.allSpaces)
                Toggle("Показывать котика", isOn: $settings.catVisible)
            }

            Section("Доступ к клавиатуре") {
                HStack(spacing: 8) {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(trusted ? .green : .orange)
                    Text(trusted ? "Доступ есть, котик видит нажатия" : "Нужно разрешение «Универсальный доступ»")
                }
                if !trusted {
                    Button("Открыть системные настройки") { requestAccess() }
                }
                Text("Котик считает только количество нажатий. Какие именно клавиши ты нажимаешь — не записывается и никуда не отправляется.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Управление") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Клик по котику — погладить")
                    Text("Двойной клик — открыть то, что он держит")
                    Text("Перетаскивание — передвинуть")
                    Text("Правый клик — меню")
                    Text("Перетащи картинку на котика — он возьмёт её в лапки")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 560)
        .onAppear { trusted = isTrusted() }
        .onReceive(poll) { _ in trusted = isTrusted() }
    }
}
