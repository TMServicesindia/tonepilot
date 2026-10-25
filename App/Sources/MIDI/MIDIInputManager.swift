import CoreMIDI
import Foundation
import TonePilotCore

struct MIDISourceInfo: Identifiable, Hashable {
    let id: MIDIUniqueID
    let name: String
    let manufacturer: String?
    var looksLikeCasio: Bool {
        let n = (name + " " + (manufacturer ?? "")).uppercased()
        return n.contains("CASIO") || n.contains("CT-X")
    }
}

/// Receives MIDI from every connected source (the Casio arrives as a class-compliant
/// USB MIDI device through Apple's USB camera adapter) and reconnects automatically
/// when devices are plugged in or out — no app restart needed.
final class MIDIInputManager: ObservableObject, @unchecked Sendable {
    @Published private(set) var sources: [MIDISourceInfo] = []
    @Published private(set) var activity: [String] = []
    @Published private(set) var lastEventAt: Date?
    @Published private(set) var setupError: String?

    /// Called on the CoreMIDI receive thread. Keep it fast: route + send to samplers only.
    var onEvents: (([MIDIEvent]) -> Void)?
    /// Called on the main thread when a source disappears (to release held notes).
    var onSourcesChanged: ((_ removed: Bool) -> Void)?

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var connected: Set<MIDIEndpointRef> = []
    private var pendingLog: [String] = []
    private let logLock = NSLock()
    private var logFlushScheduled = false
    var loggingEnabled = true

    func start() {
        guard client == 0 else { return }
        var status = MIDIClientCreateWithBlock("TonePilot" as CFString, &client) { [weak self] notification in
            let id = notification.pointee.messageID
            guard id == .msgSetupChanged || id == .msgObjectAdded || id == .msgObjectRemoved else { return }
            let removed = id == .msgObjectRemoved
            DispatchQueue.main.async {
                self?.refreshSources()
                self?.onSourcesChanged?(removed)
            }
        }
        guard status == noErr else { setupError = "MIDI client error \(status)"; return }

        status = MIDIInputPortCreateWithProtocol(client, "TonePilot Input" as CFString, ._1_0, &port) { [weak self] eventList, _ in
            self?.receive(eventList)
        }
        guard status == noErr else { setupError = "MIDI input port error \(status)"; return }
        refreshSources()
    }

    /// Reconnects to every source currently present. Safe to call repeatedly ("Rescan").
    func refreshSources() {
        guard port != 0 else { return }
        var found: [MIDISourceInfo] = []
        var present: Set<MIDIEndpointRef> = []
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            guard src != 0 else { continue }
            present.insert(src)
            if !connected.contains(src) {
                if MIDIPortConnectSource(port, src, nil) == noErr { connected.insert(src) }
            }
            var uid: MIDIUniqueID = 0
            MIDIObjectGetIntegerProperty(src, kMIDIPropertyUniqueID, &uid)
            found.append(MIDISourceInfo(id: uid, name: stringProperty(src, kMIDIPropertyDisplayName) ?? "MIDI Source \(i + 1)",
                                        manufacturer: stringProperty(src, kMIDIPropertyManufacturer)))
        }
        for gone in connected.subtracting(present) { MIDIPortDisconnectSource(port, gone) }
        connected = connected.intersection(present)
        sources = found
    }

    private func stringProperty(_ obj: MIDIObjectRef, _ key: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(obj, key, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }

    // MARK: Receive (CoreMIDI thread)

    private func receive(_ list: UnsafePointer<MIDIEventList>) {
        var events: [MIDIEvent] = []
        for packet in list.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            withUnsafeBytes(of: packet.pointee.words) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                events += MIDIByteParser.parseUMPWords(Array(words.prefix(min(count, words.count))))
            }
        }
        guard !events.isEmpty else { return }
        onEvents?(events)
        if loggingEnabled { log(events) }
    }

    private func log(_ events: [MIDIEvent]) {
        logLock.lock()
        pendingLog += events.map(\.debugDescription)
        let shouldSchedule = !logFlushScheduled
        logFlushScheduled = true
        logLock.unlock()
        guard shouldSchedule else { return }
        // Batch UI updates (~15 Hz) so fast playing never floods the main thread.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.066) { [weak self] in
            guard let self else { return }
            self.logLock.lock()
            let lines = self.pendingLog
            self.pendingLog.removeAll()
            self.logFlushScheduled = false
            self.logLock.unlock()
            self.activity = Array((lines.reversed() + self.activity).prefix(60))
            self.lastEventAt = Date()
        }
    }

    func clearLog() { activity.removeAll() }
}
