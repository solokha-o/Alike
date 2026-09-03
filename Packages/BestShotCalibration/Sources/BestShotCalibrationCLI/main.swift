import BestShotCalibration
import Core
import Foundation

func printUsage() {
    let usage = """
    bestshot-calibrate — offline calibration harness for Best Shot scoring weights.

    USAGE:
      bestshot-calibrate report --corpus <path> [--output <path>] [--category <name>]
      bestshot-calibrate sweep --corpus <path> [--output report.md] [--config-output candidate.json] [--blur-penalty 5.0]

    report   Computes agreement/blur metrics for the shipped scoring config against a labelled corpus.
    sweep    Runs a deterministic search for candidate weights/thresholds and reports baseline vs candidate.

    Options:
      --corpus <path>          Path to a BestShotCalibrationCorpus JSON export. Required.
      --output <path>          Where to write the Markdown report. Defaults to stdout.
      --category <name>        report only: restrict input clusters to one BestShotCalibrationCategory
                                (people, kids, animals, night, motion, landscape, group, livePhoto).
      --config-output <path>   sweep only: where to write the candidate config JSON. Defaults to stdout
                                (appended after the report, separated by a marker line).
      --blur-penalty <double>  sweep only: weight of blurryWinnerRate in the search objective. Default 5.0.
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
    var configOutputPath: String?
    var blurPenalty: Double = WeightSweep.defaultBlurPenalty
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
        case "--config-output":
            options.configOutputPath = iterator.next()
        case "--blur-penalty":
            guard let raw = iterator.next(), let value = Double(raw) else {
                fail("--blur-penalty requires a numeric value")
            }
            options.blurPenalty = value
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

    let metrics = MetricsReport.compute(corpus: corpus, config: .current)
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
case "-h", "--help", "help":
    printUsage()
default:
    fail("Unknown subcommand: \(command)")
}
