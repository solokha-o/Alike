import SwiftUI

/// Primary button component
public struct PrimaryButton: View {
    let title: LocalizedStringKey
    let icon: String?
    let action: () -> Void
    
    @State private var feedbackTrigger = 0
    
    public init(
        _ title: LocalizedStringKey,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.action = action
    }
    
    public var body: some View {
        Button {
            feedbackTrigger += 1
            action()
        } label: {
            HStack(spacing: Spacing.small) {
                if let icon {
                    Image(systemName: icon)
                        .font(.appHeadline)
                }
                Text(title)
                    .font(.appHeadline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accent)
            .foregroundColor(.white)
            .cornerRadius(CornerRadius.medium)
        }
        .scaleOnPress()
        .sensoryFeedback(.impact(flexibility: .soft), trigger: feedbackTrigger)
    }
}

/// Secondary button component
public struct SecondaryButton: View {
    let title: LocalizedStringKey
    let icon: String?
    let action: () -> Void
    
    public init(
        _ title: LocalizedStringKey,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.small) {
                if let icon {
                    Image(systemName: icon)
                        .font(.appHeadline)
                }
                Text(title)
                    .font(.appHeadline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.secondaryBackground)
            .foregroundColor(.accent)
            .cornerRadius(CornerRadius.medium)
        }
        .scaleOnPress()
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: Spacing.medium) {
        PrimaryButton("Primary Button", icon: "star.fill") {}
        SecondaryButton("Secondary Button", icon: "gear") {}
    }
    .padding()
}
