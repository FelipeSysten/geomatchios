import UIKit
import HotwireNative
import WebKit
import SafariServices

// MARK: - Constants

private let appBackgroundColor = UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1)
private let accentColor        = UIColor(red: 0.91, green: 0.22, blue: 0.35, alpha: 1)

private let unauthPaths = ["/users/sign_in", "/users/sign_up", "/users/password", "/users/auth"]

// MARK: - SceneDelegate

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    // UITabBarController is ALWAYS the root — never swapped out.
    // Login is a fullscreen modal presented on top of it.
    private var tabBarController: UITabBarController!
    private var tabSessions: [Session] = []
    private var authSession: Session?

    private struct TabConfig {
        let path: String; let title: String; let icon: String; let customImageName: String?
        init(path: String, title: String, icon: String, customImageName: String? = nil) {
            self.path = path; self.title = title; self.icon = icon; self.customImageName = customImageName
        }
    }

    private let tabConfigs: [TabConfig] = [
        TabConfig(path: "/lead",          title: "Início",    icon: "house.fill",  customImageName: "geomatch-vazada"),
        TabConfig(path: "/discover_3d",   title: "Encontrar", icon: "map.fill"),
        TabConfig(path: "/notifications", title: "Curtidas",  icon: "heart.fill"),
        TabConfig(path: "/matches",       title: "Mensagens", icon: "message.fill"),
        TabConfig(path: "/meu-perfil",    title: "Perfil",    icon: "person.fill"),
    ]

    // MARK: - UIWindowSceneDelegate

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        Hotwire.loadPathConfiguration(from: [
            .file(Bundle.main.url(forResource: "path-configuration", withExtension: "json")!),
            .server(AppConfiguration.serverURL.appendingPathComponent("/configurations/ios_v1.json"))
        ])
        guard let windowScene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: windowScene)
        window?.backgroundColor = appBackgroundColor

        tabBarController = buildTabBarController()
        window?.rootViewController = tabBarController
        window?.makeKeyAndVisible()

        // Present login modal on top — tab bar is always underneath
        presentLoginModal(animated: false)
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {}
    func sceneDidEnterBackground(_ scene: UIScene) {}

    // MARK: - Login Modal

    private func presentLoginModal(animated: Bool) {
        authSession = nil

        let session = makeSession()
        authSession = session

        let signInURL = AppConfiguration.serverURL.appendingPathComponent("users/sign_in")
        let vc  = ApplicationWebViewController(url: signInURL)
        let nav = UINavigationController(rootViewController: vc)
        nav.setNavigationBarHidden(true, animated: false)
        nav.view.backgroundColor = appBackgroundColor
        nav.modalPresentationStyle = .fullScreen   // covers tab bar completely
        nav.modalTransitionStyle   = .crossDissolve

        if let existing = tabBarController.presentedViewController {
            existing.dismiss(animated: false) {
                self.tabBarController.present(nav, animated: animated)
            }
        } else {
            tabBarController.present(nav, animated: animated)
        }

        session.visit(vc)
    }

    // MARK: - Tab bar factory

    private func buildTabBarController() -> UITabBarController {
        let navs = tabConfigs.map { makeTabNav(config: $0) }
        let tbc  = UITabBarController()
        tbc.viewControllers = navs
        applyTabBarAppearance(to: tbc.tabBar)
        return tbc
    }

    private func makeTabNav(config: TabConfig) -> UINavigationController {
        let path = config.path.hasPrefix("/") ? String(config.path.dropFirst()) : config.path
        let url  = AppConfiguration.serverURL.appendingPathComponent(path)

        let tabImage: UIImage?
        if let name = config.customImageName, let asset = UIImage(named: name) {
            tabImage = asset.withRenderingMode(.alwaysTemplate)
        } else {
            tabImage = UIImage(systemName: config.icon)
        }

        let vc  = ApplicationWebViewController(url: url)
        let nav = UINavigationController(rootViewController: vc)
        nav.setNavigationBarHidden(true, animated: false)
        nav.view.backgroundColor = appBackgroundColor
        nav.tabBarItem = UITabBarItem(title: config.title, image: tabImage, selectedImage: tabImage)

        let session = makeSession()
        tabSessions.append(session)
        session.visit(vc)
        return nav
    }

    // MARK: - Session factory

    private func makeSession() -> Session {
        let session = Session(webViewConfiguration: AppConfiguration.makeWebViewConfiguration())
        session.delegate = self
        return session
    }

    // MARK: - Tab bar appearance

    private func applyTabBarAppearance(to tabBar: UITabBar) {
        let font = UIFont.systemFont(ofSize: 10, weight: .medium)
        let normalAttrs:   [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.lightGray]
        let selectedAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: accentColor]

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = appBackgroundColor

        for layout in [appearance.stackedLayoutAppearance,
                       appearance.inlineLayoutAppearance,
                       appearance.compactInlineLayoutAppearance] {
            layout.normal.iconColor             = .lightGray
            layout.normal.titleTextAttributes   = normalAttrs
            layout.selected.iconColor           = accentColor
            layout.selected.titleTextAttributes = selectedAttrs
        }

        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) { tabBar.scrollEdgeAppearance = appearance }
        tabBar.tintColor               = accentColor
        tabBar.unselectedItemTintColor = .lightGray
    }

    // MARK: - Helpers

    private func isUnauthURL(_ url: URL) -> Bool {
        unauthPaths.contains(where: { url.path.hasPrefix($0) })
    }

    private func navController(for session: Session) -> UINavigationController? {
        guard let index = tabSessions.firstIndex(where: { $0 === session }) else { return nil }
        return tabBarController?.viewControllers?[index] as? UINavigationController
    }

    private func isGoogleOAuthURL(_ url: URL) -> Bool {
        url.host?.contains("accounts.google.com") == true
    }

    private func openGoogleOAuth(_ url: URL) {
        let safari = SFSafariViewController(url: url)
        safari.preferredBarTintColor     = appBackgroundColor
        safari.preferredControlTintColor = accentColor
        safari.delegate = self
        // Present over login modal if it's up, otherwise over tab bar
        let presenter = tabBarController.presentedViewController ?? tabBarController
        presenter?.present(safari, animated: true)
    }
}

