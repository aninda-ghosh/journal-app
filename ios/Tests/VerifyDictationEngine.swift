import Foundation
import AVFoundation
import Speech

@main
struct VerifyDictationEngine {
    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "") {
        if actual != expected {
            print("❌ Assertion Failed: \(message)")
            print("  Expected: '\(expected)'")
            print("  Actual:   '\(actual)'")
            exit(1)
        }
    }

    @MainActor
    static func main() async {
        print("Running DictationEngine.swift continuous rambling validation tests...")

        let engine = DictationEngine(locale: Locale(identifier: "en-US"))

        // Test 1: Initial state
        assertEqual(engine.state, .idle, "Initial state must be .idle")
        assertEqual(engine.isRecording, false, "isRecording must be false initially")
        assertEqual(engine.currentText, "", "currentText must be empty initially")
        assertEqual(engine.audioLevel, 0.0, "audioLevel must be 0.0 initially")

        // Test 2: Check on-device model availability
        if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) {
            print("  · SFSpeechRecognizer available: \(recognizer.isAvailable)")
            if #available(iOS 13.0, macOS 10.15, *) {
                print("  · On-device recognition supported: \(recognizer.supportsOnDeviceRecognition)")
            }
        }

        // Test 3: Formatting and text joining (combineText)
        print("  · Testing combineText joining rules...")
        assertEqual(
            engine.combineText(committed: "", hypothesis: "Starting my ramble"),
            "Starting my ramble",
            "Empty committed should yield hypothesis"
        )
        assertEqual(
            engine.combineText(committed: "Starting my ramble", hypothesis: ""),
            "Starting my ramble",
            "Empty hypothesis should yield committed"
        )
        assertEqual(
            engine.combineText(committed: "Today was a good day.", hypothesis: "we went to the beach."),
            "Today was a good day. We went to the beach.",
            "Should auto-capitalize first letter after period"
        )
        assertEqual(
            engine.combineText(committed: "What a morning!", hypothesis: "everything worked."),
            "What a morning! Everything worked.",
            "Should auto-capitalize first letter after exclamation mark"
        )
        assertEqual(
            engine.combineText(committed: "Did that happen?", hypothesis: "i think so."),
            "Did that happen? I think so.",
            "Should auto-capitalize first letter after question mark"
        )
        assertEqual(
            engine.combineText(committed: "Hello world\n", hypothesis: "new paragraph"),
            "Hello world\nNew paragraph",
            "Should preserve newline and auto-capitalize"
        )
        assertEqual(
            engine.combineText(committed: "Part one", hypothesis: "part two"),
            "Part one part two",
            "Should space unpunctuated parts"
        )

        // Test 4: Simulated multi-utterance ramble with pauses
        print("  · Simulating continuous rambling across pauses...")
        // Utterance 1 in-flight
        engine.setTestHypothesis(current: "Today was a good day.")
        assertEqual(engine.currentText, "Today was a good day.")

        // Recognizer flushes on pause, starts Utterance 2
        // In the old implementation, this wiped out Utterance 1!
        // In the new implementation, Utterance 1 is committed and Utterance 2 appends:
        engine.setTestHypothesis(
            current: "we went for a long walk in the park.",
            committed: "Today was a good day."
        )
        assertEqual(
            engine.currentText,
            "Today was a good day. We went for a long walk in the park.",
            "Must preserve Utterance 1 when Utterance 2 starts after a pause"
        )

        // User pauses again, starts Utterance 3
        engine.setTestHypothesis(
            current: "and then we had coffee.",
            committed: "Today was a good day. We went for a long walk in the park."
        )
        assertEqual(
            engine.currentText,
            "Today was a good day. We went for a long walk in the park. And then we had coffee.",
            "Must preserve all previous utterances when Utterance 3 starts after another pause"
        )

        // Test 5: Cancel resets state cleanly
        print("  · Testing cancel resets...")
        engine.cancel()
        assertEqual(engine.state, .idle, "State must remain .idle after cancel")
        assertEqual(engine.currentText, "", "currentText must be empty after cancel")

        // Test 6: stopImmediately() synchronously captures in-flight hypothesis and halts
        print("  · Testing stopImmediately() instant stop and text capture...")
        engine.setTestListeningState(isListening: true)
        engine.setTestHypothesis(
            current: "and this was spoken right before tapping save.",
            committed: "Journal entry start."
        )
        assertEqual(engine.isRecording, true, "Engine must be recording before stop")
        let captured = engine.stopImmediately()
        assertEqual(
            captured,
            "Journal entry start. And this was spoken right before tapping save.",
            "stopImmediately must return full accumulated text instantly"
        )
        assertEqual(engine.isRecording, false, "Engine must not be recording after stopImmediately")
        assertEqual(engine.state, .idle, "State must be idle after stopImmediately")
        assertEqual(engine.currentText, "", "currentText must be reset to empty for next session")

        print("✓ All DictationEngine tests passed successfully!")
    }
}
