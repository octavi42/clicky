//
//  SimulationControlPanelWindowManager.swift
//  leanring-buddy
//
//  Manages the dedicated NSWindow that hosts the presenter-only
//  "Clicky Memory Demo" control panel (SimulationControlPanelView).
//
//  Unlike the menu bar dropdown (a transient, non-activating NSPanel), this
//  is a regular titled, resizable window: the presenter keeps it open and
//  interacts with it during a meeting, so it needs focus, a title bar, and
//  standard close/minimize/resize behavior.
//
//  A single window instance is reused across opens — pressing the dropdown
//  button again surfaces the existing window instead of creating duplicates.
//

import AppKit
import SwiftUI

extension Notification.Name {
    static let clickyOpenSimulationControlPanel = Notification.Name("clickyOpenSimulationControlPanel")
}

@MainActor
final class SimulationControlPanelWindowManager: NSObject {
    private var controlPanelWindow: NSWindow?
    private var openControlPanelObserver: NSObjectProtocol?

    private let companionManager: CompanionManager
    private let initialWindowWidth: CGFloat = 900
    private let initialWindowHeight: CGFloat = 640

    init(companionManager: CompanionManager) {
        self.companionManager = companionManager
        super.init()

        openControlPanelObserver = NotificationCenter.default.addObserver(
            forName: .clickyOpenSimulationControlPanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showWindow()
        }
    }

    deinit {
        if let observer = openControlPanelObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Window Lifecycle

    func showWindow() {
        if controlPanelWindow == nil {
            createWindow()
        }

        // The app is LSUIElement (no dock icon), so it never activates on its
        // own. Without explicit activation the window would open behind the
        // frontmost app and receive no keyboard focus.
        NSApplication.shared.activate(ignoringOtherApps: true)
        controlPanelWindow?.makeKeyAndOrderFront(nil)
    }

    private func createWindow() {
        let simulationControlPanelView = SimulationControlPanelView(companionManager: companionManager)
        let hostingView = NSHostingView(rootView: simulationControlPanelView)

        let demoWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialWindowWidth, height: initialWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        demoWindow.title = "Clicky Memory Demo"
        demoWindow.appearance = NSAppearance(named: .darkAqua)
        demoWindow.backgroundColor = NSColor(DS.Colors.background)
        demoWindow.titlebarAppearsTransparent = true
        // Keep the window instance alive after the user closes it so the
        // next button press can reuse it instead of crashing on a
        // deallocated window.
        demoWindow.isReleasedWhenClosed = false
        demoWindow.minSize = NSSize(width: 860, height: 600)
        demoWindow.contentView = hostingView
        demoWindow.center()

        controlPanelWindow = demoWindow
    }
}
