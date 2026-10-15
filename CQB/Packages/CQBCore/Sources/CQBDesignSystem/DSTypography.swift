//
//  DSTypography.swift
//  CQBCore
//
//  Created by YoonJung Kwak on 10/8/26.
//

import Foundation
import SwiftUI

public enum DSTypography {
    public static let h1 = font("NotoSansKR-Bold", size: 32)
    public static let h2 = font("NotoSansKR-Bold", size: 24)
    public static let h3 = font("NotoSansKR-Bold", size: 16)

    public static let body = font("NotoSansKR-Regular", size: 16)
    public static let bodySmall = font("NotoSansKR-Regular", size: 14)
    public static let label = font("NotoSansKR-Medium", size: 12)
    public static let caption = font("NotoSansKR-Regular", size: 12)

    private static func font(_ name: String, size: CGFloat) -> Font {
        DSFonts.register()
        return .custom(name, size: size)
    }
}
