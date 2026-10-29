import SwiftUI
import UIKit

/// Items for `.sheet(item:)`.
struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// UIActivityViewController: Save to Files / AirDrop / mail / Zalo (S3 §6.6 "Lấy log ra").
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
