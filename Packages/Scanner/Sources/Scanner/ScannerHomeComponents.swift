import Cleanup
import DesignSystem
import SwiftUI

private struct ScannerHomeSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
        } else {
            content.background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
            )
        }
    }
}

private extension View {
    func scannerHomeSurface() -> some View {
        modifier(ScannerHomeSurfaceModifier())
    }
}

struct ScannerHomeHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let presentation: ScannerHomePresentation
    let onAction: (ScannerHomeAction) -> Void

    var body: some View {
        VStack(spacing: Spacing.medium) {
            ScannerHeroArtwork(
                cue: presentation.cue,
                maximumWidth: heroWidth
            )
            .equatable()
            .id(presentation.visualPhase)
            .transition(.opacity)

            VStack(spacing: Spacing.xSmall) {
                Text(presentation.title)
                    .font(.appTitle2)
                    .foregroundStyle(.primary)

                Text(presentation.message)
                    .font(.appBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            if let progress = presentation.progress {
                scanProgress(progress)
            }

            actions
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.large)
        .scannerHomeSurface()
        .animation(
            reduceMotion ? nil : .appQuick,
            value: presentation.visualPhase
        )
    }

    private var heroWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 124 : 176
    }

    private func scanProgress(_ progress: Double) -> some View {
        VStack(spacing: Spacing.xSmall) {
            ProgressView(value: progress)
                .tint(Color.accent)

            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.appSubheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText(value: progress))
        }
        .animation(
            reduceMotion ? nil : .linear(duration: 0.12),
            value: progress
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(appLocalized("Scanning progress")))
        .accessibilityValue(Text(progress.formatted(.percent.precision(.fractionLength(0)))))
    }

    @ViewBuilder
    private var actions: some View {
        if let action = presentation.primaryAction,
           let title = presentation.primaryActionTitle {
            Button {
                onAction(action)
            } label: {
                Text(title)
                    .font(.appHeadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }

        if let action = presentation.secondaryAction,
           let title = presentation.secondaryActionTitle {
            Button(title) { onAction(action) }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }
}

private struct ScannerHeroArtwork: View, Equatable {
    let cue: ALIReactionCue
    let maximumWidth: CGFloat

    var body: some View {
        ALIReactionView(cue: cue, maximumWidth: maximumWidth)
    }
}

struct ScannerLibraryStatusCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let summary: ScanSummary
    let isStale: Bool
    let allowance: ScannerAllowancePresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Text(appLocalized("Library Status"))
                    .font(.appHeadline)

                Spacer()

                if isStale {
                    Text(appLocalized("Needs refresh"))
                        .font(.appCaption)
                        .foregroundStyle(Color.statusNeedsReview)
                }
            }

            metricLayout {
                metric(
                    value: summary.completedAt.formatted(date: .abbreviated, time: .omitted),
                    label: appLocalized("Last Scan")
                )
                metric(
                    value: "\(summary.totalOpportunityCount)",
                    label: appLocalized("Opportunities")
                )
                metric(
                    value: ByteCountFormatter.string(
                        fromByteCount: summary.estimatedSavingsBytes,
                        countStyle: .file
                    ),
                    label: appLocalized("Reclaimable")
                )
            }

            if isStale {
                Text(appLocalized("These results are from before your photo library changed."))
                    .font(.appFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let allowance {
                Divider()
                ScannerAllowanceRow(allowance: allowance)
            }
        }
        .padding(Spacing.medium)
        .scannerHomeSurface()
    }

    private func metricLayout<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.small))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.small))
        return layout { content() }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(value)
                .font(.appHeadline)
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(label)
                .font(.appCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
    }
}

struct ScannerScanScopeCard: View {
    let allowance: ScannerAllowancePresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(appLocalized("What ALI checks"))
                .font(.appHeadline)

            scopeRow(
                icon: "square.stack.3d.up.fill",
                title: appLocalized("Similar Photos"),
                message: appLocalized("Groups of photos that look alike.")
            )
            scopeRow(
                icon: "camera.viewfinder",
                title: appLocalized("Screenshots"),
                message: appLocalized("Screen captures that may no longer be useful.")
            )
            scopeRow(
                icon: "drop.triangle",
                title: appLocalized("Blurred Photos"),
                message: appLocalized("Likely low-quality photos to review.")
            )

            if let allowance {
                Divider()
                ScannerAllowanceRow(allowance: allowance)
            }
        }
        .padding(Spacing.medium)
        .scannerHomeSurface()
    }

    private func scopeRow(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(title).font(.appSubheadline.weight(.semibold))
                Text(message)
                    .font(.appFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ScannerPremiumOfferCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.small) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accent)

                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(appLocalized("Unlock more with Alike Pro"))
                        .font(.appHeadline)
                    Text(appLocalized("Unlock unlimited scans, smart cleanup, and batch actions."))
                        .font(.appFootnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Spacing.small)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(Spacing.medium)
        }
        .buttonStyle(.plain)
        .scannerHomeSurface()
        .accessibilityHint(Text(appLocalized("Opens the upgrade options")))
    }
}

private struct ScannerAllowanceRow: View {
    let allowance: ScannerAllowancePresentation

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)
            Text(
                String(
                    format: appLocalized("%d of %d free scans remaining"),
                    allowance.remainingScans,
                    allowance.totalScans
                )
            )
            .font(.appFootnote)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
