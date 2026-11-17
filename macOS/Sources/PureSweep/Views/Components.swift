import SwiftUI

// The main window uses an immersive look: a full-bleed gradient that changes colour per section,
// light text, frosted "glass" cards and one large glowing round action button per page.

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension AppModel.Page {
    /// Background gradient, dark to light.
    var palette: [Color] {
        switch self {
        case .home: return [Color(hex: 0x1A1440), Color(hex: 0x3B1D7A), Color(hex: 0x6B2FA8)]
        case .cleanup: return [Color(hex: 0x062A3F), Color(hex: 0x0B5372), Color(hex: 0x1293A8)]
        case .snapshots: return [Color(hex: 0x111633), Color(hex: 0x23307A), Color(hex: 0x3F52C4)]
        case .uninstaller: return [Color(hex: 0x2A0716), Color(hex: 0x6E1236), Color(hex: 0xB0305A)]
        case .loginItems: return [Color(hex: 0x03241F), Color(hex: 0x0A5546), Color(hex: 0x13917A)]
        case .largeFiles: return [Color(hex: 0x2B0D05), Color(hex: 0x7A2A0C), Color(hex: 0xC4561A)]
        case .shredder: return [Color(hex: 0x111214), Color(hex: 0x2A2D35), Color(hex: 0x4A505E)]
        }
    }
    /// Bright accent used for the button ring, icons and progress.
    var accent: Color {
        switch self {
        case .home: return Color(hex: 0xC79BFF)
        case .cleanup: return Color(hex: 0x5CE1E6)
        case .snapshots: return Color(hex: 0x9DB0FF)
        case .uninstaller: return Color(hex: 0xFF8FB0)
        case .loginItems: return Color(hex: 0x6FF0C8)
        case .largeFiles: return Color(hex: 0xFFB36B)
        case .shredder: return Color(hex: 0xC9D1E0)
        }
    }
}

/// Full-window background: the section gradient plus a soft glow.
struct ImmersiveBackground: View {
    let page: AppModel.Page
    var body: some View {
        ZStack {
            LinearGradient(colors: page.palette, startPoint: .bottomLeading, endPoint: .topTrailing)
            RadialGradient(colors: [page.accent.opacity(0.35), .clear], center: UnitPoint(x: 0.65, y: 0.35), startRadius: 10, endRadius: 520)
            RadialGradient(colors: [.black.opacity(0.35), .clear], center: .bottomLeading, startRadius: 0, endRadius: 600)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: page)
    }
}

/// The current section, so shared components can pick up its accent.
private struct PageKey: EnvironmentKey { static let defaultValue = AppModel.Page.home }
extension EnvironmentValues {
    var page: AppModel.Page {
        get { self[PageKey.self] }
        set { self[PageKey.self] = newValue }
    }
}

/// Page title: large white heading, subtitle and an optional trailing action.
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    var colors: [Color] = []      // kept for call-site compatibility; the window gradient supplies colour now
    @ViewBuilder var trailing: Trailing
    @Environment(\.page) private var page

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(page.accent)
                .frame(width: 46, height: 46)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 26, weight: .bold))
                Text(subtitle).font(.callout).foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 12)
            trailing
        }
        .foregroundStyle(.white)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String, symbol: String, colors: [Color] = []) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, colors: colors) { EmptyView() }
    }
}

