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
