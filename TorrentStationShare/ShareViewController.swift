import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Extract the shared URL from the extension context
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            close()
            return
        }

        Task {
            let url = await extractURL(from: extensionItems)
            await MainActor.run {
                showShareView(sharedURL: url)
            }
        }
    }

    private func extractURL(from items: [NSExtensionItem]) async -> String? {
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                // Try URL type first
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await provider.loadItem(
                        forTypeIdentifier: UTType.url.identifier
                    ) as? URL {
                        return url.absoluteString
                    }
                }
                // Try plain text (for magnet links pasted as text)
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await provider.loadItem(
                        forTypeIdentifier: UTType.plainText.identifier
                    ) as? String {
                        if text.hasPrefix("magnet:") || text.hasPrefix("http://") || text.hasPrefix("https://") {
                            return text
                        }
                    }
                }
            }
        }
        return nil
    }

    private func showShareView(sharedURL: String?) {
        let shareView = ShareView(
            sharedURL: sharedURL ?? "",
            onDismiss: { [weak self] in self?.close() }
        )

        let hostingController = UIHostingController(rootView: shareView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
