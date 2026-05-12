import UIKit
import HotwireNative
import WebKit

private let appBackgroundColor = UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1)

final class ApplicationWebViewController: VisitableViewController {

    let customVisitableURL: URL

    override init(url: URL) {
        self.customVisitableURL = url
        super.init(url: url)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Title

    // Bloqueia a propagação do <title> HTML para o tabBarItem da aba
    override var title: String? {
        get { "" }
        set { /* no-op intencional */ }
    }

    // MARK: - Status bar

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - Progress bar (2px, substitui o spinner nativo)

    private lazy var progressBar: UIProgressView = {
        let bar = UIProgressView(progressViewStyle: .bar)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.trackTintColor = UIColor.white.withAlphaComponent(0.12)
        bar.progressTintColor = UIColor(red: 0.91, green: 0.22, blue: 0.35, alpha: 1)
        bar.isHidden = true
        return bar
    }()

    private var progressObservation: NSKeyValueObservation?
    private var apnsTokenObserver: NSObjectProtocol?
    private var apnsTokenRegistered = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = appBackgroundColor

        title = ""
        navigationItem.title = ""

        edgesForExtendedLayout = [.all]
        extendedLayoutIncludesOpaqueBars = true

        setupProgressBar()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        setNeedsStatusBarAppearanceUpdate()
        updateTabBarVisibility()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    // MARK: - VisitableViewController

    // Spinner nativo completamente bloqueado — progress bar é o único indicador
    override func showVisitableActivityIndicator() {}
    override func hideVisitableActivityIndicator() {}

    override func visitableDidActivateWebView(_ webView: WKWebView) {
        super.visitableDidActivateWebView(webView)

        webView.isOpaque = false
        webView.backgroundColor = appBackgroundColor
        webView.scrollView.backgroundColor = appBackgroundColor
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.bounces = false

        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.setProgress(webView.estimatedProgress)
            }
        }
    }

    override func visitableDidDeactivateWebView() {
        progressObservation = nil
        super.visitableDidDeactivateWebView()
    }

    override func visitableDidRender() {
        super.visitableDidRender()
        finishProgress()
        updateTabBarVisibility()
        registerAPNSTokenIfNeeded()
    }

    // MARK: - APNs token registration

    private static let apnsEndpoint = URL(string: "https://geomatch-cvtv.onrender.com/push_subscriptions/apns")!

    private let authenticatedPaths = ["/lead", "/discover_3d", "/notifications", "/matches", "/meu-perfil"]

    private func registerAPNSTokenIfNeeded() {
        guard !apnsTokenRegistered else { return }

        // Só tenta em rotas autenticadas — garante que o cookie de sessão Rails existe
        guard authenticatedPaths.contains(where: { customVisitableURL.path.hasPrefix($0) }) else { return }

        if let token = AppDelegate.apnsToken {
            sendAPNSToken(token)
        } else {
            // Token APNs ainda não chegou; aguarda e tenta quando chegar
            apnsTokenObserver = NotificationCenter.default.addObserver(
                forName: .apnsTokenReady, object: nil, queue: .main
            ) { [weak self] notification in
                guard let self, let token = notification.object as? String else { return }
                // Só envia se ainda estiver numa rota autenticada
                guard self.authenticatedPaths.contains(where: { self.customVisitableURL.path.hasPrefix($0) }) else { return }
                self.sendAPNSToken(token)
                if let obs = self.apnsTokenObserver {
                    NotificationCenter.default.removeObserver(obs)
                    self.apnsTokenObserver = nil
                }
            }
        }
    }

    private func sendAPNSToken(_ token: String) {
        guard !apnsTokenRegistered else { return }

        // 1. Lê o CSRF token do DOM da WebView
        visitableView.webView?.evaluateJavaScript(
            "document.querySelector('meta[name=\"csrf-token\"]')?.content ?? ''"
        ) { [weak self] result, _ in
            guard let self,
                  let csrf = result as? String, !csrf.isEmpty else {
                print("⚠️ [APNs] CSRF não encontrado — tentará novamente na próxima página autenticada")
                return
            }

            // 2. Extrai cookies da WKWebsiteDataStore compartilhada e envia via URLSession
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                self.postTokenToServer(token, csrf: csrf, cookies: cookies)
            }
        }
    }

    private func postTokenToServer(_ token: String, csrf: String, cookies: [HTTPCookie]) {
        var request = URLRequest(url: Self.apnsEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")

        // Injeta os cookies de sessão do Rails na requisição nativa
        HTTPCookie.requestHeaderFields(with: cookies).forEach {
            request.setValue($0.value, forHTTPHeaderField: $0.key)
        }

        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["device_token": token, "platform": "ios"]
        )

        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                switch status {
                case 200, 201, 204:
                    self?.apnsTokenRegistered = true
                    print("✅ [APNs] Token registrado com sucesso (HTTP \(status))")
                case 401, 403:
                    // Não autenticado — apnsTokenRegistered permanece false e
                    // registerAPNSTokenIfNeeded() será chamado novamente na próxima
                    // página autenticada via visitableDidRender()
                    print("⚠️ [APNs] Não autenticado (HTTP \(status)) — aguardando login para retentar")
                default:
                    print("⚠️ [APNs] Falha ao registrar token (HTTP \(status)) — tentará novamente")
                }
            }
        }.resume()
    }

    private func updateTabBarVisibility() {
        let js = """
        (function() {
            var path = window.location.pathname;
            var hasPassword = document.querySelector('input[type="password"]') !== null;
            var isLandingPage = document.querySelector('a[href*="sign_in"]') !== null || document.querySelector('a[href*="sign_up"]') !== null;
            var shouldHide = false;
            if (path === '/' && isLandingPage) {
                shouldHide = true;
            } else if ((path.includes('sign_in') || path.includes('sign_up') || path.includes('password')) && hasPassword) {
                shouldHide = true;
            }
            return { path: path, hasPassword: hasPassword, shouldHide: shouldHide };
        })();
        """
        self.visitableView.webView?.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self,
                  let dict = result as? [String: Any],
                  let path = dict["path"] as? String,
                  let hasPassword = dict["hasPassword"] as? Bool,
                  let shouldHide = dict["shouldHide"] as? Bool else { return }
            DispatchQueue.main.async {
                guard let tabBar = self.tabBarController?.tabBar else { return }
                print("🚨 [JS DEBUG] URL: \(path) | Tem Senha? \(hasPassword) | Ocultar? \(shouldHide)")

                if shouldHide {
                    // Só oculta se esta for a aba ativa — evita que background esconda a barra
                    guard self.tabBarController?.selectedViewController == self.navigationController else {
                        print("🚨 [JS DEBUG] Aba no background tentou OCULTAR a barra. Bloqueado.")
                        return
                    }
                    if !tabBar.isHidden {
                        tabBar.isHidden = true
                        self.view.setNeedsLayout()
                        self.view.layoutIfNeeded()
                    }
                } else {
                    // Qualquer aba pode MOSTRAR a barra — revelar é sempre seguro
                    if tabBar.isHidden {
                        tabBar.isHidden = false
                        self.view.setNeedsLayout()
                        self.view.layoutIfNeeded()
                    }
                }
            }
        }
    }

    // MARK: - Progress bar

    private func setupProgressBar() {
        view.addSubview(progressBar)
        view.bringSubviewToFront(progressBar)
        NSLayoutConstraint.activate([
            progressBar.topAnchor.constraint(equalTo: view.topAnchor),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2),
        ])
    }

    private func setProgress(_ progress: Double) {
        let value = Float(progress)
        if progressBar.isHidden {
            progressBar.setProgress(0.05, animated: false)
            progressBar.isHidden = false
        }
        progressBar.setProgress(value, animated: true)
        if value >= 1.0 { finishProgress() }
    }

    private func finishProgress() {
        UIView.animate(withDuration: 0.25, delay: 0.1, options: .curveEaseOut) {
            self.progressBar.alpha = 0
        } completion: { _ in
            self.progressBar.isHidden = true
            self.progressBar.alpha = 1
            self.progressBar.setProgress(0, animated: false)
        }
    }
}
