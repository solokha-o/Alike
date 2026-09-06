import BestShotCalibration
import Core
import Foundation

func printUsage() {
    let usage = """
    bestshot-calibrate — offline calibration harness for Best Shot scoring weights.

    USAGE:
      bestshot-calibrate report --corpus <path> [--output <path>] [--category <name>] [--config <path>]
      bestshot-calibrate sweep --corpus <path> [--output report.md] [--config-output candidate.json] [--blur-penalty 5.0]
      bestshot-calibrate personalize --corpus <path> [--output <path>] [--prefix 10,30,100] [--folds 5]

    report        Computes agreement/blur metrics for the shipped scoring config against a labelled corpus.
    sweep         Runs a deterministic search for candidate weights/thresholds and reports baseline vs candidate.
    personalize   Fits personal weights from a prefix of clusters (ordered by clusterID) and,
                  separately, via k-fold cross-validation, and checks whether personalisation ever
                  makes the held-out ranking worse than the global config. The verdict is keyed on
                  the k-fold aggregate, since that is the only view that both engages personalisation
                  and measures it on clusters the fit never saw; the prefix table is a shrinkage
                  curve alongside it. A regression guard, not a demonstration of gain — exits 0
                  either way.

    Options:
      --corpus <path>          Path to a BestShotCalibrationCorpus JSON export. Required.
      --output <path>          Where to write the Markdown report. Defaults to stdout.
      --category <name>        report only: restrict input clusters to one BestShotCalibrationCategory
                                (people, kids, animals, night, motion, landscape, group, livePhoto).
      --config <path>          report only: measure the corpus with this PhotoQualityScoringConfig JSON
                                file instead of the shipped PhotoQualityScoringConfig.current. Same JSON
                                shape `sweep --config-output` writes — use this to check a candidate
                                config before hand-applying it to Packages/Core.
      --config-output <path>   sweep only: where to write the candidate config JSON. Defaults to stdout
                                (appended after the report, separated by a marker line).
      --blur-penalty <double>  sweep only: weight of the penalized blurry rate in the search
                                objective. Must be finite and >= 0. Default 5.0.
      --prefix <sizes>         personalize only: comma-separated fit-set prefix sizes, each a
                                non-negative integer or the literal "all" (the whole corpus).
                                Duplicates collapse and every size clamps to the corpus size.
                                Default "10,30,100,all".
      --folds <k>              personalize only: number of cross-validation folds. Must be an
                                integer between 2 and the corpus size (rejected otherwise, same as
                                a malformed --prefix). Default 5.
    """
    FileHandle.standardError.write(Data((usage + "\n").utf8))
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("Error: " + message + "\n").utf8))
    printUsage()
    exit(1)
}

struct Options {
    var corpusPath: String?
    var outputPath: String?
    var category: String?
    var configPath: String?
    var configOutputPath: String?
    var blurPenalty: Double = WeightSweep.defaultBlurPenalty
    var prefix: String?
    var folds: String?
}

func parseOptions(_ args: [String]) -> Options {
    var options = Options()
    var iterator = args.makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--corpus":
            options.corpusPath = iterator.next()
        case "--output":
            options.outputPath = iterator.next()
        case "--category":
            options.category = iterator.next()
        case "--config":
            options.configPath = iterator.next()
        case "--config-output":
            options.configOutputPath = iterator.next()
        case "--blur-penalty":
            guard let raw = iterator.next(), let value = Double(raw) else {
                fail("--blur-penalty requires a numeric value")
            }
            // `Double("-5")` and `Double("nan")` both parse. A negative penalty
            // turns the unresolved/blurry charge into a reward, which hands the
            // search back the all-unresolved winner `WeightSweep.score` exists
            // to rule out; a NaN makes every `>` comparison false, so the
            // search silently keeps whatever it looked at first.
            guard value.isFinite, value >= 0 else {
                fail("--blur-penalty must be a finite value >= 0, got '\(raw)'")
            }
            options.blurPenalty = value
        case "--prefix":
            options.prefix = iterator.next()
        case "--folds":
            options.folds = iterator.next()
        default:
            fail("Unrecognized argument: \(arg)")
        }
    }
    return options
}

func write(_ text: String, to path: String?) {
    guard let path else {
        print(text, terminator: "")
        return
    }
    do {
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    } catch {
        fail("Could not write to \(path): \(error)")
    }
}

func loadCorpus(at path: String) -> CorpusLoader.LoadResult {
    let url = URL(fileURLWithPath: path)
    do {
        return try CorpusLoader.load(from: url)
    } catch {
        fail("Could not load corpus at \(path): \(error)")
    }
}

