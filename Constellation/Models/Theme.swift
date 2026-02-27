//
//  Theme.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//


import Foundation
import SwiftData

@Model
final class Theme {
    var id: UUID
    var name: String
    var type: ThemeType
    var itemCount: Int
    var lastUpdated: Date
    var relatedThemes: [String] // IDs of related themes
    
    init(name: String, type: ThemeType = .concept) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.itemCount = 0
        self.lastUpdated = Date()
        self.relatedThemes = []
    }
}

enum ThemeType: String, Codable {
    case concept      // "decision-making"
    case genre        // "sci-fi"
    case mood         // "dark"
    case topic        // "WWII"
    case person       // "Kennedy family"
    case place        // "New York"
}
