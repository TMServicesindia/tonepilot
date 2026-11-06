import SwiftUI

/// Shared TonePilot components, built only from `DS` tokens. Screens compose these instead of styling
/// views ad hoc. Every interactive component keeps a 44 pt hit area and supports Dynamic Type.

// MARK: Surfaces

extension View {
    /// Groups content on a surface (one level above the canvas). Use only when grouping helps.
    func dsSurface(padding: CGFloat = DS.Space.componentPadding, radius: CGFloat = DS.Radius.l) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// The screen background.
    func dsCanvas() -> some View { background(DS.Palette.canvas.ignoresSafeArea()) }
}

/// A section heading with an optional trailing action ("Edit", "See all").
struct DSSectionHeader: View {
    let title: String
    var action: (title: String, id: String, run: () -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(DS.Text.section).foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Space.s)
            if let action {
                Button(action.title, action: action.run)
                    .font(DS.Text.label).foregroundStyle(DS.Palette.accent)
                    .frame(minHeight: DS.Size.touchTarget)
                    .accessibilityIdentifier(action.id)
            }
        }
    }
}

// MARK: Buttons

/// Filled accent button: the one primary action on a screen or card.
struct DSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Text.button)
            .frame(maxWidth: .infinity, minHeight: DS.Size.primaryButton)
            .padding(.horizontal, DS.Space.l)
            .foregroundStyle(enabled ? DS.Palette.onAccent : DS.Palette.textTertiary)
            .background(enabled ? DS.Palette.accent : DS.Palette.disabled, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Neutral button on the elevated colour: secondary actions next to a primary one.
struct DSSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Text.button)
            .frame(maxWidth: .infinity, minHeight: DS.Size.primaryButton)
            .padding(.horizontal, DS.Space.l)
            .foregroundStyle(enabled ? DS.Palette.textPrimary : DS.Palette.textTertiary)
            .background(DS.Palette.elevated, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == DSPrimaryButtonStyle { static var dsPrimary: DSPrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == DSSecondaryButtonStyle { static var dsSecondary: DSSecondaryButtonStyle { .init() } }

// MARK: Chips

/// Small status or metadata chip. Meaning never relies on colour alone: always text, optional icon.
struct DSChip: View {
    enum Tone { case neutral, accent, success, warning, error }
    let text: String
    var symbol: String? = nil
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(DS.Text.metadata.weight(.semibold))
        .padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.xs)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return DS.Palette.textSecondary
        case .accent: return DS.Palette.accent
        case .success: return DS.Palette.success
        case .warning: return DS.Palette.warning
        case .error: return DS.Palette.error
        }
    }
    private var background: Color { tone == .neutral ? DS.Palette.elevated : foreground.opacity(0.16) }
}

// MARK: Segmented control

/// Fixed, always-visible segmented control (Song Studio pages). Equal widths when they fit; at large
/// text sizes it becomes a horizontally scrolling row, so no label is truncated or hyphenated.
struct DSSegmentedControl<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let identifier: (Item) -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.xxs) { ForEach(items) { segment($0, equal: true) } }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.xxs) { ForEach(items) { segment($0, equal: false) } }
            }
        }
        .padding(DS.Space.xxs)
        .background(DS.Palette.elevated, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
    }

    private func segment(_ item: Item, equal: Bool) -> some View {
        let on = item == selection
        return Button {
            withAnimation(DS.Motion.standard(reduceMotion: reduceMotion)) { selection = item }
        } label: {
            Text(title(item))
                .font(DS.Text.label)
                .lineLimit(1)
                .fixedSize(horizontal: !equal, vertical: false)
                .padding(.horizontal, DS.Space.m)
                .frame(maxWidth: equal ? .infinity : nil, minHeight: DS.Size.segmentedHeight)
                .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textPrimary)
                .background(on ? DS.Palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: DS.Radius.m - 2, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: DS.Size.touchTarget)
        .accessibilityIdentifier(identifier(item))
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: Rows

/// A tappable navigation row: icon, title, value, chevron (e.g. the tone row on the Play page).
struct DSNavigationRow: View {
    let symbol: String
    let title: String
    var value: String? = nil
    var id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.m) {
                Image(systemName: symbol).font(DS.Text.section).foregroundStyle(DS.Palette.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title).font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                    if let value { Text(value).font(DS.Text.body.weight(.semibold)).foregroundStyle(DS.Palette.textPrimary).lineLimit(2) }
                }
                Spacer(minLength: DS.Space.s)
                Image(systemName: "chevron.right").font(DS.Text.metadata.weight(.semibold)).foregroundStyle(DS.Palette.textTertiary)
            }
            .frame(minHeight: DS.Size.touchTarget)
            .dsSurface(padding: DS.Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

/// Empty or not-yet state: one line of explanation and at most one action.
struct DSEmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var action: (title: String, id: String, run: () -> Void)? = nil

    var body: some View {
        VStack(spacing: DS.Space.s) {
            Image(systemName: symbol).font(.title2).foregroundStyle(DS.Palette.textTertiary)
            Text(title).font(DS.Text.section).foregroundStyle(DS.Palette.textPrimary).multilineTextAlignment(.center)
            if let message { Text(message).font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary).multilineTextAlignment(.center) }
            if let action {
                Button(action.title, action: action.run).buttonStyle(.dsPrimary).padding(.top, DS.Space.s)
                    .accessibilityIdentifier(action.id)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xl)
    }
}
