import XCTest
@testable import Core

final class BestShotPersonalizedScoringConfigProviderTests: XCTestCase {
    private let global = PhotoQualityScoringConfig.current

    func testNoStoredWeightsReturnsGlobalConfigUnchanged() async {
        let repository = MockBestShotPersonalizationRepository()
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)

        let config = await provider.config()

        XCTAssertEqual(config, global)
    }

    func testStoredWeightsAreCarriedIntoTheConfig() async {
        let repository = MockBestShotPersonalizationRepository()
        let personal = BestShotPersonalWeights(
            withFaces: PhotoQualityScoringConfig.Weights(
                sharpness: 0.30,
                faceQuality: 0.35,
                exposure: 0.20,
                noiseArtifacts: 0.10,
                resolution: 0.05
            ),
            withoutFaces: PhotoQualityScoringConfig.Weights(
                sharpness: 0.65,
                faceQuality: 0,
                exposure: 0.20,
                noiseArtifacts: 0.10,
                resolution: 0.05
            ),
            scoringModelVersion: global.scoringModelVersion,
            withFacesExampleCount: 25,
            withoutFacesExampleCount: 15
        )
        await repository.setWeights(personal)
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)

        let config = await provider.config()

        XCTAssertEqual(config.weightsWithFaces, personal.withFaces)
        XCTAssertEqual(config.weightsWithoutFaces, personal.withoutFaces)
        // Everything else about the config is untouched.
        XCTAssertEqual(config.scoringModelVersion, global.scoringModelVersion)
        XCTAssertEqual(config.favoriteBonus, global.favoriteBonus)
    }

    func testResetMakesTheNextConfigCallGlobalAgain() async {
        let repository = MockBestShotPersonalizationRepository()
        let personal = BestShotPersonalWeights(
            withFaces: PhotoQualityScoringConfig.Weights(
                sharpness: 0.30,
                faceQuality: 0.35,
                exposure: 0.20,
                noiseArtifacts: 0.10,
                resolution: 0.05
            ),
            withoutFaces: PhotoQualityScoringConfig.Weights(
                sharpness: 0.65,
                faceQuality: 0,
                exposure: 0.20,
                noiseArtifacts: 0.10,
                resolution: 0.05
            ),
            scoringModelVersion: global.scoringModelVersion,
            withFacesExampleCount: 25,
            withoutFacesExampleCount: 15
        )
        await repository.setWeights(personal)
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)
        let personalizedConfig = await provider.config()
        XCTAssertNotEqual(personalizedConfig, global)

        await provider.reset()
        let configAfterReset = await provider.config()

        XCTAssertEqual(configAfterReset, global)
        let didReset = await repository.didReset
        XCTAssertTrue(didReset)
    }

    func testRecordOverrideRefitsAndCachesTheResult() async {
        let repository = MockBestShotPersonalizationRepository()
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)

        for index in 0..<20 {
            let example = BestShotOverrideExample(
                recordedAt: Date(timeIntervalSince1970: Double(index)),
                clusterHasFaces: false,
                componentDelta: PhotoQualityScoringConfig.Weights(
                    sharpness: -0.3,
                    faceQuality: 0,
                    exposure: 0.3,
                    noiseArtifacts: 0,
                    resolution: 0
                ),
                offsetDelta: 0,
                scoringModelVersion: global.scoringModelVersion
            )
            await provider.recordOverride(example)
        }

        let storedWeights = await repository.weights
        XCTAssertNotNil(storedWeights)
        XCTAssertEqual(storedWeights?.withoutFacesExampleCount, 20)

        // The cache reflects the fit without another repository round trip.
        let config = await provider.config()
        XCTAssertEqual(config.weightsWithoutFaces, storedWeights?.withoutFaces)
        XCTAssertNotEqual(config.weightsWithoutFaces, global.weightsWithoutFaces)
    }
}
