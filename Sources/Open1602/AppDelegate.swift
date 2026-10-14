import AnnoFormats
import AppKit
import MetalKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var controller: GameController?

    /// UserDefaults-Schlüssel für den zuletzt gewählten Spielordner.
    private static let dataPathKey = "GameDataPath"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
        guard let gameData = locateGameData() else {
            NSApp.terminate(nil)
            return
        }
        do {
            let view = GameView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768))
            let controller = try GameController(gameData: gameData, view: view)
            let window = NSWindow(
                contentRect: view.frame,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.contentView = view
            window.contentMinSize = NSSize(width: 320, height: 240)
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            window.delegate = controller
            self.window = window
            self.controller = controller
            controller.updateTitle()
            if let path = argument("--snapshot") {
                writeSnapshot(controller: controller, to: path)
                NSApp.terminate(nil)
                return
            }
            NSApp.activate()
        } catch {
            fail("Start fehlgeschlagen", error)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Sucht den Spielordner: `--data`, `OPEN1602_DATA`, Arbeitsverzeichnis, gespeicherter Pfad, sonst Auswahldialog.
    private func locateGameData() -> GameData? {
        if let data = try? GameData.locate(explicit: argument("--data")) { return data }
        if let saved = UserDefaults.standard.string(forKey: Self.dataPathKey),
            let data = try? GameData(root: URL(fileURLWithPath: saved))
        {
            return data
        }
        while true {
            let panel = NSOpenPanel()
            panel.message = "Bitte den Anno-1602-Spielordner wählen (enthält haeuser.cod)."
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            guard panel.runModal() == .OK, let url = panel.url else { return nil }
            do {
                let data = try GameData(root: url)
                UserDefaults.standard.set(data.root.path, forKey: Self.dataPathKey)
                return data
            } catch {
                fail("Kein Spielordner", error)
            }
        }
    }

    private func argument(_ name: String) -> String? {
        let args = CommandLine.arguments
        return args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    }

    /// `--snapshot DATEI [--viewer BSH --image N | --island SCP --zoom 0…2 --rotation 0…3]`: rendert ein Bild (2048×1536, Retina 2×) als PNG und beendet die App.
    private func writeSnapshot(controller: GameController, to path: String) {
        if argument("--viewer") != nil || argument("--image") != nil {
            controller.showViewer(file: argument("--viewer"), image: argument("--image").flatMap(Int.init) ?? 0)
        }
        if argument("--island") != nil {
            do {
                try controller.showIsland(
                    file: argument("--island"), zoom: argument("--zoom").flatMap(Int.init),
                    rotation: argument("--rotation").flatMap(Int.init))
            } catch {
                return fail("Insel konnte nicht geladen werden", error)
            }
        }
        let (width, height) = (2048, 1536)
        guard
            var pixels = controller.snapshot(width: width, height: height, backingScale: 2),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return fail("Snapshot fehlgeschlagen", CocoaError(.fileWriteUnknown)) }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let image = pixels.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: space, bitmapInfo: info.rawValue)?.makeImage()
        }
        guard let image else { return fail("Snapshot fehlgeschlagen", CocoaError(.fileWriteUnknown)) }
        let rep = NSBitmapImageRep(cgImage: image)
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        } catch {
            fail("Snapshot fehlgeschlagen", error)
        }
    }

    private func fail(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = String(describing: error)
        alert.runModal()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Open1602 beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let viewItem = NSMenuItem()
        menu.addItem(viewItem)
        let viewMenu = NSMenu(title: "Darstellung")
        viewMenu.addItem(withTitle: "Vollbild", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]
        viewItem.submenu = viewMenu
        return menu
    }
}
