//
//  SettingsView.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("theme.semanticMatchThreshold") private var semanticThreshold = 0.79
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Theme Matching") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Semantic Match Threshold")
                            Spacer()
                            Text(String(format: "%.2f", semanticThreshold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        
                        Slider(value: $semanticThreshold, in: 0.60...0.95, step: 0.01)
                        
                        Text("Lower values merge more tags. Higher values keep tags more distinct.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Button("Reset to Default (0.79)") {
                        semanticThreshold = 0.79
                    }
                }
                
                Section("Notes") {
                    Text("This setting affects new theme normalization during extraction and discovery.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
