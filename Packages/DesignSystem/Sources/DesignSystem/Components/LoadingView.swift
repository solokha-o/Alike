import SwiftUI

/// Loading indicator with text
public struct LoadingView: View {
    let message: LocalizedStringKey
    let progress: Double?
    
    public init(
        message: LocalizedStringKey,
        progress: Double? = nil
    ) {
        self.message = message
        self.progress = progress
    }
    
    public var body: some View {
        VStack(spacing: Spacing.large) {
            if let progress {
                ProgressView(value: progress) {
                    Text(message)
                        .font(.appHeadline)
                        .foregroundColor(.secondary)
                }
                .progressViewStyle(.linear)
                .tint(.accent)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.accent)
                
                Text(message)
                    .font(.appHeadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(Spacing.xLarge)
    }
}

#Preview {
    VStack {
        LoadingView(message: "Analyzing photos...")
        LoadingView(message: "Processing...", progress: 0.65)
    }
}
