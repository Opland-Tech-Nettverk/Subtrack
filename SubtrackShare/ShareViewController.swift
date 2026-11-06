import SwiftUI
import UIKit

/// Hovedklassen til delingsutvidelsen (`NSExtensionPrincipalClass`). Vertskap for SwiftUI-skjermen.
/// Utvidelsen åpner aldri databasen og lagrer aldri bildet eller PDF-en: den henter ut teksten og legger den
/// som en fil i innboksen i App Group-mappen, som appen leser neste gang den blir aktiv.
final class ShareViewController: UIViewController {
    private var model: ShareViewModel?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Sveip ned mens kvitteringen leses: da kommer verken Ferdig eller Avbryt.
        model?.cancelIfReading()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        let model = ShareViewModel(
            providers: providers,
            finish: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            },
            cancelRequest: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            }
        )

        self.model = model
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }
}
