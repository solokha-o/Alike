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

        lines.append(contentsOf: faceCoverageSection(metrics.overall.faces))

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

    /// Whether the face branch of the model engages on this corpus at all.
    ///
    /// A `faceQuality` weight of 0.25 that never fires is not visible in any
    /// agreement figure — the ranker simply takes the without-faces weights and
    /// reports a perfectly plausible number. This section is where "we found
    /// faces and threw them all away" becomes readable.
    private static func faceCoverageSection(_ faces: MetricsReport.FaceCoverage) -> [String] {
        var lines: [String] = ["## Face coverage", ""]
        guard faces.candidateCount > 0 else {
            lines.append(faces.failedCount > 0
                ? "_No candidate could be measured (\(faces.failedCount) failed)._"
                : "_No candidates._")
            lines.append("")
            return lines
        }

        lines.append("| measured candidates | with faces | faces rejected only | rejection counts unknown | analysis failed |")
        lines.append("|---|---|---|---|---|")
        lines.append(
            "| \(faces.candidateCount) "
                + "| \(faces.withFacesCount) (\(percent(faces.withFacesRate ?? 0))) "
                + "| \(faces.rejectedOnlyCount) (\(percent(faces.rejectedOnlyRate ?? 0))) "
                + "| \(faces.unknownRejectionCount) "
                + "| \(faces.failedCount) |"
        )
        lines.append("")

        if faces.unknownRejectionCount > 0 {
            lines.append(
                "> \(faces.unknownRejectionCount) candidate(s) were measured before rejected faces were "
                    + "counted, so \"no faces\" and \"all faces rejected\" cannot be told apart for them. "
                    + "Re-measure the corpus to get this number to zero."
            )
            lines.append("")
        }

        let rejections = faces.rejections
        if rejections.isEmpty {
            lines.append("_No face was rejected._")
        } else {
            lines.append("| rejection reason | faces |")
            lines.append("|---|---|")
            lines.append("| below the confidence floor | \(rejections.lowConfidence) |")
            lines.append("| too small a share of the frame | \(rejections.tooSmallInFrame) |")
            lines.append("| too few real pixels to measure | \(rejections.insufficientResolution) |")
            lines.append("| crop or sampling failed | \(rejections.cropFailed) |")
        }
        lines.append("")
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

    // MARK: - Personalization report

    /// Renders both personalisation views and the one verdict built from
    /// whichever measurement can actually back it up.
    ///
    /// The prefix table (`personalization`) is a shrinkage curve: useful for
    /// seeing how the fit moves as more clusters feed it, but on a corpus
    /// this size personalisation may not even engage until the prefix
    /// consumes the whole corpus — leaving nothing to evaluate on. The
    /// k-fold view (`kfold`) is what the verdict is keyed on instead: every
    /// fold fits on the *other* folds and evaluates on clusters the fit
    /// never saw, so it is the only measurement that can both engage
    /// personalisation and hold out real eval data.
    public static func render(
        personalization: PersonalizationReport.Result,
        kfold: PersonalizationReport.KFoldResult,
        corpusClusterCount: Int
    ) -> String {
        var lines: [String] = []
        lines.append("# Best Shot Personalisation Regression Guard")
        lines.append("")
        lines.append("- Corpus clusters: \(corpusClusterCount)")
        lines.append(
            "- Both views order clusters by `clusterID`, sorted ascending — not chronologically. This "
                + "corpus was labelled in one sitting, so a per-cluster `recordedAt` would be fiction; "
                + "synthesised examples all carry a fixed timestamp instead."
        )
        lines.append(
            "- Personalisation only engages once a branch (with-faces / without-faces) has enough "
                + "examples; below that threshold a branch's weights come back identical to the global "
                + "config, and both tables below say so rather than implying a bug."
        )
        lines.append("")

        lines.append(personalizationPrefixSection(personalization))
        lines.append(personalizationKFoldSection(kfold, corpusClusterCount: corpusClusterCount))

        lines.append("## Verdict")
        lines.append("")
        for line in kfoldVerdict(kfold) {
            lines.append(line)
        }
        lines.append("")

        lines.append(reportFooter)
        return lines.joined(separator: "\n") + "\n"
    }

    /// The shrinkage-curve view: how the fit changes as the prefix grows.
    /// Carries no verdict of its own — see `render(personalization:kfold:corpusClusterCount:)`.
    private static func personalizationPrefixSection(_ personalization: PersonalizationReport.Result) -> String {
        var lines: [String] = []
        lines.append("## Personalisation vs baseline (prefix shrinkage curve)")
        lines.append("")
        lines.append(
            "| Prefix | Fit clusters | Examples (faces/no-faces) | Agreed | Unresolved | Refused "
                + "| Eval clusters | Engaged (faces/no-faces) | Top-1 (all) baseline "
                + "| Top-1 (all) personalized | Coverage baseline | Coverage personalized "
                + "| Blurry winner baseline | Blurry winner personalized |"
        )
        lines.append("|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|")

        for result in personalization.prefixResults {
            let fit = result.fit
            let examplesLabel = "\(fit.withFacesExampleCount)/\(fit.withoutFacesExampleCount)"
            let engagedLabel = "\(result.withFacesEngaged ? "yes" : "no")/\(result.withoutFacesEngaged ? "yes" : "no")"
            let row: String
            if let baseline = result.baseline, let personalized = result.personalized {
                row = "| \(result.prefixSize) | \(fit.fitClusterCount) | \(examplesLabel) "
                    + "| \(fit.agreementClusterCount) | \(fit.unresolvedClusterCount) | \(fit.refusedExampleCount) "
                    + "| \(result.evalClusterCount) | \(engagedLabel) "
                    + "| \(rateWithCorrectCount(baseline.topOneAgreementOverAllClusters, correct: baseline.correctClusterCount, of: baseline.clusterCount)) "
                    + "| \(rateWithCorrectCount(personalized.topOneAgreementOverAllClusters, correct: personalized.correctClusterCount, of: personalized.clusterCount)) "
                    + "| \(percent(baseline.coverageRate)) | \(percent(personalized.coverageRate)) "
                    + "| \(percentOrDash(baseline.blurryWinnerRate, of: baseline.winnerClusterCount)) "
                    + "| \(percentOrDash(personalized.blurryWinnerRate, of: personalized.winnerClusterCount)) |"
            } else {
                row = "| \(result.prefixSize) | \(fit.fitClusterCount) | \(examplesLabel) "
                    + "| \(fit.agreementClusterCount) | \(fit.unresolvedClusterCount) | \(fit.refusedExampleCount) "
                    + "| 0 | \(engagedLabel) | _no eval clusters_ | _no eval clusters_ | — | — | — | — |"
            }
            lines.append(row)
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// The held-out view the verdict is keyed on: fit on k-1 folds, evaluate
    /// on the one left out, repeated for every fold, then summed.
    private static func personalizationKFoldSection(
        _ kfold: PersonalizationReport.KFoldResult,
        corpusClusterCount: Int
    ) -> String {
        var lines: [String] = []
        lines.append("## K-fold cross-validation (k=\(kfold.folds))")
        lines.append("")
        lines.append(
            "Fold membership is deterministic: clusters sorted by `clusterID`, fold = index % k. Each "
                + "fold fits on the other k-1 folds and evaluates on the held-out fold, so — unlike the "
                + "prefix curve above — every row here can both engage personalisation and measure it on "
                + "clusters the fit never saw."
        )
        lines.append("")
        lines.append(
            "| Fold | Fit clusters | Examples (faces/no-faces) | Eval clusters | Engaged (faces/no-faces) "
                + "| Correct baseline | Correct personalized | Coverage baseline | Coverage personalized "
                + "| Blurry winner baseline | Blurry winner personalized |"
        )
        lines.append("|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|")

        for fold in kfold.foldResults {
            let examplesLabel = "\(fold.fit.withFacesExampleCount)/\(fold.fit.withoutFacesExampleCount)"
            let engagedLabel = "\(fold.withFacesEngaged ? "yes" : "no")/\(fold.withoutFacesEngaged ? "yes" : "no")"
            let row: String
            if let baseline = fold.baseline, let personalized = fold.personalized {
                row = "| \(fold.foldIndex) | \(fold.fit.fitClusterCount) | \(examplesLabel) "
                    + "| \(fold.evalClusterCount) | \(engagedLabel) "
                    + "| \(baseline.correctClusterCount)/\(baseline.clusterCount) "
                    + "| \(personalized.correctClusterCount)/\(personalized.clusterCount) "
                    + "| \(percent(baseline.coverageRate)) | \(percent(personalized.coverageRate)) "
                    + "| \(percentOrDash(baseline.blurryWinnerRate, of: baseline.winnerClusterCount)) "
                    + "| \(percentOrDash(personalized.blurryWinnerRate, of: personalized.winnerClusterCount)) |"
            } else {
                row = "| \(fold.foldIndex) | \(fold.fit.fitClusterCount) | \(examplesLabel) | 0 | \(engagedLabel) "
                    + "| _no eval clusters_ | _no eval clusters_ | — | — | — | — |"
            }
            lines.append(row)
        }
        lines.append("")

        lines.append("### Aggregate over folds")
        lines.append("")
        lines.append("| | Correct (sum) | Top-1 (all) | Coverage | Blurry winner |")
        lines.append("|---|---:|---:|---:|---:|")
        lines.append(aggregateRow(label: "Baseline", bucket: kfold.aggregateBaseline))
        lines.append(aggregateRow(label: "Personalized", bucket: kfold.aggregatePersonalized))
        lines.append("")

        for line in engagementSummary(kfold, corpusClusterCount: corpusClusterCount) {
            lines.append(line)
        }
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func aggregateRow(label: String, bucket: PersonalizationReport.AggregateBucket) -> String {
        "| \(label) | \(bucket.correctClusterCount)/\(bucket.clusterCount) "
            + "| \(rateWithCorrectCount(bucket.topOneAgreementOverAllClusters, correct: bucket.correctClusterCount, of: bucket.clusterCount)) "
            + "| \(percentOrDash(bucket.coverageRate, of: bucket.clusterCount)) "
            + "| \(percentOrDash(bucket.blurryWinnerRate, of: bucket.winnerClusterCount)) |"
    }

    /// Spells out per-branch engagement in words rather than leaving a
    /// reader to infer "never engaged" from a zero somewhere in the table.
    private static func engagementSummary(
        _ kfold: PersonalizationReport.KFoldResult,
        corpusClusterCount: Int
    ) -> [String] {
        var lines: [String] = []

        if kfold.withFacesEngagedAnyFold {
            let folds = kfold.foldResults.filter(\.withFacesEngaged).map { String($0.foldIndex) }
            lines.append("- with-faces branch: engaged in fold(s) \(folds.joined(separator: ", ")).")
        } else {
            lines.append(
                "- with-faces branch: **not engaged in any of the \(kfold.folds) folds** — only "
                    + "\(kfold.faceBearingClusterCount) of \(corpusClusterCount) corpus clusters carry a "
                    + "measured face, too few for this branch to reach the fit minimum on any fold."
            )
        }

        if kfold.withoutFacesEngagedAnyFold {
            let folds = kfold.foldResults.filter(\.withoutFacesEngaged).map { String($0.foldIndex) }
            lines.append("- without-faces branch: engaged in fold(s) \(folds.joined(separator: ", ")).")
        } else {
            lines.append("- without-faces branch: **not engaged in any of the \(kfold.folds) folds.**")
        }

        return lines
    }

    private static func rateWithCorrectCount(_ value: Double?, correct: Int, of total: Int) -> String {
        guard let value else { return "n/a" }
        return "\(percent(value)) (\(correct)/\(total))"
    }

    /// The verdict the CLI reports: keyed on the k-fold aggregate, since
    /// that is the only measurement that both engaged personalisation and
    /// held out real eval data. A tiny epsilon absorbs floating-point noise
    /// rather than flagging a difference that is really zero.
    private static func kfoldVerdict(_ kfold: PersonalizationReport.KFoldResult) -> [String] {
        guard kfold.withFacesEngagedAnyFold || kfold.withoutFacesEngagedAnyFold else {
            return [
                "Personalisation never engaged in any of the \(kfold.folds) folds, so this run measured "
                    + "nothing — there is no verdict to give on this corpus. See the engagement notes "
                    + "above for why.",
            ]
        }

        let epsilon = 1e-9
        let baseline = kfold.aggregateBaseline
        let personalized = kfold.aggregatePersonalized

        let baselineTopOne = baseline.topOneAgreementOverAllClusters ?? 0
        let personalizedTopOne = personalized.topOneAgreementOverAllClusters ?? 0
        let baselineCoverage = baseline.coverageRate ?? 0
        let personalizedCoverage = personalized.coverageRate ?? 0
        let baselineBlurry = baseline.blurryWinnerRate ?? 0
        let personalizedBlurry = personalized.blurryWinnerRate ?? 0

        var reasons: [String] = []
        if personalizedTopOne < baselineTopOne - epsilon {
            reasons.append(
                "aggregate top-1 (all) dropped from \(percent(baselineTopOne)) to \(percent(personalizedTopOne)) "
                    + "(\(baseline.correctClusterCount) -> \(personalized.correctClusterCount) correct of "
                    + "\(baseline.clusterCount))"
            )
        }
        if personalizedCoverage < baselineCoverage - epsilon {
            reasons.append("aggregate coverage dropped from \(percent(baselineCoverage)) to \(percent(personalizedCoverage))")
        }
        if personalizedBlurry > baselineBlurry + epsilon {
            reasons.append("aggregate blurry winner rate rose from \(percent(baselineBlurry)) to \(percent(personalizedBlurry))")
        }

        if reasons.isEmpty {
            return [
                "Personalisation did not regress the k-fold aggregate: top-1 (all) "
                    + "\(percent(baselineTopOne)) -> \(percent(personalizedTopOne)), coverage "
                    + "\(percent(baselineCoverage)) -> \(percent(personalizedCoverage)), blurry winner "
                    + "\(percent(baselineBlurry)) -> \(percent(personalizedBlurry)).",
            ]
        }
        return ["**Personalisation regressed the k-fold aggregate:** " + reasons.joined(separator: "; ") + "."]
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