func loadScoringConfig(at path: String) -> PhotoQualityScoringConfig {
    let url = URL(fileURLWithPath: path)
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PhotoQualityScoringConfig.self, from: data)
    } catch {
        fail("Could not load scoring config at \(path): \(error)")
    }
}

func runReport(_ args: [String]) {
    let options = parseOptions(args)
    guard let corpusPath = options.corpusPath else { fail("report requires --corpus <path>") }

    let loadResult = loadCorpus(at: corpusPath)
    var corpus = loadResult.corpus

    if let categoryName = options.category {
        guard let category = BestShotCalibrationCategory(rawValue: categoryName) else {
            fail("Unknown --category '\(categoryName)'. Valid values: "
                + BestShotCalibrationCategory.allCases.map(\.rawValue).joined(separator: ", "))
        }
        corpus.entries = corpus.entries.filter { $0.category == category }
    }

    let scoringConfig = options.configPath.map(loadScoringConfig) ?? .current
    let metrics = MetricsReport.compute(corpus: corpus, config: scoringConfig)
    let report = ReportWriter.render(metrics: metrics, corpus: corpus, warnings: loadResult.warnings)
    write(report, to: options.outputPath)
}

func runSweep(_ args: [String]) {
    let options = parseOptions(args)
    guard let corpusPath = options.corpusPath else { fail("sweep requires --corpus <path>") }

    let loadResult = loadCorpus(at: corpusPath)
    let corpus = loadResult.corpus

    let result = WeightSweep.run(corpus: corpus, baseline: .current, blurPenalty: options.blurPenalty)
    var report = ReportWriter.render(sweep: result)
    if !loadResult.warnings.isEmpty {
        let warningBlock = loadResult.warnings.map { "> \($0.replacingOccurrences(of: "\n", with: " "))" }
            .joined(separator: "\n")
        report = "## Warnings\n\n\(warningBlock)\n\n" + report
    }
    write(report, to: options.outputPath)

    do {
        let configData = try ReportWriter.encodeCandidateConfig(result.candidateConfig)
        if let configOutputPath = options.configOutputPath {
            try configData.write(to: URL(fileURLWithPath: configOutputPath))
        } else if options.outputPath != nil {
            // Report already went to a file; the config still needs a home.
            print(String(data: configData, encoding: .utf8) ?? "")
        } else {
            print("\n--- candidate config JSON ---")
            print(String(data: configData, encoding: .utf8) ?? "")
        }
    } catch {
        fail("Could not encode candidate config: \(error)")
    }
}

func runPersonalize(_ args: [String]) {
    let options = parseOptions(args)
    guard let corpusPath = options.corpusPath else { fail("personalize requires --corpus <path>") }

    let loadResult = loadCorpus(at: corpusPath)
    let corpus = loadResult.corpus

    let prefixSpec = options.prefix ?? PersonalizationReport.defaultPrefixSpec
    let prefixSizes: [Int]
    do {
        prefixSizes = try PersonalizationReport.parsePrefixes(prefixSpec, corpusSize: corpus.entries.count)
    } catch {
        fail("Could not parse --prefix '\(prefixSpec)': \(error)")
    }

    let foldsSpec = options.folds ?? String(PersonalizationReport.defaultFolds)
    let folds: Int
    do {
        folds = try PersonalizationReport.parseFolds(foldsSpec, corpusSize: corpus.entries.count)
    } catch {
        fail("Could not parse --folds '\(foldsSpec)': \(error)")
    }

    let result = PersonalizationReport.run(corpus: corpus, prefixSizes: prefixSizes, global: .current)
    let kfoldResult = PersonalizationReport.runKFold(corpus: corpus, folds: folds, global: .current)
    var report = ReportWriter.render(
        personalization: result,
        kfold: kfoldResult,
        corpusClusterCount: corpus.entries.count
    )
    if !loadResult.warnings.isEmpty {
        let warningBlock = loadResult.warnings.map { "> \($0.replacingOccurrences(of: "\n", with: " "))" }
            .joined(separator: "\n")
        report = "## Warnings\n\n\(warningBlock)\n\n" + report
    }
    write(report, to: options.outputPath)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    printUsage()
    exit(1)
}

switch command {
case "report":
    runReport(Array(arguments.dropFirst()))
case "sweep":
    runSweep(Array(arguments.dropFirst()))
case "personalize":
    runPersonalize(Array(arguments.dropFirst()))
case "-h", "--help", "help":
    printUsage()
default:
    fail("Unknown subcommand: \(command)")
}
