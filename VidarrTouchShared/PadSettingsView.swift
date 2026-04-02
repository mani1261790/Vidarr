import SwiftUI

struct PadSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var homePageURL = PadBrowserPreferences.shared.homePageURLString
    @State private var searchTemplate = PadBrowserPreferences.shared.searchTemplate
    @State private var preferredLanguage = PadBrowserPreferences.shared.preferredContentLanguage

    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("スタートページ") {
                    TextField("", text: $homePageURL, prompt: Text("Vidarr Start"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("空欄にすると Vidarr Start を開きます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("検索するときのURL") {
                    TextField("https://search.fenrir-inc.com/?q={query}", text: $searchTemplate)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("{query} が検索語に置き換わります。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Webページの表示言語") {
                    Picker("言語", selection: $preferredLanguage) {
                        ForEach(PadPreferredContentLanguage.allCases, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        PadBrowserPreferences.shared.homePageURLString = homePageURL
                        PadBrowserPreferences.shared.searchTemplate = searchTemplate
                        PadBrowserPreferences.shared.preferredContentLanguage = preferredLanguage
                        onSave()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        let trimmedSearch = searchTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty, trimmedSearch.contains("{query}") else { return false }
        let probe = trimmedSearch.replacingOccurrences(of: "{query}", with: "vidarr")
        guard let searchURL = URL(string: probe), let searchScheme = searchURL.scheme?.lowercased(), searchScheme == "http" || searchScheme == "https" else {
            return false
        }
        let trimmedHome = homePageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHome.isEmpty else { return true }
        guard let homeURL = URL(string: trimmedHome), let homeScheme = homeURL.scheme?.lowercased() else { return false }
        return homeScheme == "http" || homeScheme == "https"
    }
}
