//
//  SettingsView.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//

import SwiftUI
import AuthenticationServices
import CloudKit

struct SettingsView: View {
    @AppStorage("theme.semanticMatchThreshold") private var semanticThreshold = 0.79
    @AppStorage("recommend.semanticWeight") private var recommendationSemanticWeight = 0.58
    @AppStorage("recommend.qualityWeight") private var recommendationQualityWeight = 0.28
    @AppStorage("recommend.popularityWeight") private var recommendationPopularityWeight = 0.20
    @AppStorage("recommend.noveltyWeight") private var recommendationNoveltyWeight = 0.10
    @AppStorage("recommend.diversityBalance") private var recommendationDiversityBalance = 0.78
    @AppStorage("recommend.coherenceThreshold") private var recommendationCoherenceThreshold = 0.22
    @AppStorage("recommend.enableTasteDiveBlend") private var enableTasteDiveBlend = false
    @State private var cloudStatusText = "Checking iCloud status..."
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Account & Sync") {
                    SignInWithAppleButton(.signIn, onRequest: { request in
                        request.requestedScopes = [.fullName, .email]
                    }, onCompletion: { _ in })
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 44)

                    HStack {
                        Text("Cloud Sync")
                        Spacer()
                        Text(cloudStatusText)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    Button("Refresh Sync Status") {
                        Task { await refreshCloudAccountStatus() }
                    }

                    Text("Sync uses CloudKit private database in your iCloud account. Your app data is not used for tracking.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

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
                        Slider(value: $recommendationCoherenceThreshold, in: 0.10...0.70, step: 0.01)
                        
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
                        recommendationCoherenceThreshold = 0.22
                    }
                }

                Section("Recommendation Sources") {
                    Toggle("Enable TasteDive Signal Blend", isOn: $enableTasteDiveBlend)
                    Text("When enabled, recommendations blend your personal library profile with TasteDive relationship signals and TMDB ranking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("Notes") {
                    Text("This setting affects new theme normalization during extraction and discovery.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task {
                await refreshCloudAccountStatus()
            }
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

    private func refreshCloudAccountStatus() async {
        let status = await withCheckedContinuation { continuation in
            CKContainer.default().accountStatus { status, _ in
                continuation.resume(returning: status)
            }
        }
        await MainActor.run {
            switch status {
            case .available:
                cloudStatusText = "Connected"
            case .noAccount:
                cloudStatusText = "No iCloud account"
            case .restricted:
                cloudStatusText = "Restricted"
            case .couldNotDetermine:
                cloudStatusText = "Unavailable"
            case .temporarilyUnavailable:
                cloudStatusText = "Temporarily unavailable"
            @unknown default:
                cloudStatusText = "Unknown"
            }
        }
    }
}

#Preview {
    SettingsView()
}
