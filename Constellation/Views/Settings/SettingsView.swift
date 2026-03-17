//
//  SettingsView.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("theme.semanticMatchThreshold") private var semanticThreshold = 0.79
    #if DEBUG
    @StateObject private var diagnostics = DebugDiagnostics.shared
    #endif
    
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

                #if DEBUG
                Section("Diagnostics (Debug)") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Theme Backfill")
                            Spacer()
                            Text("\(diagnostics.themeBackfillUpdates)/\(diagnostics.themeBackfillRuns)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.subheadline)

                        HStack {
                            Text("Themes Generated")
                            Spacer()
                            Text("M \(diagnostics.movieThemesGenerated) • TV \(diagnostics.tvThemesGenerated) • B \(diagnostics.bookThemesGenerated)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.footnote)

                        HStack {
                            Text("Poster Requests")
                            Spacer()
                            Text("\(diagnostics.posterRequests)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text("Poster Cache Hits")
                            Spacer()
                            Text("\(diagnostics.posterCacheHits)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text("Poster Retries")
                            Spacer()
                            Text("\(diagnostics.posterRetries)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text("Poster Failures")
                            Spacer()
                            Text("\(diagnostics.posterFailures)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text("Poster Invalid URLs")
                            Spacer()
                            Text("\(diagnostics.posterInvalidURLs)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    Button("Reset Diagnostics") {
                        diagnostics.reset()
                    }
                    .foregroundStyle(.red)
                }
                #endif
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
