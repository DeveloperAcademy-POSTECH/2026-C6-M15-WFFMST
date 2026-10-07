//
//  DevelopmentSample.swift
//  CQB
//
//  Created by Dayoon Lee on 10/8/26.
//

import Foundation

public struct DevelopmentSample: Identifiable, Sendable {
    public let id: UUID
    public let title: String

    public init(
        id: UUID = UUID(),
        title: String
    ) {
        self.id = id
        self.title = title
    }
}

