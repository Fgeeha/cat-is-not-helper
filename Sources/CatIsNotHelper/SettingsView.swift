import SwiftUI
import Combine

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var state: CatState
    let isTrusted: () -> Bool
    let requestAccess: () -> Void

    @State private var trusted = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var sizePreset: Binding<SizePreset?> {
        Binding(
            get: { SizePreset.closest(to: settings.scale) },
            set: { if let preset = $0 { settings.scale = preset.scale } }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            preview
            Divider()
            form
        }
        .frame(width: 760, height: 640)
        .onAppear { trusted = isTrusted() }
        .onReceive(poll) { _ in
            trusted = isTrusted()
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    // MARK: - Превью

    private var preview: some View {
        VStack(spacing: 12) {
            Text("Так он выглядит").font(.headline)
            CatView(state: state, settings: settings, fixedScale: 1)
                .frame(width: CatView.design.width, height: CatView.design.height)
            Text("Превью живое: котик тапает вместе с тобой и здесь.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Погладить") { state.pet() }
                Button("Покормить 🐟") { state.feed() }
            }
            .controlSize(.small)
            Spacer()
        }
        .padding(20)
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Форма

    private var form: some View {
        Form {
            Section("Внешность") {
                Picker("Окрас", selection: $settings.fur) {
                    ForEach(FurStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Глаза", selection: $settings.eyeColor) {
                    ForEach(EyeColorChoice.allCases) { Text($0.title).tag($0) }
                }
                Picker("Аксессуар", selection: $settings.accessory) {
                    ForEach(Accessory.allCases) { Text($0.title).tag($0) }
                }
                Picker("Клавиатура", selection: $settings.keyboard) {
                    ForEach(KeyboardStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Отразить (хвост слева)", isOn: $settings.mirrored)
            }

            Section("Размер") {
                Picker("Пресет", selection: sizePreset) {
                    ForEach(SizePreset.allCases) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Точно")
                    Slider(value: $settings.scale, in: AppSettings.scaleRange)
                    Text("\(Int(settings.scale * 100))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                HStack {
                    Text("Непрозрачность")
                    Slider(value: $settings.opacity, in: 0.3...1.0)
                    Text("\(Int(settings.opacity * 100))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Text("Размер на экране: \(Int(CatView.size(for: settings.scale).width))×\(Int(CatView.size(for: settings.scale).height)) pt")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Поведение") {
                Toggle("Фразы в пузырьках", isOn: $settings.bubbles)
                Toggle("Поверх всех окон", isOn: $settings.alwaysOnTop)
                Toggle("На всех рабочих столах", isOn: $settings.allSpaces)
                Toggle("Показывать котика", isOn: $settings.catVisible)
            }

            Section("Запуск") {
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            try LaunchAtLogin.set(enabled)
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if LaunchAtLogin.requiresApproval {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text("Автозапуск отключён в системе — разреши его в «Объектах входа».")
                        Spacer()
                        Button("Открыть") { LaunchAtLogin.openSystemSettings() }
                    }
                    .font(.caption)
                }
                if let launchError {
                    Text(launchError).font(.caption).foregroundColor(.red)
                }
            }

            Section("Доступ к клавиатуре") {
                HStack(spacing: 8) {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(trusted ? .green : .orange)
                    Text(trusted ? "Доступ есть, котик видит нажатия" : "Нужно разрешение «Универсальный доступ»")
                }
                if !trusted {
                    Button("Открыть системные настройки") { requestAccess() }
                    Text("Если CatIsNotHelper уже есть в списке с галочкой, а котик всё равно не видит клавиши — убери его из списка кнопкой «−» и добавь заново. Так бывает после пересборки приложения.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("Котик считает только количество нажатий. Какие именно клавиши ты нажимаешь — не записывается и никуда не отправляется.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Управление") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Клик по котику — погладить")
                    Text("Двойной клик — открыть то, что он держит")
                    Text("Потянуть за картинку в лапках — забрать её (в Finder, чат, куда угодно)")
                    Text("Потянуть за котика — передвинуть")
                    Text("Правый клик — меню")
                    Text("Перетащи картинку на котика — он возьмёт её в лапки")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
