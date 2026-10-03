import SwiftUI
import WebKit

/// Shows the publisher's page unchanged; audio is not scraped or redistributed.
struct PronunciationSourceView: View {
    let url: URL
    let title: String
    let guidance: String
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    @State private var failed = false
    @State private var reloadID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(guidance).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Link("Mở trình duyệt ↗", destination: url)
                Button("Đóng") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
            Text("Nếu trang yêu cầu xác minh hoặc không phát được audio, chọn Mở trình duyệt. App không tự vượt bước xác minh của nguồn.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.bottom, 10)
            Divider()
            if failed {
                HStack {
                    Text("Không tải được trang nguồn. Kiểm tra mạng hoặc mở bằng trình duyệt.")
                    Button("Thử lại") { loading = true; failed = false; reloadID = UUID() }
                }.font(.callout).padding(12)
            }
            PronunciationPublisherPage(url: url, loading: $loading, failed: $failed)
                .id(reloadID)
        }.frame(minWidth: 700, idealWidth: 900, minHeight: 480, idealHeight: 620)
    }
}

private struct PronunciationPublisherPage: NSViewRepresentable {
    let url: URL
    @Binding var loading: Bool
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(loading: $loading, failed: $failed) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.navigationDelegate = nil
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        let loading: Binding<Bool>
        let failed: Binding<Bool>
        init(loading: Binding<Bool>, failed: Binding<Bool>) { self.loading = loading; self.failed = failed }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loading.wrappedValue = false
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
        private func fail(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            loading.wrappedValue = false
            failed.wrappedValue = true
        }
    }
}
