import AppKit
import PaneKit

extension WindowProbe {
    @MainActor
    static func runFocusLossChecks() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pane-focus-\(UUID().uuidString)")
        let notes = root.appendingPathComponent("notes")
        do {
            try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
            let filename = "focus-test.md"
            let note = notes.appendingPathComponent(filename)
            try "Focus test\n".write(to: note, atomically: true, encoding: .utf8)
            let settings = SettingsStore(store: JSONFileStore(url: root.appendingPathComponent("settings.json")))
            settings.update {
                $0.vaultPath = notes.path
                $0.showOnEverySpace = true
                $0.dismissMode = .sameHotkeyToggles
                $0.checkForUpdates = false
            }
            let state = StateStore(store: JSONFileStore(url: root.appendingPathComponent("state.json")))
            state.update {
                $0.notes[filename] = NoteState(lastOpened: Date(), isPinned: true)
                $0.panes = [PaneState(noteFilename: filename, autoSizing: false, manualHeight: 360)]
            }
            let vault = VaultService(vault: notes)
            let controller = PaneController(vault: vault, state: state, settings: settings)
            settings.onChange = { [weak controller] _ in controller?.applySettings() }
            let cover = FocusCoverPanel(
                contentRect: CGRect(x: 40, y: 80, width: 360, height: 240),
                styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false
            )
            cover.level = .popUpMenu
            cover.backgroundColor = .windowBackgroundColor
            cover.isReleasedWhenClosed = false
            defer {
                controller.dismiss()
                cover.orderOut(nil)
                controller.panel.orderOut(nil)
                vault.drain()
            }

            // A fresh CI runner may need several seconds to start the WebContent process.
            for _ in 0..<160 {
                if controller.currentFilename == filename { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard controller.currentFilename == filename else {
                check(false, "focus tests load only their temporary note")
                return
            }
            check(true, "focus tests load only their temporary note")

            controller.summon()
            await settle()
            check(controller.isVisible && controller.panel.isKeyWindow,
                  "an ordinary pane appears focused")
            let edited = "Focus test\nAn edit immediately before losing focus.\n"
            controller.editor(controller.editor, didReceive: .edited(text: edited, caret: edited.utf16.count))
            cover.makeKeyAndOrderFront(nil)
            await settle()
            check(!controller.isVisible, "without Keep on This Space, focus loss dismisses the pane")
            check(controller.panel.frame.maxX < 0,
                  "focus loss parks the pane offscreen instead of merely covering it")
            vault.drain()
            check((try? String(contentsOf: note, encoding: .utf8)) == edited,
                  "focus loss saves the last edit before hiding")
            check(controller.isPinned, "automatic hiding preserves the note's pin")

            cover.orderOut(nil)
            controller.toggle()
            await settle()
            check(controller.isVisible && controller.panel.isKeyWindow,
                  "the global hotkey recalls an automatically hidden pane with focus")

            settings.update { $0.showOnEverySpace = false }
            cover.makeKeyAndOrderFront(nil)
            await settle()
            check(controller.isVisible && !controller.panel.isKeyWindow,
                  "Keep on This Space retains an unfocused pane")
            try? await Task.sleep(nanoseconds: 100_000_000)
            controller.toggle()
            await settle()
            check(controller.isVisible && controller.panel.isKeyWindow,
                  "the hotkey refocuses a retained pane before toggling it away")
            try? await Task.sleep(nanoseconds: 100_000_000)
            controller.toggle()
            await settle()
            check(!controller.isVisible, "a focused retained pane can still be hidden by the hotkey")
            check(controller.isPinned, "manual hiding also preserves the note's pin")

            cover.orderOut(nil)
            settings.update { $0.showOnEverySpace = true }
            controller.summon()
            await settle()
            cover.makeKeyAndOrderFront(nil)
            cover.orderOut(nil)
            controller.panel.makeKeyAndOrderFront(nil)
            controller.editor.focusEditor()
            await settle()
            check(controller.isVisible && controller.panel.isKeyWindow,
                  "regaining focus in the same event cancels automatic hiding")

            settings.update { $0.showOnEverySpace = false }
            cover.makeKeyAndOrderFront(nil)
            await settle()
            check(controller.isVisible, "the pane remains before disabling Keep on This Space")
            settings.update { $0.showOnEverySpace = true }
            await settle()
            check(!controller.isVisible,
                  "disabling Keep on This Space also dismisses an already unfocused pane")

            cover.orderOut(nil)
            settings.update { $0.dismissMode = .escapeOnly }
            controller.summon()
            await settle()
            cover.makeKeyAndOrderFront(nil)
            await settle()
            check(!controller.isVisible, "focus loss also hides a pane in Esc only mode")
        } catch {
            check(false, "focus fixture: \(error)")
        }
    }
}

@MainActor
private final class FocusCoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
