import Foundation
import WebKit

enum BrowserDataCleaner {
    static func clearPersistentBrowsingData(completion: @escaping (Result<Void, Error>) -> Void) {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
            dataStore.removeData(ofTypes: dataTypes, for: records) {
                URLCache.shared.removeAllCachedResponses()
                HTTPCookieStorage.shared.removeCookies(since: .distantPast)
                BrowsingHistoryStore.shared.clear()
                BookmarkStore.shared.clear()
                DownloadStore.shared.clear()
                MediaPermissionStore.shared.clear()
                BrowserPreferences.shared.contentBlockingDisabledHosts = []
                BrowserPreferences.shared.harmfulSiteAllowedHosts = []
                completion(.success(()))
            }
        }
    }
}
