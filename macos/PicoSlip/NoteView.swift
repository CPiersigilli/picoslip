import SwiftUI
import PicoKit

/// The note card in either style. Colors always come from the shared palettes.
struct NoteView: View {
    @Bindable var note: Note
    let onToggle: () -> Void
    let onClose: () -> Void
    let onStyleChange: () -> Void
    @AppStorage(NoteStyle.storageKey) private var style: NoteStyle = .mac
    @State private var hovering = false

    private var card: Color { Color(note.palette.card(note.color)) }
    private var ink: Color { Color(note.palette.ink(note.color)) }
    private var bar: Color { Color(note.palette.bar(note.color)) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        VStack(spacing: 0) {
            titleBar
            if style == .windows { Rectangle().fill(ink).frame(height: 1) }
            if !note.collapsed {
                NoteTextView(note: note, ink: NSColor(ink), font: style.bodyFont)
                    .padding(style == .mac
                             ? EdgeInsets(top: 2, leading: 12, bottom: 12, trailing: 12)
                             : EdgeInsets(top: 6, leading: 10, bottom: 10, trailing: 10))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(card, in: shape)
        .overlay(shape.strokeBorder(style == .mac ? ink.opacity(0.12) : ink, lineWidth: style == .mac ? 0.5 : 1))
        .clipShape(shape)
        .onHover { hovering = $0 }
        .background(ShadowRefresher(style: style, collapsed: note.collapsed))
        .onChange(of: style) { onStyleChange() }
    }

    private var titleBar: some View {
        HStack(spacing: 0) {
            if style == .mac {
                HStack(spacing: 7) {
                    MacButton(symbol: "xmark", ink: ink, action: onClose)
                    MacButton(symbol: note.collapsed ? "plus" : "minus", ink: ink, action: onToggle)
                }
                .padding(.leading, 9)
                .opacity(hovering ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: hovering)
            }
            Text(note.title ?? "")
                .font(style.titleFont)
                .foregroundStyle(ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, style == .mac ? 8 : 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            if style == .windows {
                BarButton(symbol: note.collapsed ? "square" : "minus", ink: ink, hover: card,
                          height: style.barHeight - 1, action: onToggle)
                BarButton(symbol: "xmark", ink: ink, hover: Color(red: 235 / 255, green: 161 / 255, blue: 151 / 255),
                          height: style.barHeight - 1, action: onClose)
            }
        }
        .frame(height: style == .windows ? style.barHeight - 1 : style.barHeight)
        .background(WindowDragArea())
        .background(style == .windows ? bar : card)
        .contextMenu { NoteStylePicker() }
    }
}

/// Small round control in the ink color, in the place of the window buttons.
private struct MacButton: View {
    let symbol: String
    let ink: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(ink.opacity(hovering ? 0.85 : 0.55))
                .frame(width: 13, height: 13)
                .background(ink.opacity(hovering ? 0.22 : 0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Square title-bar button of the Windows style.
private struct BarButton: View {
    let symbol: String
    let ink: Color
    let hover: Color
    let height: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ink)
                .frame(width: height + 1, height: height)
                .background(hovering ? hover : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The window shadow follows the card's shape only after it is recomputed.
private struct ShadowRefresher: NSViewRepresentable {
    let style: NoteStyle
    let collapsed: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        Task { view.window?.invalidateShadow() }
    }
}

extension Color {
    init(_ color: NoteColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}
