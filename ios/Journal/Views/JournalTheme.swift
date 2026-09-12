import SwiftUI
import UIKit

/// Journal design system replicating the macOS desktop aesthetic:
/// "A quiet room for writing. Warm paper in light, deep ink in dark."
public enum JournalTheme {
    // MARK: - Color Palette

    /// Warm paper in light (#faf8f5), deep ink in dark (#17161a).
    public static let bg = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x17/255.0, green: 0x16/255.0, blue: 0x1a/255.0, alpha: 1.0)
            : UIColor(red: 0xfa/255.0, green: 0xf8/255.0, blue: 0xf5/255.0, alpha: 1.0)
    })

    /// Raised card background (#ffffff in light, #1f1e23 in dark).
    public static let bgRaised = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x1f/255.0, green: 0x1e/255.0, blue: 0x23/255.0, alpha: 1.0)
            : UIColor.white
    })

    /// Sunken control background (#f2efea in light, #131217 in dark).
    public static let bgSunken = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x13/255.0, green: 0x12/255.0, blue: 0x17/255.0, alpha: 1.0)
            : UIColor(red: 0xf2/255.0, green: 0xef/255.0, blue: 0xea/255.0, alpha: 1.0)
    })

    /// Subtle border (#e4ded5 in light, #302e36 in dark).
    public static let border = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x30/255.0, green: 0x2e/255.0, blue: 0x36/255.0, alpha: 1.0)
            : UIColor(red: 0xe4/255.0, green: 0xde/255.0, blue: 0xd5/255.0, alpha: 1.0)
    })

    /// Strong border (#d3cbbf in light, #423f4a in dark).
    public static let borderStrong = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x42/255.0, green: 0x3f/255.0, blue: 0x4a/255.0, alpha: 1.0)
            : UIColor(red: 0xd3/255.0, green: 0xcb/255.0, blue: 0xbf/255.0, alpha: 1.0)
    })

    /// Primary text (#2b2622 in light, #e8e4de in dark).
    public static let text = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xe8/255.0, green: 0xe4/255.0, blue: 0xde/255.0, alpha: 1.0)
            : UIColor(red: 0x2b/255.0, green: 0x26/255.0, blue: 0x22/255.0, alpha: 1.0)
    })

    /// Soft text (#6b625a in light, #a39d96 in dark).
    public static let textSoft = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xa3/255.0, green: 0x9d/255.0, blue: 0x96/255.0, alpha: 1.0)
            : UIColor(red: 0x6b/255.0, green: 0x62/255.0, blue: 0x5a/255.0, alpha: 1.0)
    })

    /// Faint text (#9a9089 in light, #6f6a66 in dark).
    public static let textFaint = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x6f/255.0, green: 0x6a/255.0, blue: 0x66/255.0, alpha: 1.0)
            : UIColor(red: 0x9a/255.0, green: 0x90/255.0, blue: 0x89/255.0, alpha: 1.0)
    })

    /// Warm terracotta accent (#9a5b3d in light, #d99a72 in dark).
    public static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xd9/255.0, green: 0x9a/255.0, blue: 0x72/255.0, alpha: 1.0)
            : UIColor(red: 0x9a/255.0, green: 0x5b/255.0, blue: 0x3d/255.0, alpha: 1.0)
    })

    /// Soft accent tint (#f0e2da in light, #2c2420 in dark).
    public static let accentSoft = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x2c/255.0, green: 0x24/255.0, blue: 0x20/255.0, alpha: 1.0)
            : UIColor(red: 0xf0/255.0, green: 0xe2/255.0, blue: 0xda/255.0, alpha: 1.0)
    })

    /// Destructive danger tone (#a4402f in light, #d8735e in dark).
    public static let danger = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xd8/255.0, green: 0x73/255.0, blue: 0x5e/255.0, alpha: 1.0)
            : UIColor(red: 0xa4/255.0, green: 0x40/255.0, blue: 0x2f/255.0, alpha: 1.0)
    })

    // MARK: - Typography

    /// Serif font for headers & wordmarks ("Iowan Old Style" / Palatino / Serif fallback).
    public static func serifTitle(_ size: CGFloat = 22, weight: Font.Weight = .semibold) -> Font {
        if UIFont(name: "IowanOldStyle-Bold", size: size) != nil {
            return .custom("IowanOldStyle-Bold", size: size)
        }
        return .system(size: size, weight: weight, design: .serif)
    }

    /// Serif font for body reading & prose.
    public static func serifProse(_ size: CGFloat = 16.5, weight: Font.Weight = .regular) -> Font {
        if UIFont(name: "IowanOldStyle-Roman", size: size) != nil {
            return .custom("IowanOldStyle-Roman", size: size)
        }
        return .system(size: size, weight: weight, design: .serif)
    }

    /// Wordmark font used in the app navigation header.
    public static var wordmark: Font {
        if UIFont(name: "IowanOldStyle-Bold", size: 21) != nil {
            return .custom("IowanOldStyle-Bold", size: 21)
        }
        return .system(size: 21, weight: .bold, design: .serif)
    }

    // MARK: - Shadows & Corner Radii

    public static let cardRadius: CGFloat = 14
    public static let buttonRadius: CGFloat = 8
    public static let chipRadius: CGFloat = 20

    public static let shadowColor = Color.black.opacity(0.04)
}

// MARK: - View Modifiers

public struct JournalCardModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background(JournalTheme.bgRaised)
            .clipShape(RoundedRectangle(cornerRadius: JournalTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: JournalTheme.cardRadius, style: .continuous)
                    .stroke(JournalTheme.border, lineWidth: 1)
            )
            .shadow(color: JournalTheme.shadowColor, radius: 4, x: 0, y: 2)
    }
}

public extension View {
    func journalCard() -> some View {
        self.modifier(JournalCardModifier())
    }

    func journalBackground() -> some View {
        self.background(JournalTheme.bg.ignoresSafeArea())
    }
}
