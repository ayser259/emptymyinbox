import SwiftUI

struct FeatureInclusionSettingsView: View {
    @State private var inclusions: [FeatureAccountInclusion] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if inclusions.isEmpty {
                Text("No connected accounts.")
                    .secondaryText()
            } else {
                ForEach(inclusions) { inclusion in
                    Section(inclusion.accountEmail) {
                        Toggle(
                            "Include in Daily Briefing",
                            isOn: bindingForDailyBriefing(email: inclusion.accountEmail)
                        )
                        Toggle(
                            "Include in Newsletter Insights",
                            isOn: bindingForInsights(email: inclusion.accountEmail)
                        )

                        Button {
                            Task {
                                await AccountInclusionStore.shared.setPrimaryNewsletterAddress(accountEmail: inclusion.accountEmail)
                                await load()
                            }
                        } label: {
                            HStack {
                                Text("Set as Newsletter Address")
                                Spacer()
                                if inclusion.isPrimaryNewsletterAddress {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppTheme.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Feature Inclusions")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    private func load() async {
        await AccountInclusionStore.shared.refreshFromConnectedAccounts()
        let loaded = await AccountInclusionStore.shared.allInclusions()
        await MainActor.run {
            inclusions = loaded
            isLoading = false
        }
    }

    private func bindingForDailyBriefing(email: String) -> Binding<Bool> {
        Binding(
            get: {
                inclusions.first(where: { $0.accountEmail.caseInsensitiveCompare(email) == .orderedSame })?.includeInDailyBriefing ?? true
            },
            set: { newValue in
                Task {
                    await AccountInclusionStore.shared.setIncludeInDailyBriefing(accountEmail: email, isIncluded: newValue)
                    await load()
                }
            }
        )
    }

    private func bindingForInsights(email: String) -> Binding<Bool> {
        Binding(
            get: {
                inclusions.first(where: { $0.accountEmail.caseInsensitiveCompare(email) == .orderedSame })?.includeInNewsletterInsights ?? true
            },
            set: { newValue in
                Task {
                    await AccountInclusionStore.shared.setIncludeInNewsletterInsights(accountEmail: email, isIncluded: newValue)
                    await load()
                }
            }
        )
    }
}
