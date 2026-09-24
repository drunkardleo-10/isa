import SwiftUI

struct FindBarOverlay: View {
    @ObservedObject var tab: Tab

    var body: some View {
        ZStack {
            if tab.isFindPresented {
                FindBarView(findState: tab.findState)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
                    .zIndex(50)
            }
        }
        .animation(.easeOut(duration: 0.18), value: tab.isFindPresented)
    }
}
