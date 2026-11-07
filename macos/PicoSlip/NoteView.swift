import SwiftUI
import PicoKit

/// Window-level actions the card asks its panel for.
struct NoteActions {
    let toggleCollapsed: () -> Void
    let close: () -> Void
    let menu: () -> NSMenu
    let setTitle: (String?) -> Void
    let styleChanged: () -> Void
}

/// The note card in either style. Colors always come from the shared palettes.
struct NoteView: View {
    @Bindable var note: Note
    let editor: NSScrollView
    let actions: NoteActions
    @AppStorage(NoteStyle.storageKey) private var style: NoteStyle = .mac
    @State private var hovering = false

    private var card: Color { Color(note.palette.card(note.color)) }
    private var ink: Color { Color(note.palette.ink(note.color)) }
    private var bar: Color { Color(note.palette.bar(note.color)) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        let insets = style.textInsets
        VStack(spacing: 0) {
            titleBar
            if style == .windows { Rectangle().fill(ink).frame(height: 1) }
            if !note.collapsed {
                EditorHost(view: editor)
                    .padding(EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(card, in: shape)
        .overlay(shape.strokeBorder(style == .mac ? ink.opacity(0.12) : ink, lineWidth: style == .mac ? 0.5 : 1))
        .overlay(alignment: .topTrailing) {
            if note.saveFailed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help("This note could not be saved. PicoSlip keeps retrying.")
                    .padding(8)
            }
        }
        .clipShape(shape)
        .onHover { hovering = $0 }
        .background(ShadowRefresher(style: style, collapsed: note.collapsed))
        .onChange(of: style) { actions.styleChanged() }
    }

    private var titleBar: some View {
        HStack(spacing: 0) {
            if style == .mac {
                HStack(spacing: 7) {
                    MacButton(symbol: "xmark", ink: ink, action: actions.close)
                    MacButton(symbol: note.collapsed ? "plus" : "minus", ink: ink, action: actions.toggleCollapsed)
                }
                .padding(.leading, 9)
                .opacity(hovering ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: hovering)
            }
            ZStack(alignment: .leading) {
                TitleBarArea(onDoubleClick: { note.editingTitle = true }, menu: actions.menu)
                if note.editingTitle {
                    TitleField(initial: note.title ?? "", ink: ink, font: style.titleFont, commit: actions.setTitle)
                        .padding(.horizontal, style == .mac ? 8 : 10)
                } else {
                    Text(note.title ?? "")
                        .font(style.titleFont)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, style == .mac ? 8 : 10)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if style == .windows {
                BarButton(symbol: note.collapsed ? "square" : "minus", ink: ink, hover: card,
                          height: style.barHeight - 1, action: actions.toggleCollapsed)
                BarButton(symbol: "xmark", ink: ink, hover: Color(red: 235 / 255, green: 161 / 255, blue: 151 / 255),
                          height: style.barHeight - 1, action: actions.close)
            }
        }
        .frame(height: style == .windows ? style.barHeight - 1 : style.barHeight)
        .background(style == .windows ? bar : card)
    }
}

/// Inline title editor: Enter saves, Esc cancels, an empty title removes it.
private struct TitleField: View {
    let initial: String
    let ink: Color
    let font: Font
    let commit: (String?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Title", text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(ink)
            .focused($focused)
            .onSubmit { commit(text) }
            .onExitCommand { commit(initial.isEmpty ? nil : initial) }
            .onAppear { text = initial; focused = true }
    }
}

/// The editor's scroll view, created and owned by the panel.
private struct EditorHost: NSViewRepresentable {
    let view: NSScrollView
    func makeNSView(context: Context) -> NSScrollView { view }
    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

/// Drag to move, double-click to edit the title, right-click for the menu.
private struct TitleBarArea: NSViewRepresentable {
    let onDoubleClick: () -> Void
    let menu: () -> NSMenu

    func makeNSView(context: Context) -> BarView { BarView() }

    func updateNSView(_ view: BarView, context: Context) {
        view.onDoubleClick = onDoubleClick
        view.makeMenu = menu
    }

    final class BarView: NSView {
        var onDoubleClick: (() -> Void)?
        var makeMenu: (() -> NSMenu)?

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { onDoubleClick?() } else { window?.performDrag(with: event) }
        }

        override func menu(for event: NSEvent) -> NSMenu? { makeMenu?() }
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
