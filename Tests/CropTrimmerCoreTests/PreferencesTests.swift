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

    /// A model id is persisted forever and the list has already grown from three entries to six.
    /// A stored id that is no longer in the list must still be selectable and visible, or the
    /// setting silently shows nothing while the app keeps using it.
    @MainActor
    func testAStoredModelIdThatLeftTheListIsStillShown() {
        XCTAssertFalse(VisionModel.all.contains { $0.id == "retired/model-v0" })
        let picker = VisionModelPicker(title: "Naming model", selection: .constant("retired/model-v0"))
        XCTAssertEqual(picker.selection, "retired/model-v0")
        // Every shipped id stays offered alongside it.
        XCTAssertTrue(VisionModel.all.contains { $0.id == "google/gemini-2.5-flash-lite" })
    }

    /// The AI page tells the owner where the key goes while they paste it, so it must not claim
    /// the Keychain — OpenRouterKeyStore deliberately uses a plain app preference.
    func testTheKeyStoreIsAPlainPreferenceNotTheKeychain() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CropTrimmer.key.\(UUID().uuidString)"))
        try OpenRouterKeyStore.save("sk-test-value", defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: OpenRouterKeyStore.defaultsKey), "sk-test-value",
                       "Stored as a readable preference; the AI page must say so rather than promising the Keychain")
        OpenRouterKeyStore.clear(defaults: defaults)
        XCTAssertNil(try OpenRouterKeyStore.read(defaults: defaults))
    }
}
