import SwiftUI
import Photos
import DesignSystem

/// Welcome screen with permission handling
public struct WelcomeView: View {
    @State private var viewModel: WelcomeViewModel
    @Binding var isCompleted: Bool
    @State private var isSymbolAnimating = false
    
    public init(isCompleted: Binding<Bool>, viewModel: WelcomeViewModel? = nil) {
        self._isCompleted = isCompleted
        if let viewModel {
            self._viewModel = State(initialValue: viewModel)
        } else {
            self._viewModel = State(initialValue: WelcomeViewModel())
        }
    }
    
    public var body: some View {
        Group {
            switch viewModel.authorizationStatus {
            case .notDetermined:
                initialState
            case .denied, .restricted:
                deniedState
            case .authorized, .limited:
                authorizedState
            @unknown default:
                initialState
            }
        }
        .onAppear {
            viewModel.checkStatus()
            isSymbolAnimating = true
        }
    }
    
    // MARK: - Initial State
    private var initialState: some View {
        VStack(spacing: Spacing.xLarge) {
            Spacer()
            
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 80, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.accent, Color.heroGold, Color.heroCoral)
                .symbolEffect(.bounce, options: .repeating, value: isSymbolAnimating)
            
            Text(appLocalized("Alike"))
                .font(.appLargeTitle)
                .foregroundColor(.accent)
            
            Text(appLocalized("Find visually similar photos in your library"))
                .font(.appTitle3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xLarge)
            
            Spacer()
            
            PrimaryButton(appLocalized("Grant Access"), icon: "photo.on.rectangle") {
                Task {
                    await viewModel.requestPermission()
                }
            }
            .padding(.horizontal, Spacing.large)
            .padding(.bottom, Spacing.xLarge)
        }
        .sensoryFeedback(.success, trigger: viewModel.isAuthorized)
    }
    
    // MARK: - Denied State
    private var deniedState: some View {
        ContentUnavailableView {
            Label {
                Text(appLocalized("Photo Access Required"))
            } icon: {
                Image(systemName: "photo.on.rectangle.slash")
            }
        } description: {
            Text(appLocalized("Alike needs access to your photo library to find similar photos. Please enable access in Settings."))
        } actions: {
            PrimaryButton(appLocalized("Open Settings"), icon: "gear") {
                viewModel.openSettings()
            }
            .padding(.horizontal, Spacing.large)
        }
    }
    
    // MARK: - Authorized State
    private var authorizedState: some View {
        VStack {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.statusReviewed, Color.statusSavings, .white)
                .symbolEffect(.pulse, options: .repeating, value: isSymbolAnimating)
            
            Text(appLocalized("Access Granted"))
                .font(.appTitle)
                .foregroundColor(.accent)
        }
        .task {
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation {
                isCompleted = true
            }
        }
    }
}

// MARK: - Preview
#Preview("Initial") {
    WelcomeView(isCompleted: .constant(false))
}

#Preview("Denied") {
    @Previewable @State var isCompleted = false
    let mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .denied)
    let viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
    
    return WelcomeView(isCompleted: $isCompleted, viewModel: viewModel)
}

#Preview("Authorized") {
    @Previewable @State var isCompleted = false
    let mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .authorized)
    let viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
    
    return WelcomeView(isCompleted: $isCompleted, viewModel: viewModel)
}
