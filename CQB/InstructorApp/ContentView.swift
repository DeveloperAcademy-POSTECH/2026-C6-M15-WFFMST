//
//  ContentView.swift
//  InstructorApp
//
//  Created by Dayoon Lee on 10/7/26.
//

import SwiftUI
import CQBCore
import CQBFixtures

struct ContentView: View {
    private let sample = FixtureCatalog.samples[1]

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("iPad")
            
            Text(sample.title)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