/// Frosted capsule button for secondary actions on the gradient.
struct HeaderButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.white.opacity(configuration.isPressed ? 0.28 : 0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Frosted glass panel.
struct Card: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(Card(padding: padding)) }

    /// A List styled to sit on the gradient inside a glass panel.
    func glassList() -> some View {
        self.scrollContentBackground(.hidden)
            .listStyle(.plain)
            .padding(.vertical, 6)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The page's single big round action, with a glowing ring. Optional progress (0-100) draws around it.
struct BigActionButton: View {
    let title: String
    var subtitle: String? = nil
    var progress: Double? = nil
    var enabled = true
    let action: () -> Void
    @Environment(\.page) private var page
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(page.accent.opacity(0.25)).blur(radius: 24)
                    .scaleEffect(pulse ? 1.12 : 0.95)
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(LinearGradient(colors: [page.accent, .white.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                if let progress {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 5).padding(-10)
                    Circle().trim(from: 0, to: max(0.001, progress / 100))
                        .stroke(page.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(-10)
                        .shadow(color: page.accent, radius: 6)
                }
                VStack(spacing: 2) {
                    Text(title).font(.system(size: title.count > 7 ? 17 : 20, weight: .semibold))
                    if let subtitle { Text(subtitle).font(.caption.weight(.medium)).opacity(0.8).monospacedDigit() }
                }
                .foregroundStyle(.white)
            }
            .frame(width: 120, height: 120)
            .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.7)
        .onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = true } }
        .accessibilityLabel(subtitle == nil ? title : "\(title) \(subtitle!)")
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Large glowing emblem for a page's start screen.
struct HeroEmblem: View {
    let symbol: String
    var size: CGFloat = 200
    var spinning = false
    @Environment(\.page) private var page
    @State private var turn = false

    var body: some View {
        ZStack {
            Circle().fill(page.accent.opacity(0.18)).blur(radius: 40)
            Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1).padding(size * 0.02)
            Circle().strokeBorder(.white.opacity(0.06), lineWidth: 1).padding(size * 0.14)
            Circle()
                .fill(LinearGradient(colors: [page.accent.opacity(0.9), page.palette[1]], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(size * 0.24)
                .shadow(color: page.accent.opacity(0.6), radius: 30)
            Image(systemName: symbol)
                .font(.system(size: size * 0.24, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .symbolEffect(.pulse, isActive: spinning)
            if spinning {
                Circle().trim(from: 0, to: 0.25)
                    .stroke(page.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .padding(size * 0.08)
                    .rotationEffect(.degrees(turn ? 360 : 0))
                    .onAppear { withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { turn = true } }
            }
        }
        .frame(width: size, height: size)
    }
}

/// Start screen: emblem, headline, explanation, then the big button.
struct LandingView<Button: View>: View {
    let symbol: String
    let title: String
    let text: String
    @ViewBuilder var button: Button

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            HeroEmblem(symbol: symbol)
            Text(title).font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            Text(text).font(.title3).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center).frame(maxWidth: 520)
            Spacer(minLength: 0)
            button
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Dashboard dial.
struct RingGauge: View {
    var value: Double          // 0-100
    var color: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value / 100)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.6), radius: 6)
        }
        .animation(.easeOut(duration: 0.6), value: value)
    }
}

/// Round checkbox with a mixed state (some, but not all, sub-items ticked).
struct TriCheckbox: View {
    var state: Bool?
    var action: () -> Void
    @Environment(\.page) private var page

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(.white.opacity(state == false ? 0.45 : 0), lineWidth: 1.5)
                if state != false {
                    Circle().fill(page.accent)
                    Image(systemName: state == true ? "checkmark" : "minus")
                        .font(.system(size: 10, weight: .heavy)).foregroundStyle(page.palette[0])
                }
            }
            .frame(width: 20, height: 20)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(state == true ? "checked" : state == nil ? "mixed" : "unchecked")
    }
}

/// Same look as TriCheckbox, for a Bool binding.
struct RoundCheckbox: View {
    @Binding var isOn: Bool
    var body: some View { TriCheckbox(state: isOn) { isOn.toggle() } }
}

/// Notice strip, e.g. for Full Disk Access.
struct Banner<Actions: View>: View {
    let symbol: String
    let text: String
    var tint: Color = .orange
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).font(.title3)
            Text(text).font(.callout).foregroundStyle(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            actions
        }
        .padding(12)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.45)))
    }
}

struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .shadow(color: color.opacity(0.4), radius: 4, y: 2)
    }
}
