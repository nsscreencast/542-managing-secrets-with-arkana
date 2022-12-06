//
//  UnsplashBrowserApp.swift
//  UnsplashBrowser
//
//  Created by Ben Scheirman on 1/24/22.
//

import SwiftUI

@main
struct UnsplashBrowserApp: App {
    
    @StateObject var photosViewModel = PhotosViewModel(client: .init())
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: photosViewModel)
        }
    }
}
