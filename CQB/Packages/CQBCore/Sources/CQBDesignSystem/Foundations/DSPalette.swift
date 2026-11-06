import SwiftUI

/// Figma 디자인 시스템의 원시 색상 팔레트입니다.
///
/// 화면에서는 원시 팔레트보다 ``DSColor``의 의미 토큰을 우선 사용합니다.
public enum DSPalette {
    public enum Neutral {
        public static let white = color(0xFFFFFF)
        public static let black = color(0x070707)
    }

    public enum Gray {
        public static let g50 = color(0xFAFAFA)
        public static let g100 = color(0xB7B8BA)
        public static let g200 = color(0x9A9B9C)
        public static let g300 = color(0x7C7D7F)
        public static let g400 = color(0x5F6061)
        public static let g500 = color(0x40444B)
        public static let g600 = color(0x34363A)
        public static let g700 = color(0x2D2D31)
        public static let g800 = color(0x1E1E24)
        public static let g850 = color(0x161619)
        public static let g900 = color(0x0D0D0E)
        public static let g700Opacity20 = g700.opacity(0.2)
    }

    public enum Primary {
        public static let p50 = color(0xFFFBE5)
        public static let p100 = color(0xFFF7CC)
        public static let p200 = color(0xFFF099)
        public static let p300 = color(0xFFE866)
        public static let p400 = color(0xFFE133)
        public static let p500 = color(0xFFD900)
        public static let p600 = color(0xCCAE00)
        public static let p700 = color(0x998200)
        public static let p800 = color(0x665700)
        public static let p900 = color(0x332B00)
    }

    public enum Red {
        public static let r50 = color(0xFADCDC)
        public static let r100 = color(0xF5C4C4)
        public static let r200 = color(0xEB9393)
        public static let r300 = color(0xE06262)
        public static let r400 = color(0xD63131)
        public static let r500 = color(0xCC0000)
        public static let r600 = color(0xA30000)
        public static let r700 = color(0x7A0000)
        public static let r800 = color(0x520000)
        public static let r900 = color(0x290000)
    }

    public enum Green {
        public static let g50 = color(0xDEF4BA)
        public static let g100 = color(0xC1DA98)
        public static let g200 = color(0xA5C177)
        public static let g300 = color(0x88A755)
        public static let g400 = color(0x6C8E34)
        public static let g500 = color(0x4F7412)
        public static let g600 = color(0x3F5D0E)
        public static let g700 = color(0x2F460B)
        public static let g800 = color(0x202E07)
        public static let g900 = color(0x101704)
    }

    public enum Yellow {
        public static let y50 = color(0xFCF4E5)
        public static let y100 = color(0xFAEACC)
        public static let y200 = color(0xF4D499)
        public static let y300 = color(0xEFBF66)
        public static let y400 = color(0xE9A933)
        public static let y500 = color(0xE49400)
        public static let y600 = color(0xB67600)
        public static let y700 = color(0x895900)
        public static let y800 = color(0x5B3B00)
        public static let y900 = color(0x2E1E00)
    }

    public enum Blue {
        public static let b50 = color(0xE5EFFC)
        public static let b100 = color(0xCCE0FA)
        public static let b200 = color(0x99C1F4)
        public static let b300 = color(0x66A1EF)
        public static let b400 = color(0x3382E9)
        public static let b500 = color(0x0063E4)
        public static let b600 = color(0x004FB6)
        public static let b700 = color(0x003B89)
        public static let b800 = color(0x00285B)
        public static let b900 = color(0x00142E)
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
