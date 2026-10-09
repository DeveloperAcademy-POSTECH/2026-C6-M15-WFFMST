//
//  DSFonts.swift
//  CQBCore
//
//  Created by YoonJung Kwak on 10/9/26.
//

import CoreText
import Foundation

public enum DSFonts {
    private static let registration: Void = {
        let names = [
            "NotoSansKR-Regular",
            "NotoSansKR-Medium",
            "NotoSansKR-Bold"
        ]

        for name in names {
            guard let url = Bundle.module.url(
                forResource: name,
                withExtension: "ttf"
            ) else {
                assertionFailure("폰트 파일을 찾을 수 없습니다: \(name)")
                continue
            }

            var error: Unmanaged<CFError>?
            let success = CTFontManagerRegisterFontsForURL(
                url as CFURL,
                .process,
                &error
            )

            if !success, let error = error?.takeRetainedValue() {
                // 다른 경로에서 이미 등록한 폰트는 정상으로 취급합니다.
                if CFErrorGetCode(error)
                    != CTFontManagerError.alreadyRegistered.rawValue {
                    assertionFailure("폰트 등록 실패: \(name), \(error)")
                }
            }
        }
    }()

    public static func register() {
        _ = registration
    }
}
