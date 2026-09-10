import SwiftUI
import WebKit

struct LoginWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var networkManager: NetworkManager
    var onLoginSuccess: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LoginWebView

        init(_ parent: LoginWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let currentURL = webView.url?.absoluteString else { return }
            
            // Check if we reached the main timetable page after successful auth
            if currentURL.contains("timetable") && !currentURL.contains("login") {
                parent.networkManager.saveCookies(from: webView) {
                    self.parent.onLoginSuccess()
                }
            }
        }
    }
}
