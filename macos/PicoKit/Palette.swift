import PicoCore

/// An sRGB color with components from 0 to 1.
public struct RGBColor: Sendable, Equatable {
    public let red: Double, green: Double, blue: Double

    init(_ packed: UInt32) {
        red = Double((packed >> 16) & 0xff) / 255
        green = Double((packed >> 8) & 0xff) / 255
        blue = Double(packed & 0xff) / 255
    }
}

/// The three "New note palette" choices, colors from the shared core.
public enum Palette: Int, CaseIterable, Sendable {
    case pastel = 0, blackAndWhite = 1, yellowOnly = 2

    public static let colorCount = Int(PC_COLOR_COUNT)

    public var name: String {
        switch self {
        case .pastel: "Pastel"
        case .blackAndWhite: "Black and white"
        case .yellowOnly: "Yellow only"
        }
    }

    public func card(_ color: Int) -> RGBColor { RGBColor(pc_note_rgb(Int32(rawValue), Int32(color))) }
    public func ink(_ color: Int) -> RGBColor { RGBColor(pc_ink_rgb(Int32(rawValue), Int32(color))) }
    public func bar(_ color: Int) -> RGBColor { RGBColor(pc_bar_rgb(Int32(rawValue), Int32(color))) }
}
