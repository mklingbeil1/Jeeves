import SwiftUI
import AppKit

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct Row: View {
    let it: Item
    let on: Bool
    let k: Int
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let img = it.image {
                Image(nsImage: img).resizable().frame(width: 30, height: 30)
            } else {
                Text(it.icon).font(.system(size: 22)).frame(width: 30)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(it.title).fontWeight(.semibold).lineLimit(1)
                if !it.sub.isEmpty {
                    Text(it.sub).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if it.del != nil {
                Button(action: onDelete) { Text("✕").foregroundColor(.secondary) }.buttonStyle(.plain)
            } else if k < 9 {
                Text("⌥\(k + 1)").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(on ? Color.accentColor.opacity(0.25) : Color.clear)
        .contentShape(Rectangle())
    }
}

struct RootView: View {
    @ObservedObject var m: Launcher
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("What can I fetch?", text: $m.query)
                .textFieldStyle(.plain)
                .font(.system(size: 26, design: .serif))
                .focused($focused)
                .onSubmit { m.run(m.sel) }
                .padding(.horizontal, 20)
                .frame(height: 72)
            if !m.items.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(m.items.enumerated()), id: \.element.id) { k, it in
                                Row(it: it, on: k == m.sel, k: k, onDelete: { it.del?(); m.refresh() })
                                    .id(it.id)
                                    .onTapGesture { m.run(k) }
                            }
                        }
                    }
                    .frame(height: CGFloat(min(m.items.count, 8)) * 48)
                    .onChange(of: m.sel) { _ in
                        if m.items.indices.contains(m.sel) { proxy.scrollTo(m.items[m.sel].id) }
                    }
                }
            }
        }
        .frame(width: 680)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.12)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
        .onChange(of: m.focusTick) { _ in focused = true }
    }
}
