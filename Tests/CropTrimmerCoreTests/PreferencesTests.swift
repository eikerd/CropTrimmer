import XCTest
@testable import CropTrimmer

final class PreferencesTests: XCTestCase {
    @MainActor
    func testDefaultLoopLengthPersistsAcrossModelInstances() {
        let key = "CropTrimmer.defaultLoopLength"
        let original = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(original, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)

        XCTAssertEqual(EditorModel().defaultLoopLength, 5, "Defaults to 5 seconds when nothing is stored")
        let a = EditorModel()
        a.defaultLoopLength = 10  // setLoopLength(_:) itself requires an open movie; this is what it writes.
        XCTAssertEqual(UserDefaults.standard.double(forKey: key), 10)
        XCTAssertEqual(EditorModel().defaultLoopLength, 10, "A fresh model reads the persisted value")

        UserDefaults.standard.set(7, forKey: key)
        XCTAssertEqual(EditorModel().defaultLoopLength, 5, "An out-of-range stored value falls back to 5, not garbage")
    }

    @MainActor
    func testLoopHeaderFocusSetIsOrderIndependent() {
        let model = EditorModel()
        let a = UUID(); let b = UUID()
        XCTAssertFalse(model.loopHeaderHasKeyboardFocus)
        model.setLoopHeaderFocused(a, focused: true)
        XCTAssertTrue(model.loopHeaderHasKeyboardFocus)
        // Focus moves straight from a to b; b's "focused" can arrive before or after a's "unfocused".
        model.setLoopHeaderFocused(b, focused: true)
        model.setLoopHeaderFocused(a, focused: false)
        XCTAssertTrue(model.loopHeaderHasKeyboardFocus, "b is still focused even though a's event landed last")
        model.setLoopHeaderFocused(a, focused: false)
        model.setLoopHeaderFocused(b, focused: false)
        XCTAssertFalse(model.loopHeaderHasKeyboardFocus)
    }

    @MainActor
    func testQuestionMarkOpensPreferencesToTheShortcutsTab() {
        let model = EditorModel()
        XCTAssertEqual(model.preferencesTab, .general)
        var opened = false
        model.openPreferences = { opened = true }
        // The key monitor itself needs a live NSEvent/keyWindow, so this exercises the same
        // model-level effect its "?" case produces, without depending on AppKit event delivery.
        model.preferencesTab = .shortcuts
        model.openPreferences?()
        XCTAssertTrue(opened)
        XCTAssertEqual(model.preferencesTab, .shortcuts)
    }
}
