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
                    TextField("https://search.fenrir-inc.com/", text: $homePageURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                }
            }
        }
    }
}
