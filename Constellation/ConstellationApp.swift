//
//  ConstellationApp.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/25/26.
//

import SwiftUI
import SwiftData

@main
struct ConstellationApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Movie.self,
            TVShow.self,
            Theme.self,
            ItemCollection.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
