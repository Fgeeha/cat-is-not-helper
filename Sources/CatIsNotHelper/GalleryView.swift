import SwiftUI

struct GalleryView: View {
    @ObservedObject var shots: ScreenshotManager
    @ObservedObject var state: CatState
    let onCapture: () -> Void
    let onGive: (URL) -> Void
    let onTakeBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { onCapture() } label: { Label("Сделать скриншот", systemImage: "camera") }
                    .keyboardShortcut("4", modifiers: [.command, .shift])
                Button { shots.openFolder() } label: { Label("Открыть папку", systemImage: "folder") }
                Spacer()
                Text("\(shots.items.count) шт.").foregroundColor(.secondary)
            }
            .padding()

            Divider()

            if shots.items.isEmpty {
                VStack(spacing: 10) {
                    Text("🐾").font(.system(size: 48))
                    Text("Пока пусто").font(.headline)
                    Text("Нажми «Сделать скриншот» или перетащи картинку прямо на котика — он подержит.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                        ForEach(shots.items, id: \.self) { url in
                            GalleryCell(
                                url: url,
                                isHeld: state.heldURL == url,
                                give: { onGive(url) },
                                takeBack: { onTakeBack() },
                                open: { shots.open(url) },
                                reveal: { shots.reveal(url) },
                                delete: {
                                    if state.heldURL == url { state.putAway() }
                                    shots.delete(url)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 480)
        .onAppear { shots.reload() }
    }
}

struct GalleryCell: View {
    let url: URL
    let isHeld: Bool
    let give: () -> Void
    let takeBack: () -> Void
    let open: () -> Void
    let reveal: () -> Void
    let delete: () -> Void

    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color.secondary.opacity(0.08)
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 124)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isHeld ? Color.orange : Color.clear, lineWidth: 3))
            .overlay(alignment: .topTrailing) {
                if isHeld {
                    Text("🐾 у котика")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange))
                        .foregroundColor(.white)
                        .padding(6)
                }
            }
            .onTapGesture(count: 2) { open() }

            Text(url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack {
                if isHeld {
                    Button("Забрать у котика") { takeBack() }.controlSize(.small)
                } else {
                    Button("🐾 Дать котику") { give() }.controlSize(.small)
                }
                Spacer()
                Menu {
                    Button("Открыть") { open() }
                    Button("Показать в Finder") { reveal() }
                    Divider()
                    Button("Удалить", role: .destructive) { delete() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .onAppear {
            guard image == nil else { return }
            let target = url
            DispatchQueue.global(qos: .utility).async {
                let loaded = ImageLoader.thumbnail(url: target, maxPixel: 400)
                DispatchQueue.main.async {
                    if url == target { image = loaded }
                }
            }
        }
    }
}
