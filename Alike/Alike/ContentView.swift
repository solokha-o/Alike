//
//  ContentView.swift
//  Alike
//
//  Created by Oleksand S on 27.01.2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "photo.stack")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Alike - Photo Similarity Finder")
                .font(.headline)
            Text("📦 Please add Swift Packages in Xcode")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
