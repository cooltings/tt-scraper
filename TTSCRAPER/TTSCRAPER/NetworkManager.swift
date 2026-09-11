import Foundation
import WebKit
import Combine

class NetworkManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var needsReauth: Bool = false
    
    private let targetURL = URL(string: "https://intranet.psc.ac.uk/timetable")!
    private let cookieKey = "SavedAppCookies"
    
    init() {
        // Check if we have saved cookies on startup
        if loadCookies() {
            self.isAuthenticated = true
        }
    }
    
    // Save cookies from WKWebView to UserDefaults
    func saveCookies(from webView: WKWebView, completion: @escaping () -> Void) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let cookieDataArray = cookies.compactMap { cookie -> [HTTPCookiePropertyKey: Any]? in
                cookie.properties
            }
            UserDefaults.standard.set(cookieDataArray, forKey: self.cookieKey)
            
            // Sync with shared HTTPCookieStorage for URLSession
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
            
            DispatchQueue.main.async {
                self.isAuthenticated = true
                self.needsReauth = false
                completion()
            }
        }
    }
    
    // Load stored cookies into HTTPCookieStorage
    func loadCookies() -> Bool {
        guard let cookieProperties = UserDefaults.standard.array(forKey: cookieKey) as? [[HTTPCookiePropertyKey: Any]] else {
            return false
        }
        
        var hasCookies = false
        for props in cookieProperties {
            if let cookie = HTTPCookie(properties: props) {
                HTTPCookieStorage.shared.setCookie(cookie)
                hasCookies = true
            }
        }
        return hasCookies
    }
    
    // Perform background timetable fetch
    func fetchTimetable(week: Int? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        var urlString = targetURL.absoluteString
        if let week = week {
            urlString += "?week=\(week)"
        }
        
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                completion(.failure(NSError(domain: "DataError", code: -1, userInfo: nil)))
                return
            }
            
            // Inspect HTML to see if session expired and redirected to login page
            if html.lowercased().contains("login") || html.contains("Sign In") || html.contains("type=\"password\"") {
                DispatchQueue.main.async {
                    self?.isAuthenticated = false
                }
                completion(.failure(NSError(domain: "AuthError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Session expired"])))
            } else {
                DispatchQueue.main.async {
                    self?.isAuthenticated = true
                }
                completion(.success(html))
            }
        }.resume()
    }
    
    // Detects if redirection occurred or login form is present
    private func isSessionExpired(response: HTTPURLResponse, html: String) -> Bool {
        // 1. Check HTTP Status Code
        if response.statusCode == 401 || response.statusCode == 403 {
            return true
        }
        
        // 2. Check if redirected to a login page URL
        if let finalURL = response.url?.absoluteString, finalURL.contains("login") || finalURL.contains("sso") {
            return true
        }
        
        // 3. Check HTML content for SSO/Login indicators
        if html.contains("Sign in to your account") || html.contains("name=\"loginform\"") {
            return true
        }
        
        return false
    }
    
    func logout() {
        UserDefaults.standard.removeObject(forKey: cookieKey)
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date.distantPast) {
            DispatchQueue.main.async {
                self.isAuthenticated = false
                self.needsReauth = false
            }
        }
    }
}
