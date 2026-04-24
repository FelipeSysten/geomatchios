import WebKit

enum AppConfiguration {
    static let serverURL = URL(string: "https://geomatch-cvtv.onrender.com")!

    // Pool único compartilhado por TODAS as WKWebViews do app.
    // Garante que cookies (incluindo CSRF e sessão Devise) sejam visíveis
    // em qualquer webview, eliminando erros 422.
    static let sharedProcessPool = WKProcessPool()

    static func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.processPool = sharedProcessPool
        config.websiteDataStore = .default()       // store persistente compartilhado
        config.applicationNameForUserAgent = "Turbo Native iOS"
        return config
    }
}
