import SwiftUI

/// Retains a resizable split at desktop widths and a back stack when space is limited.
struct NotebookSplitLayout<Sidebar: View, Detail: View>: View {
    @Binding var showDetail: Bool
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail
    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 960 {
                HSplitView {
                    sidebar().frame(minWidth: 260, idealWidth: 300, maxWidth: 350)
                    detail().frame(minWidth: 440, maxWidth: .infinity)
                }
            } else if showDetail {
                VStack(spacing: 0) {
                    HStack {
                        Button { showDetail = false } label: { Label("Danh sách", systemImage: "chevron.left") }
                            .buttonStyle(TransToolsActionButtonStyle(height: 30))
                        Spacer()
                    }.padding(10).background(TransToolsTheme.mint.opacity(0.45))
                    detail()
                }
            } else {
                sidebar().frame(maxWidth: .infinity)
            }
        }
    }
}
