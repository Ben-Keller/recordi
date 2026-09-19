// Standalone test runner: this Mac has Command Line Tools, without Xcode's XCTest framework.
import Foundation
import RecordiCore
var failures = 0
func fail(_ message: String, _ file: StaticString, _ line: UInt) { failures += 1; print("FAIL \(file):\(line): \(message)") }
func checkEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    do { let value = try a(); if value != b { fail("\(value) != \(b)", file, line) } } catch { fail(error.localizedDescription, file, line) }
}
func checkTrue(_ a: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) { checkEqual(try a(), true, file: file, line: line) }
func checkFalse(_ a: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) { checkEqual(try a(), false, file: file, line: line) }
func checkNil<T>(_ a: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) {
    do { if try a() != nil { fail("Expected nil", file, line) } } catch { fail(error.localizedDescription, file, line) }
}
func checkNotNil<T>(_ a: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) {
    do { if try a() == nil { fail("Expected value", file, line) } } catch { fail(error.localizedDescription, file, line) }
}
func checkThrows<T>(_ a: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try a(); fail("Expected error", file, line) } catch {}
}
func unwrap<T>(_ a: T?) throws -> T { guard let a else { throw RecordiError("Expected value") }; return a }
let suite = CoreTests()
let tests: [(String, () throws -> Void)] = [
    ("queue deduplication and path validation", suite.testQueueDeduplicatesAndRejectsOutsidePaths),
    ("sequential processing and completion persistence", suite.testSequentialOutputAndCompletionSurviveStateRemoval),
    ("failure, manual retry and interrupted recovery", suite.testFailureExplicitRetryAndInterruptedRecovery),
    ("missing dependencies and bad audio preserve sources", suite.testMissingDependenciesAndBadAudioFailWithoutDeleting),
    ("worker lock excludes duplicate processes", suite.testWorkerLockExcludesAnotherWorker),
    ("recording controls during background transcription", suite.testRecordingControlsRemainUsableDuringTranscription),
    ("recovery ignores active and unstable recordings", suite.testRecoveryDefersActiveUnknownAndUnstableFiles),
    ("command acknowledgements, timeout and missing app", suite.testBridgeAcknowledgementTimeoutAndMissingApp),
    ("actual Audio Hijack JavaScript with mocked API", suite.testGeneratedJavaScriptUsesActualStateAndRejectsMissingSession),
    ("literal process arguments and bounded timeout", suite.testProcessArgumentsAreLiteralAndTimeoutIsBounded),
    ("partial and malformed transcripts", suite.testMalformedOutputsAreNotSuccessful),
    ("cancellation requeues and changed sources fail safely", suite.testCancellationRequeuesAndSourceChangesFailSafely)
]
for (name, test) in tests {
    let before = failures
    do { try suite.setUpWithError(); try test() } catch { failures += 1; print("FAIL \(name): \(error)") }
    try? suite.tearDownWithError()
    print("\(failures == before ? "PASS" : "FAIL") \(name)")
}
print("\(tests.count) test groups, \(failures) failures")
exit(failures == 0 ? 0 : 1)
