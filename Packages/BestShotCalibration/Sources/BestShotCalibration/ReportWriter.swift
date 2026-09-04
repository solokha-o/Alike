import Core
import Foundation

/// Renders `MetricsReport`/`WeightSweep.Result` as Markdown, and encodes a
/// candidate `PhotoQualityScoringConfig` as pretty-printed, key-sorted JSON.
public enum ReportWriter {
    // MARK: - Metrics report

    public static func render(
        metrics: MetricsReport,
        corpus: BestShotCalibrationCorpus,
        warnings: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("# Best Shot Calibration Report")
        lines.append("")
        lines.append("- Corpus exported at: \(iso(corpus.exportedAt))")
        lines.append("- Corpus scoringModelVersion: \(corpus.scoringModelVersion)")
        lines.append("- Corpus thumbnailConfigVersion: \(corpus.thumbnailConfigVersion)")
        lines.append("- Clusters: \(corpus.entries.count)")
        lines.append("")

        if !warnings.isEmpty {
            lines.append("## Warnings")
            lines.append("")
            for warning in warnings {
                lines.append("> \(warning.replacingOccurrences(of: "\n", with: " "))")
            }
            lines.append("")
        }

        lines.append("## Overall metrics")
        lines.append("")
        lines.append(contentsOf: metricsTable(rows: [("overall", metrics.overall)]))
        lines.append("")

        lines.append("## Per-category metrics")
        lines.append("")
        if metrics.byCategory.isEmpty {
            lines.append("_No clusters._")
        } else {
            lines.append(
                contentsOf: metricsTable(rows: metrics.byCategory.map { ($0.key.displayName, $0.bucket) })
            )
        }
        lines.append("")

        lines.append(reportFooter)
        return lines.joined(separator: "\n") + "\n"
    }

    private static func metricsTable(rows: [(label: String, bucket: MetricsReport.Bucket)]) -> [String] {
        var lines: [String] = []
        lines.append(
            "| Slice | Clusters | Automatic | LowConf | Unresolved | Top-1 (resolved) | Top-1 (all) | Coverage "
                + "| Blurry winner rate | Offline override proxy |"
        )
        lines.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for (label, bucket) in rows {
            lines.append(
                "| \(label) | \(bucket.clusterCount) | \(bucket.automaticCount) | \(bucket.lowConfidenceCount) "
                    + "| \(bucket.unresolvedCount) | \(percentOrDash(bucket.topOneAgreement, of: bucket.resolvedClusterCount)) "
                    + "| \(percentOrDash(bucket.topOneAgreementOverAllClusters, of: bucket.clusterCount)) "
                    + "| \(percent(bucket.coverageRate)) "
                    + "| \(percentOrDash(bucket.blurryWinnerRate, of: bucket.winnerClusterCount)) "
                    + "| \(percentOrDash(bucket.offlineOverrideProxy, of: bucket.overrideEligibleClusterCount)) |"
            )
        }
        return lines
    }

    private static func percentOrDash(_ value: Double?, of sampleCount: Int) -> String {
        guard let value else { return "n/a (n=0)" }
        return "\(percent(value)) (n=\(sampleCount))"
    }

    // MARK: - Sweep report

