import Foundation

struct Palette: Identifiable {
    let id: String
    let label: String
    let hex: String
    static let all = [
        Palette(id: "blue", label: "파랑", hex: "#0A84FF"),
        Palette(id: "lavender", label: "연보라", hex: "#B8A1FF"),
        Palette(id: "pink", label: "핑크", hex: "#FF4FA3"),
        Palette(id: "red", label: "빨강", hex: "#FF453A"),
        Palette(id: "orange", label: "주황", hex: "#FF9F0A"),
        Palette(id: "yellow", label: "노랑", hex: "#FFCC00"),
        Palette(id: "green", label: "초록", hex: "#30D158")
    ]
}

struct TargetRow: Decodable, Identifiable {
    let id: String
    let label: String
    let available: Bool
    let color: String
    var detail: String
    var applyReady: Bool?
    var paletteColor: String {
        guard id == "chrome" else { return color }
        return Palette.all.first(where: { ChromeColor.matches(color, $0.hex) })?.hex ?? color
    }
}

struct ChromeProfile: Decodable, Identifiable {
    let id: String
    let label: String
    let color: String
    let detail: String
    let available: Bool
}

struct Reply: Decodable {
    var ok: Bool
    var message: String
    var rows: [TargetRow]?
    let chromeProfiles: [ChromeProfile]?
    let chromeProfileIDs: [String]?
    let chromeUIActions: [ChromeUIAction]?
    var chromeResults: [ChromeApplyResult]? = nil

    enum CodingKeys: String, CodingKey {
        case ok, message, rows, chromeProfiles, chromeProfileIDs, chromeUIActions
    }
}
