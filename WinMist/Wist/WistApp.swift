//
//  WistApp.swift
//  Wist
//

import SwiftUI

@main
struct WistApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 980, height: 640)
    }
}
