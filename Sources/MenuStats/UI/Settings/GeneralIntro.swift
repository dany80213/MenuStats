import AppKit
import SwiftUI

/// The top of Settings ▸ Generali: what MenuStats is and what it is showing now.
struct GeneralHero: View {
    @ObservedObject var settings: Settings

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "sviluppo"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable().frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("MenuStats").font(.system(size: 24, weight: .bold))
                        Text("versione \(version)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                    Text("Tutto il tuo Mac nella barra dei menu: CPU, memoria, disco, rete, temperature, batteria, meteo, calendario e Sveglio. Scegli qui l'aspetto generale e i colori; ogni modulo ha poi la sua pagina a sinistra.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                chip("menubar.rectangle", "\(settings.visibleModules.count) moduli nella barra")
                chip("arrow.clockwise", "ogni \(Int(settings.refreshInterval)) s")
                chip("paintpalette", settings.currentPreset.map { $0.edited ? "\($0.preset.name), modificato" : $0.preset.name } ?? "Colori di serie")
                chip(settings.panelBackground == .solid ? "rectangle.fill" : "rectangle.dashed",
                     settings.panelBackground == .solid ? "Tendina piena" : "Tendina trasparente")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: heroColors.map { $0.opacity(0.16) }, startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .padding(.bottom, 22)
        .animation(.easeInOut(duration: 0.35), value: settings.colorPreset)
    }

    /// The hero takes the colors of the chosen preset.
    private var heroColors: [Color] {
        let preset = settings.currentPreset?.preset ?? ColorPreset.all[0]
        return [preset.palette[0], preset.palette[4], preset.palette[2]].compactMap { NSColor(hex: $0) }.map(Color.init(nsColor:))
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

/// Settings ▸ Generali ▸ Colori: every preset as a card; hovering one previews it above, clicking applies it.
struct ColorPresetPicker: View {
    @ObservedObject var settings: Settings
    /// Builds the menu bar preview with the given icon colors.
    var menubar: (([ModuleID: NSColor]) -> NSImage)?
    @State private var hovered: ColorPreset?

    private var shown: ColorPreset { hovered ?? settings.currentPreset?.preset ?? ColorPreset.all[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preview
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(ColorPreset.all) { preset in
                    PresetCard(preset: preset, selected: settings.colorPreset == preset.id || (settings.colorPreset == nil && preset.id == ColorPreset.standardID),
                               hovered: hovered == preset)
                        .onHover { inside in
                            withAnimation(.easeOut(duration: 0.15)) { hovered = inside ? preset : (hovered == preset ? nil : hovered) }
                        }
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { settings.apply(preset) }
                        }
                        .help("Applica «\(preset.name)» a tutti i colori")
                }
            }
            HStack(spacing: 12) {
                Toggle("Colora le icone nella barra dei menu", isOn: $settings.colorIcons)
                Spacer()
                if let current = settings.currentPreset, current.edited {
                    Button("Rimetti «\(current.preset.name)»") { withAnimation { settings.apply(current.preset) } }
                        .buttonStyle(.link)
                }
            }
        }
    }

    /// What the hovered (or chosen) preset looks like: the menu bar and a piece of the dropdown.
    private var preview: some View {
        let colors = shown.palette.compactMap(NSColor.init(hex:)).map(Color.init(nsColor:))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(hovered == nil ? "In uso: \(shown.name)" : "Anteprima: \(shown.name)")
                    .font(.system(size: 12, weight: .semibold))
                Text(shown.mood).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if hovered != nil { Text("Clic per applicare").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            if let menubar {
                MenubarPreview(image: menubar(Dictionary(uniqueKeysWithValues: ModuleID.allCases.compactMap { module in
                    NSColor(hex: shown.moduleHex(module)).map { (module, $0) }
                })), vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
            MiniDropdown(colors: colors)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
        .animation(.easeInOut(duration: 0.25), value: shown)
    }
}

/// One preset: its five colors as stripes, its name and mood.
private struct PresetCard: View {
    var preset: ColorPreset
    var selected: Bool
    var hovered: Bool

    var body: some View {
        let colors = preset.palette.compactMap(NSColor.init(hex:)).map(Color.init(nsColor:))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(colors.indices, id: \.self) { colors[$0] }
            }
            .frame(height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.name).font(.system(size: 12, weight: .semibold))
                    Text(preset.mood).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(colors.first ?? .accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(hovered ? 0.08 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(selected ? (colors.first ?? .accentColor) : Color.primary.opacity(hovered ? 0.2 : 0.08), lineWidth: selected ? 2 : 1))
        .scaleEffect(hovered ? 1.03 : 1)
        .contentShape(Rectangle())
    }
}

/// A small sketch of the dropdown in the preset's colors: CPU user/system lines, the memory bar, network bars.
private struct MiniDropdown: View {
    var colors: [Color]

    private static let user: [Double] = [0.30, 0.42, 0.35, 0.55, 0.48, 0.62, 0.40, 0.52, 0.66, 0.50, 0.58, 0.45]
    private static let system: [Double] = [0.12, 0.18, 0.15, 0.22, 0.20, 0.26, 0.18, 0.24, 0.30, 0.22, 0.25, 0.19]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            card("CPU") {
                GeometryReader { geometry in
                    ZStack {
                        line(Self.user, geometry.size).stroke(colors[0], style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        line(Self.system, geometry.size).stroke(colors[1], style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(height: 38)
                legend([("Utente", colors[0]), ("Sistema", colors[1])])
            }
            card("Memoria") {
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(Array([0.38, 0.17, 0.12, 0.18].enumerated()), id: \.offset) { index, share in
                            RoundedRectangle(cornerRadius: 2).fill(colors[index]).frame(width: geometry.size.width * share)
                        }
                        RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.15))
                    }
                }
                .frame(height: 10)
                legend([("App", colors[0]), ("Wired", colors[1]), ("Compressa", colors[2]), ("Cache", colors[3])])
            }
            card("Rete") {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<9, id: \.self) { index in
                        VStack(spacing: 1) {
                            RoundedRectangle(cornerRadius: 1).fill(colors[1]).frame(width: 6, height: CGFloat([6, 10, 4, 14, 8, 12, 5, 9, 7][index]))
                            RoundedRectangle(cornerRadius: 1).fill(colors[0]).frame(width: 6, height: CGFloat([12, 18, 9, 22, 15, 20, 11, 17, 13][index]))
                        }
                    }
                }
                .frame(height: 38, alignment: .bottom)
                legend([("Download", colors[0]), ("Upload", colors[1])])
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func line(_ values: [Double], _ size: CGSize) -> Path {
        Path { path in
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1), y: size.height * (1 - value))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }

    private func legend(_ items: [(String, Color)]) -> some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 3) {
                    Circle().fill(item.1).frame(width: 6, height: 6)
                    Text(item.0).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}
