import SwiftUI

/// Hex and light/dark construction helpers for the design-system color tokens.
///
/// Kept in `Support/Theme/` so `Theme` is the only place raw hex values appear.
/// The light/dark initializer builds a dynamic color that resolves against the
/// current interface style, giving app chrome sensible light and dark variants
/// without an asset catalog.
extension Color {
    /// A solid color from a 24-bit `0xRRGGBB` hex value, fully opaque.
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    /// A dynamic color that resolves to `light` in light mode and `dark` in dark
    /// mode (both `0xRRGGBB`). Falls back to the light value on platforms without
    /// a trait collection.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        let dynamic = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark)
                : UIColor(hex: light)
        }
        self.init(uiColor: dynamic)
        #else
        self.init(hex: light)
        #endif
    }
}

#if canImport(UIKit)
import UIKit

extension UIColor {
    /// A solid `UIColor` from a 24-bit `0xRRGGBB` hex value, used to back the
    /// dynamic (light/dark) `Color` provider.
    fileprivate convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
#endif
