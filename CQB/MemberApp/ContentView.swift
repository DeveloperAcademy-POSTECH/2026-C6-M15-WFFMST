//
//  ContentView.swift
//  CQB
//
//  Created by Dayoon Lee on 10/7/26.
//

import SwiftUI
import CQBCore
import CQBFixtures
import CQBDesignSystem

struct ContentView: View {
    private let sample = FixtureCatalog.samples[0]

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("iphone")
            
            Text(sample.title)
                .font(DSTypography.h3)
                .foregroundStyle(DSColor.team1)
                
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
