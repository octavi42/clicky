//
//  SimulationDemoComparisonWindowManager.swift
//  leanring-buddy
//
//  Manages the dedicated NSWindow that hosts the before/after demo
//  comparison screen (SimulationDemoComparisonView). Pressing Run on a
//  feature card in the cockpit posts the open notification, then the demo
//  conversation plays into the window's two columns.
//
//  Kept separate from the cockpit window on purpose: the presenter can
//  leave the cockpit on the laptop screen and drag this window to the
//  projector. Follows the same lifecycle pattern as
//  SimulationControlPanelWindowManager — one reusable window instance,
//  explicit app activation because the app is LSUIElement.
//

import AppKit
import SwiftUI

extension Notification.Name {
    static let clickyOpenSimulationDemoComparisonWindow = Notification.Name("clickyOpenSimulationDemoComparisonWindow")
}

@MainActor
final class SimulationDemoComparisonWindowManager: NSObject, NSWindowDelegate {
    private var comparisonWindow: NSWindow?
    private var openComparisonWindowObserver: NSObjectProtocol?

    private let companionManager: CompanionManager
    private let initialWindowWidth: CGFloat = 1100
    private let initialWindowHeight: CGFloat = 680

    init(companionManager: CompanionManager) {
        self.companionManager = companionManager
        super.init()

        openComparisonWindowObserver = NotificationCenter.default.addObserver(
            forName: .clickyOpenSimulationDemoComparisonWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showWindow()
        }
    }

    deinit {
        if let observer = openComparisonWindowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Window Lifecycle

    func showWindow() {
        if comparisonWindow == nil {
            createWindow()
        }

        // The app is LSUIElement (no dock icon), so it never activates on its
        // own. Without explicit activation the window would open behind the
        // frontmost app and receive no keyboard focus.
        NSApplication.shared.activate(ignoringOtherApps: true)
        comparisonWindow?.makeKeyAndOrderFront(nil)
    }

    private func createWindow() {
        let simulationDemoComparisonView = SimulationDemoComparisonView(
            simulationDemoEngine: companionManager.simulationDemoEngine
        )
        let hostingView = NSHostingView(rootView: simulationDemoComparisonView)

        let comparisonDemoWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialWindowWidth, height: initialWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        comparisonDemoWindow.title = "Clicky Demo — Before / After"
        comparisonDemoWindow.appearance = NSAppearance(named: .darkAqua)
        comparisonDemoWindow.backgroundColor = NSColor(DS.Colors.background)
        comparisonDemoWindow.titlebarAppearsTransparent = true
        // Keep the window instance alive after the user closes it so the
        // next Run press can reuse it instead of crashing on a
        // deallocated window.
        comparisonDemoWindow.isReleasedWhenClosed = false
        comparisonDemoWindow.minSize = NSSize(width: 1000, height: 620)
        comparisonDemoWindow.contentView = hostingView
        comparisonDemoWindow.center()
        comparisonDemoWindow.delegate = self

        comparisonWindow = comparisonDemoWindow
    }

    func windowWillClose(_ notification: Notification) {
        companionManager.simulationDemoEngine.stopActiveFeatureDemoRun()
    }
}
