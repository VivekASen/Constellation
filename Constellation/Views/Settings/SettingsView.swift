//
//  SettingsView.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("theme.semanticMatchThreshold") private var semanticThreshold = 0.79
    @AppStorage("recommend.semanticWeight") private var recommendationSemanticWeight = 0.58
    @AppStorage("recommend.qualityWeight") private var recommendationQualityWeight = 0.28
    @AppStorage("recommend.popularityWeight") private var recommendationPopularityWeight = 0.20
    @AppStorage("recommend.noveltyWeight") private var recommendationNoveltyWeight = 0.10
    @AppStorage("recommend.diversityBalance") private var recommendationDiversityBalance = 0.78
    @AppStorage("recommend.coherenceThreshold") private var recommendationCoherenceThreshold = 0.34
    
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
                
                Section("Recommendation Ranking") {
                    VStack(alignment: .leading, spacing: 10) {
                        weightRow(title: "Semantic", value: recommendationSemanticWeight)
                        Slider(value: $recommendationSemanticWeight, in: 0.10...0.85, step: 0.01)
                        
                        weightRow(title: "Quality", value: recommendationQualityWeight)
                        Slider(value: $recommendationQualityWeight, in: 0.05...0.80, step: 0.01)
                        
                        weightRow(title: "Popularity", value: recommendationPopularityWeight)
                        Slider(value: $recommendationPopularityWeight, in: 0.05...0.80, step: 0.01)
                        
                        weightRow(title: "Novelty", value: recommendationNoveltyWeight)
                        Slider(value: $recommendationNoveltyWeight, in: 0.05...0.60, step: 0.01)
                        
                        weightRow(title: "Diversity Balance", value: recommendationDiversityBalance)
                        Slider(value: $recommendationDiversityBalance, in: 0.40...0.95, step: 0.01)

                        weightRow(title: "Topic Coherence Gate", value: recommendationCoherenceThreshold)
                        Slider(value: $recommendationCoherenceThreshold, in: 0.20...0.80, step: 0.01)
                        
                        Text("Higher semantic weight favors close topical matches. Higher novelty boosts less similar-to-library picks. Diversity balance controls result variety. Topic coherence gate hard-drops off-topic cards.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Button("Reset Recommendation Defaults") {
                        recommendationSemanticWeight = 0.58
                        recommendationQualityWeight = 0.28
                        recommendationPopularityWeight = 0.20
                        recommendationNoveltyWeight = 0.10
                        recommendationDiversityBalance = 0.78
                        recommendationCoherenceThreshold = 0.34
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
    
    @ViewBuilder
    private func weightRow(title: String, value: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(String(format: "%.2f", value))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

#Preview {
    SettingsView()
}
