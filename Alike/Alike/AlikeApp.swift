//
//  AlikeApp.swift
//  Alike
//
//  Created by Oleksand S on 27.01.2026.
//

import SwiftUI

import SwiftUI
import Launch
import Welcome
import Scanner
import Settings
import Details
import Core
import PhotoAnalysis
import Photos

@main
struct AlikeApp: App {
    @State private var launchCompleted = false
    @State private var welcomeCompleted = false
    @AppStorage("gridColumns") private var gridColumns = GridConfiguration.current.defaultColumns
    @AppStorage("sensitivity") private var sensitivityRaw = SensitivityLevel.medium.rawValue
    @State private var needsRescan = false
    @State private var selectedTab = 0
    @State private var shouldStartScan = false
    
    private let permissionManager = PhotoPermissionManagerImpl()
    
    private var sensitivity: Binding<SensitivityLevel> {
        Binding(
            get: { SensitivityLevel(rawValue: sensitivityRaw) ?? .medium },
            set: { sensitivityRaw = $0.rawValue }
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if !launchCompleted {
                    LaunchView(isCompleted: $launchCompleted)
                } else if !welcomeCompleted {
                    WelcomeView(isCompleted: $welcomeCompleted)
                } else {
                    mainTabView
                }
            }
            .animation(.smooth, value: launchCompleted)
            .animation(.smooth, value: welcomeCompleted)
            .task {
                // Перевіряємо дозвіл одразу при старті
                await checkInitialPermissions()
            }
        }
    }
    
    private func checkInitialPermissions() async {
        // Чекаємо завершення прелоадера
        while !launchCompleted {
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        // Якщо доступ вже є - пропускаємо Welcome екран
        if permissionManager.isAuthorized {
            await MainActor.run {
                welcomeCompleted = true
            }
        }
    }
    
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            ScannerView(
                gridColumns: $gridColumns,
                sensitivity: sensitivity,
                shouldStartScan: $shouldStartScan
            )
            .tabItem {
                Label("Scanner", systemImage: "photo.stack")
            }
            .tag(0)
            
            SettingsView(
                gridColumns: $gridColumns,
                sensitivity: sensitivity,
                needsRescan: $needsRescan
            )
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(1)
        }
        .tint(.accent)
        .alert("Rescan Required", isPresented: $needsRescan) {
            Button("Later", role: .cancel) {
                needsRescan = false
            }
            Button("Rescan Now") {
                needsRescan = false
                selectedTab = 0 // Перейти на Scanner таб
                shouldStartScan = true // Запустити сканування
            }
        } message: {
            Text("Changing sensitivity requires a new scan to take effect")
        }
    }
}
