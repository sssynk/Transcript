import SwiftUI

@main
struct TranscriptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(
                state: delegate.state,
                statsStore: delegate.statsStore,
                replacementStore: delegate.replacementStore
            )
        } label: {
            Image(systemName: "waveform")
        }

        Window("Transcript", id: "settings") {
            SettingsView(stats: delegate.statsStore, replacements: delegate.replacementStore)
        }
        .windowResizability(.contentSize)
    }
}

private struct MenuContent: View {
    var state: AppState
    var statsStore: StatsStore
    var replacementStore: ReplacementStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Hold Right ⌥ to dictate")
            .font(.system(.body, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)

        Divider()

        MicrophonePicker(state: state)

        Divider()

        Button("Settings...") {
            openWindow(id: "settings")
            NSApp.activate()
        }
        .keyboardShortcut(",")

        Button("Quit Transcript") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

private struct MicrophonePicker: View {
    @Bindable var state: AppState

    var body: some View {
        let devices = AudioDeviceManager.inputDevices()
        let defaultDev = AudioDeviceManager.defaultInputDevice()
        let defaultLabel = if let defaultDev { "System Default (\(defaultDev.name))" } else { "System Default" }

        Picker("Microphone", selection: $state.selectedDeviceUID) {
            Text(defaultLabel).tag("")
            ForEach(devices) { device in
                Text(device.name).tag(device.uid)
            }
        }
    }
}