// MARK: - SessionDelegate

extension SceneDelegate: SessionDelegate {

    func session(_ session: HotwireNative.Session,
                 decidePolicyFor navigationAction: WKNavigationAction) -> HotwireNative.WebViewPolicyManager.Decision {
        guard let url = navigationAction.request.url else { return .allow }
        if isGoogleOAuthURL(url) {
            DispatchQueue.main.async { self.openGoogleOAuth(url) }
            return .cancel
        }
        if url.host != AppConfiguration.serverURL.host {
            UIApplication.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func session(_ session: HotwireNative.Session, didProposeVisitToCrossOriginRedirect location: URL) {
        if isGoogleOAuthURL(location) { openGoogleOAuth(location) }
        else { UIApplication.shared.open(location) }
    }

    func sessionDidLoadWebView(_ session: Session) {}

    func session(_ session: Session, didProposeVisit proposal: VisitProposal) {
        // ── Auth session (login modal) ───────────────────────────────────────
        if session === authSession {
            // Authenticated URL → dismiss modal, hand the proposal to the first tab session
            if !isUnauthURL(proposal.url) {
                authSession = nil
                tabBarController.dismiss(animated: true) {
                    // Find the tab whose session should handle this URL, defaulting to tab 0
                    let targetSession = self.tabSessions.first
                    guard let nav = self.tabBarController.viewControllers?.first as? UINavigationController,
                          let ts = targetSession else {
                        self.tabSessions.forEach { $0.reload() }
                        return
                    }
                    let vc = ApplicationWebViewController(url: proposal.url)
                    nav.setViewControllers([vc], animated: false)
                    ts.visit(vc)
                }
                return
            }

            // Navigate within login flow (sign_up, forgot password, etc.)
            guard let loginNav = tabBarController.presentedViewController as? UINavigationController else { return }

            let vc           = ApplicationWebViewController(url: proposal.url)
            let context      = proposal.properties["context"]      as? String ?? "default"
            let presentation = proposal.properties["presentation"] as? String ?? "default"

            if context == "modal" {
                let modalNav = UINavigationController(rootViewController: vc)
                modalNav.setNavigationBarHidden(true, animated: false)
                modalNav.view.backgroundColor = appBackgroundColor
                loginNav.present(modalNav, animated: true)
            } else if presentation == "replace" {
                loginNav.setViewControllers([vc], animated: false)
            } else {
                loginNav.pushViewController(vc, animated: true)
            }
            session.visit(vc)
            return
        }

        // ── Tab sessions ─────────────────────────────────────────────────────
        if isUnauthURL(proposal.url) {
            // Logout → show login modal again
            presentLoginModal(animated: true)
            return
        }

        guard let nav = navController(for: session) else { return }

        let context      = proposal.properties["context"]      as? String ?? "default"
        let presentation = proposal.properties["presentation"] as? String ?? "default"
        let vc = ApplicationWebViewController(url: proposal.url)

        if context == "modal" {
            let modalNav = UINavigationController(rootViewController: vc)
            modalNav.setNavigationBarHidden(true, animated: false)
            modalNav.view.backgroundColor = appBackgroundColor
            nav.present(modalNav, animated: true)
            session.visit(vc)
        } else if presentation == "replace" {
            nav.setViewControllers([vc], animated: false)
            session.visit(vc)
        } else {
            nav.pushViewController(vc, animated: true)
            session.visit(vc)
        }
    }

    func session(_ session: Session, didFailRequestForVisitable visitable: any Visitable, error: Error) {
        print("❌ [SESSION] didFailRequest: \(error.localizedDescription)")
    }

    func sessionWebViewProcessDidTerminate(_ session: Session) {
        session.reload()
    }
}

// MARK: - SFSafariViewControllerDelegate

extension SceneDelegate: SFSafariViewControllerDelegate {
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        tabSessions.forEach { $0.reload() }
        authSession?.reload()
    }
}
