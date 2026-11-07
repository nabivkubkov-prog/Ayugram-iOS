import UIKit
import SGSimpleSettings

/// Covers application content during capture and before app-switcher snapshots.
/// UIKit cannot prevent an ordinary screenshot; capture notifications are asynchronous.
final class AyuCaptureShield {
    private let mainWindow: () -> UIWindow?
    private var shieldWindow: UIWindow?
    private var observers: [NSObjectProtocol] = []
    private var isActive = false

    init(mainWindow: @escaping () -> UIWindow?) {
        self.mainWindow = mainWindow
    }

    func start() {
        guard observers.isEmpty else { return }
        isActive = UIApplication.shared.applicationState == .active
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.update()
        })
        observers.append(center.addObserver(forName: .ayuAppearanceChanged, object: nil, queue: .main) { [weak self] _ in
            self?.update()
        })
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isActive = false
            self?.update()
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isActive = true
            self?.update()
        })
        update()
    }

    private func update() {
        guard let host = mainWindow() else { return }
        let shouldCover = AyuAppearanceSettings.shared.streamerMode && (!isActive || host.screen.isCaptured)
        guard shouldCover else {
            shieldWindow?.isHidden = true
            shieldWindow = nil
            return
        }
        if shieldWindow == nil {
            host.endEditing(true)
            let window: UIWindow
            if let scene = host.windowScene {
                window = UIWindow(windowScene: scene)
            } else {
                window = UIWindow(frame: host.screen.bounds)
            }
            window.frame = host.frame
            window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 100.0)
            window.rootViewController = AyuCaptureShieldController()
            window.isHidden = false
            shieldWindow = window
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}

private final class AyuCaptureShieldController: UIViewController {
    override var prefersStatusBarHidden: Bool { return true }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.08, alpha: 1.0)
        view.accessibilityViewIsModal = true
        let label = UILabel()
        let russian = Locale.preferredLanguages.first?.hasPrefix("ru") == true
        label.text = russian ? "AyuGram\nРежим стримера\n\nОстановите запись или трансляцию экрана, чтобы вернуться в приложение." : "AyuGram\nStreamer mode\n\nStop screen recording or mirroring to return to the app."
        label.textColor = .white
        label.font = .systemFont(ofSize: 19.0, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32.0),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32.0)
        ])
        self.view = view
    }
}
