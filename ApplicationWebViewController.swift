import UIKit
import HotwireNative
import WebKit

private let appBackgroundColor = UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1)

final class ApplicationWebViewController: VisitableViewController {

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
        navigationController?.setNavigationBarHidden(true, animated: false)
        setNeedsStatusBarAppearanceUpdate()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
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
