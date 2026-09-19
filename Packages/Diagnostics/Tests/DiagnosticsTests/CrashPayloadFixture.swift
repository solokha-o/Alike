import Foundation

/// A trimmed MetricKit diagnostic payload in the shape `jsonRepresentation()` produces.
enum CrashPayloadFixture {
    static func data(appVersion: String = "1.5.0", build: String = "12") -> Data {
        Data(
            """
            {
              "timeStampBegin": "2026-09-18 00:00:00",
              "timeStampEnd": "2026-09-18 23:59:00",
              "crashDiagnostics": [
                {
                  "version": "1.0.0",
                  "diagnosticMetaData": {
                    "appBuildVersion": "\(build)",
                    "appVersion": "\(appVersion)",
                    "osVersion": "iPhone OS 18.6 (22G86)",
                    "deviceType": "iPhone14,3",
                    "bundleIdentifier": "com.alike.app",
                    "exceptionType": 1,
                    "signal": 11
                  },
                  "callStackTree": {
                    "callStackPerThread": true,
                    "callStacks": [
                      {
                        "threadAttributed": true,
                        "callStackRootFrames": [
                          {
                            "binaryUUID": "70B89F27-1634-3580-A695-57CDB41D7743",
                            "offsetIntoBinaryTextSegment": 1318192,
                            "sampleCount": 1,
                            "binaryName": "Alike",
                            "address": 4302655792
                          }
                        ]
                      }
                    ]
                  }
                }
              ]
            }
            """.utf8
        )
    }
}
