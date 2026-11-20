import SwiftUI

/// zero red 的界面基调：黑白单色的 iOS 27 原生外观。
/// 玻璃只负责层次与景深，不引入彩色 tint；iOS 26 以下回退到系统材质，
/// 所以工程仍可部署到 iOS 17，同时在 iOS 27 上使用原生 Liquid Glass。
enum ZeroRedTheme {
    static let dockControl: CGFloat = 56
    static let dockIcon: CGFloat = 24
    static let dockSpacing: CGFloat = 0
    static let cardRadius: CGFloat = 22
    static let contentRadius: CGFloat = 26
    static let maxContentWidth: CGFloat = 560
}

extension View {
    /// 原生 Liquid Glass 表面。`interactive` 打开按压反馈，适合可点的胶囊/按钮。
    @ViewBuilder
    func zeroRedGlass(_ shape: some Shape, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                glassEffect(.regular.interactive(), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    /// 把多个玻璃元素交给系统统一渲染，让它们在动画里能互相融合、变形。
    @ViewBuilder
    func zeroRedGlassGroup(spacing: CGFloat = 12) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

/// 玻璃底栏：图标按钮共用一条胶囊，间距由系统玻璃容器协调。
struct GlassDock<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: ZeroRedTheme.dockSpacing) { content }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .zeroRedGlass(Capsule(), interactive: true)
            .zeroRedGlassGroup(spacing: 6)
    }
}

/// 底栏里的图标按钮。无障碍标签与标识符由调用方提供，保留既有 UI 测试的定位方式。
struct GlassDockButton: View {
    var symbol: String
    var label: String
    var identifier: String
    var isEnabled: Bool = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: ZeroRedTheme.dockIcon, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: ZeroRedTheme.dockControl)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// 独立的圆形玻璃按钮（关闭页面、返回等）。
struct GlassCircleButton: View {
    var symbol: String
    var label: String
    var size: CGFloat = 34
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .frame(width: size, height: size)
                .zeroRedGlass(Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// 工具栏图标按钮。iOS 26 起用系统原生玻璃按钮样式，旧系统退回普通按钮。
struct GlassToolbarButton: View {
    var symbol: String
    var label: String
    var action: () -> Void
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) { Image(systemName: symbol) }
                .buttonStyle(.glass)
                .accessibilityLabel(label)
        } else {
            Button(action: action) { Image(systemName: symbol) }
                .accessibilityLabel(label)
        }
    }
}

/// 确认/收尾类主按钮：iOS 26 用原生 `.glassProminent`，旧系统用 `.borderedProminent`。
struct GlassProminentButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(title, action: action).buttonStyle(.glassProminent)
        } else {
            Button(title, action: action).buttonStyle(.borderedProminent)
        }
    }
}

/// 资料库分页胶囊：选中态给一枚原生玻璃胶囊，未选中保持纯文本。
struct ZeroRedChip: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void
    var body: some View {
        if isSelected {
            chip.zeroRedGlass(Capsule(), interactive: true)
        } else {
            chip
        }
    }
    private var chip: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }
}

/// 极简字标：黑白单色，不引入品牌彩色。
struct ZeroRedWordmark: View {
    var subtitle: String?
    var body: some View {
        VStack(spacing: 8) {
            Text("zero red")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .tracking(-0.8)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 细线胶囊进度条，替代默认进度控件，和玻璃底栏保持同一套圆角语言。
struct ThinProgressBar: View {
    var value: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.12))
                Capsule().fill(.primary)
                    .frame(width: max(2, geometry.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}