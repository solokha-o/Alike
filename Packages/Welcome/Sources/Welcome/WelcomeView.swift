import SwiftUI
import Photos
import DesignSystem

/// Welcome screen with permission handling
public struct WelcomeView: View {
    @State private var viewModel = WelcomeViewModel()
    @Binding var isCompleted: Bool
    
    public init(isCompleted: Binding<Bool>) {
        self._isCompleted = isCompleted
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
        }
    }
    
    // MARK: - Initial State
    private var initialState: some View {
        VStack(spacing: Spacing.xLarge) {
            Spacer()
            
            Text("📸")
                .font(.system(size: 80))
            
            Text("Alike")
                .font(.appLargeTitle)
                .foregroundColor(.accent)
            
            Text("Find visually similar photos in your library")
                .font(.appTitle3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xLarge)
            
            Spacer()
            
            PrimaryButton("Grant Access", icon: "photo.on.rectangle") {
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
            Label("Photo Access Required", systemImage: "photo.on.rectangle.slash")
        } description: {
            Text("Alike needs access to your photo library to find similar photos. Please enable access in Settings.")
        } actions: {
            PrimaryButton("Open Settings", icon: "gear") {
                viewModel.openSettings()
            }
            .padding(.horizontal, Spacing.large)
        }
    }
    
    // MARK: - Authorized State
    private var authorizedState: some View {
        VStack {
            Text("✅")
                .font(.system(size: 80))
            
            Text("Access Granted")
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
    
    return WelcomeView(isCompleted: $isCompleted)
        .environment(viewModel)
}

#Preview("Authorized") {
    @Previewable @State var isCompleted = false
    let mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .authorized)
    let viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
    
    return WelcomeView(isCompleted: $isCompleted)
        .environment(viewModel)
}
