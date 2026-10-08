import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(FileStore.self) private var store
    @Environment(\.requestReview) private var requestReview
    @State private var confirmDelete = false
    private let ads = AdsManager.shared

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("100% on-device").font(.headline)
                            Text("Your documents are processed on your iPhone and are never uploaded. The app is free and shows ads.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                    }
                }

                if ads.privacyOptionsRequired {
                    Section {
                        Button("Ad privacy choices") { ads.showPrivacyOptions() }
                    } footer: {
                        Text("Change whether ads may use your data.")
                    }
                }

                Section("Storage") {
                    LabeledContent("Files", value: "\(store.files.count)")
                    LabeledContent("Space used", value: store.totalSize.formattedFileSize)
                    Button("Delete all files", role: .destructive) { confirmDelete = true }
                        .disabled(store.files.isEmpty)
                }

                Section("About") {
                    Button("Rate PDF Studio") { requestReview() }
                    LabeledContent("Version", value: version)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all files in My Files?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) { store.deleteAll() }
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}
