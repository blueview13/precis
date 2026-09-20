import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "newspaper")
                .font(.system(size: 48))
                .foregroundStyle(.accent)

            Text("Precis")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Native macOS reading for focused feeds and quiet AI summaries.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
    }
}

#Preview {
    ContentView()
}
