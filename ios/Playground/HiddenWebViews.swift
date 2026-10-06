import WebKit

/// Runs each script in its own off-screen WKWebView. Every web view stays alive until `close()`,
/// so a batch measures N live web views at once.
@MainActor
final class HiddenWebViews: NSObject {
    private static let timeout = Duration.seconds(120)
    private static let consoleBridge = """
        for (const level of ["log", "info", "debug", "warn", "error"]) {
          const prefix = level === "warn" || level === "error" ? `[${level}] ` : "";
          console[level] = (...args) =>
            window.webkit.messageHandlers.console.postMessage(prefix + args.map(String).join(" "));
        }
        """

    private struct Worker {
        let source: String
        let done: CheckedContinuation<String?, Never>
    }

    private let configuration = WKWebViewConfiguration()
    private let console: ConsoleListener
    private var webViews: [WKWebView] = []
    private var running: [ObjectIdentifier: Worker] = [:]

    init(console: ConsoleListener) {
        self.console = console
        super.init()
        let scripts = configuration.userContentController
        scripts.addUserScript(WKUserScript(source: Self.consoleBridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        scripts.add(self, name: "console")
    }

    /// Returns the error that stopped the script, or nil once it finished.
    func run(_ source: String) async -> String? {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webViews.append(webView)
        return await withCheckedContinuation { done in
            running[ObjectIdentifier(webView)] = Worker(source: source, done: done)
            webView.loadHTMLString("<!doctype html>", baseURL: nil)
            Task { [weak self, weak webView] in
                try? await Task.sleep(for: Self.timeout)
                guard let self, let webView else { return }
                finish(webView, error: "timed out after \(Self.timeout)")
            }
        }
    }

    /// Footprint of the WebContent processes behind the live web views, or nil where iOS hides them.
    func webContentFootprint() -> UInt64? {
        // WebKit has no public API for a web view's process; `_webProcessIdentifier` is its long-standing SPI.
        let pids = Set(webViews.compactMap { $0.value(forKey: "_webProcessIdentifier") as? pid_t }.filter { $0 > 0 })
        var total: UInt64 = 0
        for pid in pids {
            guard let footprint = AppMemory.footprint(of: pid) else { return nil }
            total += footprint
        }
        return total
    }

    func close() {
        configuration.userContentController.removeScriptMessageHandler(forName: "console")
        webViews.removeAll()
    }

    private func finish(_ webView: WKWebView, error: String?) {
        running.removeValue(forKey: ObjectIdentifier(webView))?.done.resume(returning: error)
    }
}

extension HiddenWebViews: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let source = running[ObjectIdentifier(webView)]?.source else { return }
        webView.callAsyncJavaScript(source, in: nil, in: .page) { result in
            if case .failure(let error) = result {
                self.finish(webView, error: error.localizedDescription)
            } else {
                self.finish(webView, error: nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(webView, error: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(webView, error: error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(webView, error: "web content process terminated")
    }
}

extension HiddenWebViews: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let line = message.body as? String {
            console.onLine(line: line)
        }
    }
}