    public static func render(sweep: WeightSweep.Result) -> String {
        var lines: [String] = []
        lines.append("# Best Shot Weight Sweep")
        lines.append("")
        lines.append("Blur penalty: \(sweep.blurPenalty)")
        lines.append("")

        lines.append("## Baseline vs candidate")
        lines.append("")
        lines.append(
            "| | Objective | Top-1 (all) | Top-1 (resolved) | Coverage | Blurry winner rate | Penalized blurry rate |"
        )
        lines.append("|---|---:|---:|---:|---:|---:|---:|")
        lines.append(
            "| Baseline | \(number(sweep.baselineScore.objective)) "
                + "| \(percent(sweep.baselineScore.topOneAgreementOverAllClusters)) "
                + "| \(percent(sweep.baselineScore.topOneAgreement)) "
                + "| \(percent(sweep.baselineScore.coverageRate)) "
                + "| \(percent(sweep.baselineScore.blurryWinnerRate)) "
                + "| \(percent(sweep.baselineScore.penalizedBlurryRate)) |"
        )
        lines.append(
            "| Candidate | \(number(sweep.candidateScore.objective)) "
                + "| \(percent(sweep.candidateScore.topOneAgreementOverAllClusters)) "
                + "| \(percent(sweep.candidateScore.topOneAgreement)) "
                + "| \(percent(sweep.candidateScore.coverageRate)) "
                + "| \(percent(sweep.candidateScore.blurryWinnerRate)) "
                + "| \(percent(sweep.candidateScore.penalizedBlurryRate)) |"
        )
        lines.append("")
        lines.append(
            "_Penalized blurry rate charges an unresolved cluster at the same "
                + "per-cluster rate as a blurry winner — refusing to answer never "
                + "beats answering correctly and unblurred. See the doc comment "
                + "on `WeightSweep.score`._"
        )
        lines.append("")

        lines.append("## Changed parameters")
        lines.append("")
        let changes = changedParameters(baseline: sweep.baselineConfig, candidate: sweep.candidateConfig)
        if changes.isEmpty {
            lines.append("_No parameter moved away from the baseline._")
        } else {
            lines.append("| Parameter | Baseline | Candidate |")
            lines.append("|---|---:|---:|")
            for change in changes {
                lines.append("| \(change.name) | \(number(change.baseline)) | \(number(change.candidate)) |")
            }
        }
        lines.append("")

        lines.append("## Sensitivity (all other parameters at the candidate config)")
        lines.append("")
        for parameter in sweep.sensitivity {
            lines.append("### \(parameter.parameterName)")
            lines.append("")
            lines.append(
                "| Value | Objective | Top-1 (all) | Top-1 (resolved) | Coverage | Blurry winner rate "
                    + "| Penalized blurry rate |"
            )
            lines.append("|---:|---:|---:|---:|---:|---:|---:|")
            for sample in parameter.samples {
                lines.append(
                    "| \(number(sample.value)) | \(number(sample.score.objective)) "
                        + "| \(percent(sample.score.topOneAgreementOverAllClusters)) "
                        + "| \(percent(sample.score.topOneAgreement)) "
                        + "| \(percent(sample.score.coverageRate)) "
                        + "| \(percent(sample.score.blurryWinnerRate)) "
                        + "| \(percent(sample.score.penalizedBlurryRate)) |"
                )
            }
            lines.append("")
        }

        lines.append(reportFooter)
        return lines.joined(separator: "\n") + "\n"
    }

    private struct ParameterChange {
        let name: String
        let baseline: Double
        let candidate: Double
    }

    private static func changedParameters(
        baseline: PhotoQualityScoringConfig,
        candidate: PhotoQualityScoringConfig
    ) -> [ParameterChange] {
        var changes: [ParameterChange] = []

        func compare(_ name: String, _ get: (PhotoQualityScoringConfig) -> Double) {
            let before = get(baseline)
            let after = get(candidate)
            if abs(before - after) > 1e-9 {
                changes.append(ParameterChange(name: name, baseline: before, candidate: after))
            }
        }

        compare("criticalSharpnessRatio") { $0.criticalSharpnessRatio }
        compare("strongPenaltySharpnessRatio") { $0.strongPenaltySharpnessRatio }
        compare("weakPenaltySharpnessRatio") { $0.weakPenaltySharpnessRatio }
        compare("absoluteSharpnessFloor") { $0.absoluteSharpnessFloor }
        compare("automaticSelectionMinimumScore") { $0.automaticSelectionMinimumScore }
        compare("automaticSelectionMinimumMargin") { $0.automaticSelectionMinimumMargin }
        compare("weightsWithFaces.sharpness") { $0.weightsWithFaces.sharpness }
        compare("weightsWithFaces.faceQuality") { $0.weightsWithFaces.faceQuality }
        compare("weightsWithFaces.exposure") { $0.weightsWithFaces.exposure }
        compare("weightsWithFaces.noiseArtifacts") { $0.weightsWithFaces.noiseArtifacts }
        compare("weightsWithFaces.resolution") { $0.weightsWithFaces.resolution }
        compare("weightsWithoutFaces.sharpness") { $0.weightsWithoutFaces.sharpness }
        compare("weightsWithoutFaces.faceQuality") { $0.weightsWithoutFaces.faceQuality }
        compare("weightsWithoutFaces.exposure") { $0.weightsWithoutFaces.exposure }
        compare("weightsWithoutFaces.noiseArtifacts") { $0.weightsWithoutFaces.noiseArtifacts }
        compare("weightsWithoutFaces.resolution") { $0.weightsWithoutFaces.resolution }

        return changes
    }

    // MARK: - Candidate config JSON

    /// Pretty-printed, key-sorted JSON. Deliberately does NOT bump
    /// `scoringModelVersion` — that decision, and applying these weights to
    /// `Packages/Core`, is the human applier's job, not this tool's.
    public static func encodeCandidateConfig(_ config: PhotoQualityScoringConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }

    // MARK: - Shared

    private static let reportFooter = """
    ---

    This report and any candidate config JSON emitted alongside it are inputs \
    to a manual review — bestshot-calibrate never writes into Packages/Core. \
    Applying a candidate config (copying its values into \
    PhotoQualityScoringConfig, and deciding whether that change warrants a \
    scoringModelVersion bump) is a separate, human step; the candidate JSON \
    here does not include one.
    """

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}
