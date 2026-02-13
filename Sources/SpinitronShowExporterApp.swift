import SwiftUI
import AppKit
import UniformTypeIdentifiers

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - App Entry
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@main
struct SpinitrOnShowExporterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Content View
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct ContentView: View {

    enum AppState { case idle, exporting, done }
    enum OutputFormat: String, Hashable { case audio, youtube }

    // ── State ───────────────────────────────────────────────────────────
    @State private var appState:      AppState = .idle
    @State private var showURL        = ""
    @State private var coverImage:    NSImage? = nil
    @State private var outputFormat   = OutputFormat.audio
    @State private var debugMode      = false
    @State private var outputDir      = FileManager.default.urls(for: .downloadsDirectory,
                                                                  in: .userDomainMask).first!
    @State private var logOutput      = ""
    @State private var currentProcess: Process? = nil
    @State private var exportFailed   = false

    private var canExport: Bool { !showURL.isEmpty && appState == .idle }
    private var shortPath: String {
        outputDir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // ── Body ────────────────────────────────────────────────────────────
    var body: some View {
        Group {
            switch appState {
            case .idle:      idleView
            case .exporting: exportingView
            case .done:      doneView
            }
        }
        .frame(width: 400)
        .navigationTitle("Spinitron Show Exporter")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Idle View (Default)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // ── Form Group: Show URL ────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Show URL")
                    .font(.system(size: 13, weight: .medium))
                TextField(
                    text: $showURL,
                    prompt: Text("Paste Spinitron Show URL here")
                        .foregroundStyle(Color(white: 0.75))
                ) { EmptyView() }
                .font(.system(size: 13, weight: .medium))
                .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(Color(nsColor: .quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // ── Output ──────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Output")
                    .font(.system(size: 13, weight: .bold))

                VStack(spacing: 0) {
                    // Cover Image
                    HStack {
                        (Text("Cover Image ")
                            .font(.system(size: 13, weight: .medium))
                        + Text("(Optional)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary))
                        Spacer()
                        Button("Choose File") { pickImage() }
                    }
                    .frame(minHeight: 42)
                    .padding(.horizontal, 10)

                    Divider()

                    // Format
                    HStack {
                        Text("Format")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("", selection: $outputFormat) {
                            Text("Audio").tag(OutputFormat.audio)
                            Text("Youtube").tag(OutputFormat.youtube)
                        }
                        .pickerStyle(.radioGroup)
                        .horizontalRadioGroupLayout()
                        .labelsHidden()
                    }
                    .frame(minHeight: 42)
                    .padding(.horizontal, 10)

                    Divider()

                    // Save to
                    HStack {
                        (Text("Save to ")
                            .font(.system(size: 13, weight: .medium))
                        + Text(shortPath)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary))
                        Spacer()
                        Button("Change\u{2026}") { pickOutputDir() }
                    }
                    .frame(minHeight: 42)
                    .padding(.horizontal, 10)

                    Divider()

                    // Debug Mode
                    HStack {
                        (Text("Debug Mode ")
                            .font(.system(size: 13, weight: .medium))
                        + Text("(Export 5 min only)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { debugMode },
                            set: { newValue in
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    debugMode = newValue
                                }
                            }
                        ))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }
                    .frame(minHeight: 42)
                    .padding(.horizontal, 10)
                }
                .background(Color(nsColor: .quaternarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // ── Export Button ────────────────────────────────────────────
            Button("Export") { startExport() }
                .buttonStyle(.borderedProminent)
                .disabled(!canExport)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(20)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Exporting View
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var exportingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ── Title ───────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 2) {
                Text("Exporting")
                    .font(.system(size: 13, weight: .bold))
                Text(exportFailed ? "An error occurred." : "Please wait\u{2026}")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // ── Log Area ────────────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logOutput.isEmpty ? " " : logOutput)
                        .font(.system(size: 10, design: .monospaced).weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("logEnd")
                }
                .onChange(of: logOutput) { _, _ in
                    proxy.scrollTo("logEnd", anchor: .bottom)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200, idealHeight: 250)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(Color(nsColor: .quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // ── Bottom Actions ──────────────────────────────────────────
            HStack {
                if exportFailed {
                    Button("Back") {
                        appState = .idle
                        exportFailed = false
                        logOutput = ""
                    }
                } else {
                    Button("Cancel") { cancelExport() }
                }
                Spacer()
                Button("Copy Log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logOutput, forType: .string)
                }
                .buttonStyle(.borderless)
                .disabled(logOutput.isEmpty)
            }
        }
        .padding(20)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Done View
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var doneView: some View {
        VStack(spacing: 0) {
            Spacer()

            // ── Centered content ─────────────────────────────────────
            VStack(spacing: 16) {
                Text("Done!")
                    .font(.system(size: 13, weight: .bold))
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: outputDir.path)
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()

            // ── Bottom button ────────────────────────────────────────
            Button("Export New Show") {
                showURL = ""
                coverImage = nil
                outputFormat = .audio
                debugMode = false
                logOutput = ""
                appState = .idle
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a cover image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        coverImage = NSImage(contentsOf: url)
    }

    private func pickOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose output folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputDir = url
    }

    private func cancelExport() {
        currentProcess?.terminate()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Run Script
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func startExport() {
        guard canExport else { return }
        appState    = .exporting
        exportFailed = false
        logOutput   = ""

        // Snapshot state for the background thread
        let url      = showURL
        let youtube  = outputFormat == .youtube
        let debug    = debugMode
        let outDir   = outputDir

        // Convert cover image to JPEG on main thread (NSImage isn't thread-safe)
        var jpegData: Data? = nil
        if let img  = coverImage,
           let tiff = img.tiffRepresentation,
           let rep  = NSBitmapImageRep(data: tiff),
           let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) {
            jpegData = jpeg
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // ── Find the shell script ───────────────────────────────────
            guard let scriptPath = Self.findScript() else {
                DispatchQueue.main.async {
                    logOutput += "Could not find spinitron-export.sh\n"
                    logOutput += "Make sure the script is bundled in the app.\n"
                    exportFailed = true
                }
                return
            }

            // ── Save cover image ────────────────────────────────────────
            let coverDest = outDir.appendingPathComponent("cover.jpg")
            var didCopyCover = false
            if let jpeg = jpegData {
                do {
                    try jpeg.write(to: coverDest)
                    didCopyCover = true
                } catch {
                    DispatchQueue.main.async {
                        logOutput += "Warning: Could not save cover image.\n"
                    }
                }
            }

            // ── Build arguments ─────────────────────────────────────────
            var args = [scriptPath]
            if youtube { args.append("--youtube") }
            if debug   { args.append("--debug") }
            args.append(url)

            // ── Configure Process ───────────────────────────────────────
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = args
            process.currentDirectoryURL = outDir

            var env  = ProcessInfo.processInfo.environment
            let path = env["PATH"] ?? ""
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(path)"
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = pipe

            DispatchQueue.main.async { currentProcess = process }

            // ── Stream output ───────────────────────────────────────────
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { fh in
                let data = fh.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async { logOutput += str }
            }

            // ── Run ─────────────────────────────────────────────────────
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    logOutput += "\nError: \(error.localizedDescription)\n"
                    exportFailed = true
                }
            }

            handle.readabilityHandler = nil

            // ── Clean up temp cover.jpg ─────────────────────────────────
            if didCopyCover {
                try? FileManager.default.removeItem(at: coverDest)
            }

            // ── Transition state ────────────────────────────────────────
            let status = process.terminationStatus
            DispatchQueue.main.async {
                currentProcess = nil
                if status == 0 {
                    appState = .done
                } else if status == 15 {
                    // Cancelled — go back to idle
                    appState = .idle
                    logOutput = ""
                } else {
                    logOutput += "\nFailed (exit code \(status))\n"
                    exportFailed = true
                }
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Script Locator
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func findScript() -> String? {
        if let p = Bundle.main.path(forResource: "spinitron-export", ofType: "sh") {
            return p
        }
        var dir = URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("spinitron-export.sh")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }
}
