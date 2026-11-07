import Observation
import PicoKit

/// One sticky note. Saving arrives in a later phase; the ID and colors already
/// follow the Windows rules through PicoKit.
@Observable
final class Note {
    let id: String
    let palette: Palette
    let color: Int
    var title: String?
    var body = ""
    var collapsed = false

    init(id: String, palette: Palette, color: Int) {
        self.id = id
        self.palette = palette
        self.color = color
    }
}
