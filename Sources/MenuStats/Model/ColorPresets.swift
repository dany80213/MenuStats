import AppKit
import Foundation

/// A ready-made color scheme for all of MenuStats: the dropdown's palette (every role of every tab), the network and
/// disk graphs, and the menu bar icons. Applying one sets those colors; each stays editable on its module's page.
struct ColorPreset: Identifiable, Equatable {
    var id: String
    var name: String
    var mood: String
    /// Five colors, one per palette role (0…4).
    var palette: [String]

    /// The palette the built-in colors come from: choosing it restores every default.
    static let standardID = "menustats"

    static let all: [ColorPreset] = [
        ColorPreset(id: standardID, name: "MenuStats", mood: "I colori di serie",
                    palette: ["#2A78D6", "#EB6834", "#1BAF7A", "#EDA100", "#E87BA4"]),
        ColorPreset(id: "ocean", name: "Oceano", mood: "Blu e verdi acqua",
                    palette: ["#1F6FEB", "#00A3BF", "#2FBF9F", "#7A8CFF", "#5AC8FA"]),
        ColorPreset(id: "sunset", name: "Tramonto", mood: "Caldi, arancio e rosa",
                    palette: ["#FF6B35", "#F7B32B", "#E63946", "#C2185B", "#FF9F80"]),
        ColorPreset(id: "forest", name: "Foresta", mood: "Verdi e terra",
                    palette: ["#2D6A4F", "#52B788", "#A3B18A", "#DDA15E", "#95D5B2"]),
        ColorPreset(id: "pastel", name: "Pastello", mood: "Tenui e morbidi",
                    palette: ["#8EC5FC", "#FFB4A2", "#B5E48C", "#FFD670", "#E0B1FF"]),
        ColorPreset(id: "neon", name: "Neon", mood: "Accesi, per lo scuro",
                    palette: ["#00E5FF", "#FF2BD6", "#39FF14", "#FFE600", "#8A5CFF"]),
        ColorPreset(id: "lavender", name: "Lavanda", mood: "Viola e lilla",
                    palette: ["#7B61FF", "#B794F4", "#E879F9", "#60A5FA", "#F472B6"]),
        ColorPreset(id: "citrus", name: "Agrumi", mood: "Gialli e verdi vivaci",
                    palette: ["#F59E0B", "#84CC16", "#F97316", "#EAB308", "#22C55E"]),
        ColorPreset(id: "earth", name: "Terra", mood: "Marroni e oliva",
                    palette: ["#A0522D", "#D2A679", "#6B8E23", "#CD853F", "#8B6F47"]),
        ColorPreset(id: "ice", name: "Ghiaccio", mood: "Azzurri freddi",
                    palette: ["#38BDF8", "#94A3B8", "#22D3EE", "#818CF8", "#CBD5E1"]),
        ColorPreset(id: "cherry", name: "Ciliegia", mood: "Rossi e rosa",
                    palette: ["#E11D48", "#FB7185", "#BE123C", "#F43F5E", "#FDA4AF"]),
        ColorPreset(id: "graphite", name: "Grafite", mood: "Grigi, senza colore",
                    palette: ["#6E6E73", "#A1A1A6", "#48484A", "#C7C7CC", "#8E8E93"]),
        ColorPreset(id: "contrast", name: "Alto contrasto", mood: "Colori netti e scuri",
                    palette: ["#0040DD", "#D70015", "#007D1B", "#B25000", "#8944AB"]),
        ColorPreset(id: "rainbow", name: "Arcobaleno", mood: "Tutti i colori di macOS",
                    palette: ["#FF3B30", "#FF9500", "#34C759", "#007AFF", "#AF52DE"]),
    ]

    /// The palette color a role of a tab takes. Disk reads and writes use the 3rd and 5th colors, so they differ
    /// from network download and upload.
    func hex(tab: DashboardTab, role: Int) -> String {
        if tab == .disk, role < 2 { return palette[[2, 4][role]] }
        return palette[role % palette.count]
    }

    /// The menu bar icon colors: modules side by side get different colors.
    func moduleHex(_ module: ModuleID) -> String {
        let order: [ModuleID: Int] = [.cpu: 0, .memory: 1, .disk: 2, .network: 3, .sensors: 4, .fans: 1, .battery: 2,
                                      .weather: 0, .date: 3, .awake: 4]
        return palette[order[module] ?? 0]
    }
}

extension Settings {
    /// Sets every color from a preset; the MenuStats preset puts back the built-in ones.
    func apply(_ preset: ColorPreset) {
        if preset.id == ColorPreset.standardID {
            panelColors = [:]
            graphSeriesColors = GraphSeries.defaultColors
            moduleColors = Settings.defaultColors
        } else {
            var panel: [DashboardTab: [Int: String]] = [:]
            var graphs = graphSeriesColors
            for tab in DashboardTab.allCases {
                for role in tab.colorRoles.map(\.index) {
                    let hex = preset.hex(tab: tab, role: role)
                    if let series = tab.graphSeries(role: role) { graphs[series] = hex } else { panel[tab, default: [:]][role] = hex }
                }
            }
            panelColors = panel
            graphSeriesColors = graphs
            moduleColors = Dictionary(uniqueKeysWithValues: ModuleID.allCases.map { ($0, preset.moduleHex($0)) })
        }
        colorPreset = preset.id
        colorPresetFingerprint = colorFingerprint
    }

    /// All the colors a preset sets, in one string: when it no longer matches, the user has edited some color.
    var colorFingerprint: String {
        let panel = panelColors.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue):" + $0.value.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",") }
        let graphs = graphSeriesColors.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue)=\($0.value)" }
        let modules = moduleColors.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue)=\($0.value)" }
        return (panel + graphs + modules).joined(separator: "|")
    }

    /// The preset in use, and whether some color was changed after choosing it.
    var currentPreset: (preset: ColorPreset, edited: Bool)? {
        guard let preset = ColorPreset.all.first(where: { $0.id == colorPreset }) else { return nil }
        return (preset, colorPresetFingerprint != colorFingerprint)
    }
}
