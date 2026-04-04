import SwiftUI
import DesignSystem

/// Launch screen with 3-second animation
public struct LaunchView: View {
    @Binding var isCompleted: Bool
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0.0
    @State private var isSymbolAnimating = false
    
    public init(isCompleted: Binding<Bool>) {
        self._isCompleted = isCompleted
    }
    
    public var body: some View {
        ZStack {
            Color.accent
                .ignoresSafeArea()
            
            VStack(spacing: Spacing.large) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 96, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.heroGold, Color.heroCoral)
                    .symbolEffect(.pulse, options: .repeating, value: isSymbolAnimating)
                    .scaleEffect(scale)
                    .opacity(opacity)
                
                Text(appLocalized("Alike"))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(opacity)
            }
        }
        .task {
            isSymbolAnimating = true

            // Animate in
            withAnimation(.appBouncy.delay(0.1)) {
                scale = 1.0
                opacity = 1.0
            }
            
            // Wait 3 seconds
            try? await Task.sleep(for: .seconds(3))
            
            // Animate out
            withAnimation(.appSmooth) {
                scale = 1.2
                opacity = 0.0
            }
            
            // Small delay for animation to complete
            try? await Task.sleep(for: .milliseconds(300))
            
            isCompleted = true
        }
    }
}

// MARK: - Preview
#Preview("Launch") {
    LaunchView(isCompleted: .constant(false))
}
