import AppKit
import Foundation
import WebKit

@MainActor
final class WebViewManager: NSObject, ObservableObject {
    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    static let antiDetectionScript = """
// 消除 webdriver 检测
Object.defineProperty(navigator, 'webdriver', { get: () => undefined });

// 伪造 plugins
Object.defineProperty(navigator, 'plugins', {
    get: () => {
        const plugins = [
            { name: 'Chrome PDF Plugin', filename: 'internal-pdf-viewer', description: 'Portable Document Format' },
            { name: 'Chrome PDF Viewer', filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai', description: '' },
            { name: 'Native Client', filename: 'internal-nacl-plugin', description: '' }
        ];
        plugins.item = (i) => plugins[i];
        plugins.namedItem = (name) => plugins.find(p => p.name === name);
        plugins.refresh = () => {};
        return plugins;
    }
});

// 伪造 languages
Object.defineProperty(navigator, 'languages', { get: () => ['zh-CN', 'zh', 'en-US', 'en'] });

// 伪造 platform
Object.defineProperty(navigator, 'platform', { get: () => 'Win32' });

// 伪造 vendor
Object.defineProperty(navigator, 'vendor', { get: () => 'Google Inc.' });

// 消除 automation 检测
try {
  delete window.cdc_adoQpoasnfa76pfcZLmcfl_Array;
  delete window.cdc_adoQpoasnfa76pfcZLmcfl_Promise;
  delete window.cdc_adoQpoasnfa76pfcZLmcfl_Symbol;
} catch (e) {}

// 伪造 chrome 对象
window.chrome = { runtime: {}, loadTimes: function() {}, csi: function() {}, app: {} };
"""

    @Published var activeTabId: String = ""
    @Published private(set) var loadingTabs: Set<String> = []
    @Published private(set) var tabProgress: [String: Double] = [:]
    @Published private(set) var tabLoadIssues: [String: TabLoadIssue] = [:]
    @Published private(set) var lastErrorMessage: String?

    private var webviews: [String: WKWebView] = [:]
    private var delegates: [String: NavigationDelegate] = [:]
    private var progressObservers: [String: NSKeyValueObservation] = [:]
    private var timeoutWorkItems: [String: DispatchWorkItem] = [:]

    private let loadTimeoutSeconds: TimeInterval = 15

    func webView(for tabId: String, url: URL) -> WKWebView {
        if let existing = webviews[tabId] {
            return existing
        }

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        let script = WKUserScript(source: Self.antiDetectionScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        controller.addUserScript(script)
        config.userContentController = controller
        config.websiteDataStore = .default()

        let webview = WKWebView(frame: .zero, configuration: config)
        webview.customUserAgent = Self.userAgent
        webview.allowsBackForwardNavigationGestures = true

        let delegate = NavigationDelegate(tabId: tabId, manager: self)
        webview.navigationDelegate = delegate
        webview.uiDelegate = delegate
        delegates[tabId] = delegate
        webviews[tabId] = webview
        progressObservers[tabId] = webview.observe(\.estimatedProgress, options: [.new]) { [weak self] webview, _ in
            guard let self else { return }
            let value = webview.estimatedProgress
            Task { @MainActor in
                self.setProgress(tabId: tabId, progress: value)
            }
        }

        webview.load(URLRequest(url: url))
        return webview
    }

    func hasWebView(tabId: String) -> Bool {
        webviews[tabId] != nil
    }

    func reload(tabId: String) {
        webviews[tabId]?.reload()
    }

    func refreshIfReady(tabId: String) {
        guard let webview = webviews[tabId], !webview.isLoading else { return }
        webview.reload()
    }

    func remove(tabId: String) {
        if let observer = progressObservers[tabId] {
            observer.invalidate()
        }
        progressObservers[tabId] = nil
        cancelTimeout(for: tabId)
        webviews.removeValue(forKey: tabId)
        delegates.removeValue(forKey: tabId)
        loadingTabs.remove(tabId)
        tabProgress.removeValue(forKey: tabId)
        tabLoadIssues.removeValue(forKey: tabId)
    }

    func removeAll(tabIds: [String]) {
        for tabId in tabIds {
            remove(tabId: tabId)
        }
    }

    func evaluateJavaScript(tabId: String, script: String) async throws -> String {
        guard let webview = webviews[tabId] else {
            return ""
        }
        return try await withCheckedThrowingContinuation { continuation in
            webview.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result as? String ?? "")
                }
            }
        }
    }

    func clearWebsiteData(for hosts: [String]) async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let store = WKWebsiteDataStore.default()
        await withCheckedContinuation { continuation in
            store.fetchDataRecords(ofTypes: types) { records in
                let targets = records.filter { record in
                    hosts.contains { host in
                        record.displayName == host || record.displayName.hasSuffix(host) || record.displayName.contains(host)
                    }
                }
                if targets.isEmpty {
                    continuation.resume()
                    return
                }
                store.removeData(ofTypes: types, for: targets) {
                    continuation.resume()
                }
            }
        }
    }

    func setLoading(tabId: String, isLoading: Bool) {
        if isLoading {
            loadingTabs.insert(tabId)
        } else {
            loadingTabs.remove(tabId)
        }
    }

    func setError(message: String?) {
        lastErrorMessage = message
    }

    func markLoadStarted(tabId: String) {
        setLoading(tabId: tabId, isLoading: true)
        setProgress(tabId: tabId, progress: 0)
        tabLoadIssues.removeValue(forKey: tabId)
        scheduleTimeout(for: tabId)
    }

    func markLoadFinished(tabId: String) {
        setLoading(tabId: tabId, isLoading: false)
        setProgress(tabId: tabId, progress: 1)
        tabLoadIssues.removeValue(forKey: tabId)
        cancelTimeout(for: tabId)
    }

    func markLoadFailed(tabId: String) {
        setLoading(tabId: tabId, isLoading: false)
        tabLoadIssues[tabId] = .failed
        cancelTimeout(for: tabId)
    }

    private func setProgress(tabId: String, progress: Double) {
        let clamped = min(max(progress, 0), 1)
        tabProgress[tabId] = clamped
    }

    private func scheduleTimeout(for tabId: String) {
        cancelTimeout(for: tabId)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.loadingTabs.contains(tabId) else { return }
            self.tabLoadIssues[tabId] = .timeout
        }
        timeoutWorkItems[tabId] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + loadTimeoutSeconds, execute: workItem)
    }

    private func cancelTimeout(for tabId: String) {
        timeoutWorkItems[tabId]?.cancel()
        timeoutWorkItems[tabId] = nil
    }

    private final class NavigationDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let tabId: String
        private weak var manager: WebViewManager?

        init(tabId: String, manager: WebViewManager) {
            self.tabId = tabId
            self.manager = manager
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            manager?.markLoadStarted(tabId: tabId)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            manager?.markLoadFinished(tabId: tabId)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            manager?.markLoadFailed(tabId: tabId)
            manager?.setError(message: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            manager?.markLoadFailed(tabId: tabId)
            manager?.setError(message: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let url = navigationAction.request.url else {
                return nil
            }
            NSWorkspace.shared.open(url)
            return nil
        }
    }
}

enum TabLoadIssue: String {
    case failed
    case timeout
}
