import SwiftUI
import PicoKit

/// The card: title bar with − and ×, a 1-point divider, the editor and a
/// 1-point outline in the ink color, as painted by paint_note() on Windows.
struct NoteView: View {
    @Bindable var note: Note
    let onToggle: () -> Void
    let onClose: () -> Void

    private var card: Color { Color(note.palette.card(note.color)) }
    private var ink: Color { Color(note.palette.ink(note.color)) }
    private var bar: Color { Color(note.palette.bar(note.color)) }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Rectangle().fill(ink).frame(height: 1)
            if !note.collapsed {
                NoteTextView(note: note, ink: NSColor(ink))
                    .padding(EdgeInsets(top: 6, leading: 10, bottom: 10, trailing: 10))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(card)
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 1))
    }

    private var titleBar: some View {
        HStack(spacing: 0) {
            Text(note.title ?? "")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WindowDragArea())
            BarButton(symbol: note.collapsed ? "square" : "minus", ink: ink, hover: card, action: onToggle)
            BarButton(symbol: "xmark", ink: ink, hover: Color(red: 235 / 255, green: 161 / 255, blue: 151 / 255),
                      action: onClose)
        }
        .frame(height: NoteWindows.barHeight - 1)
        .background(bar)
    }
}

private struct BarButton: View {
    let symbol: String
    let ink: Color
    let hover: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ink)
                .frame(width: NoteWindows.barHeight, height: NoteWindows.barHeight - 1)
                .background(hovering ? hover : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension Color {
    init(_ color: RGBColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}
